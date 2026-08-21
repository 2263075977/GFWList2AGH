# AGENTS.md — GFWList2AGH (slim) 开发指南

## 项目概览

精简版 fork，只做一件事：把多个上游域名列表合成一份**中国域名白名单**，供 SmartDNS 分流。

```
release.sh  ──►  gfwlist2domain/whitelist_full.txt  ──►  SmartDNS domain-set
```

上游的 AdGuardHome / Bind9 / DNSMasq / SmartDNS / Unbound 五种输出格式已全部移除。
**不要**为了「顺手」把它们加回来 —— 用不到的格式只会拖慢 CI 并增加维护面。

## 目录结构

```
.
├── release.sh                    唯一构建脚本
├── data/data_modify.txt          自定义规则（本地读取，改完 push 即生效）
├── gfwlist2domain/
│   └── whitelist_full.txt        唯一产物，由 CI 提交
└── .github/workflows/main.yml    每天 02:35 (UTC+8) 构建并 push
```

## 构建与验证

```bash
bash release.sh                   # 完整构建，约 30 秒
MIN_LINES=1 bash release.sh       # 放宽行数下限，调试用

# 保留 Temp/ 中间文件以便排查：让健全性检查故意失败即可
MIN_LINES=999999999 bash release.sh || true
ls Temp/
```

验证产物：

```bash
wc -l gfwlist2domain/whitelist_full.txt                          # 应约 112000
sort -u gfwlist2domain/whitelist_full.txt | cmp - gfwlist2domain/whitelist_full.txt   # 应无输出
grep -cvE '^[a-z0-9][a-z0-9.-]*[a-z0-9]$' gfwlist2domain/whitelist_full.txt || true   # 应为 0
```

## release.sh 的三段结构

| 函数 | 职责 |
| --- | --- |
| `GetData` | `curl` 拉取 12 个数据源到 `Temp/*.tmp`；`data_modify.txt` 从本地 `cp` |
| `AnalyseData` | 五步集合运算，产出 `cnacc_data.tmp` / `lite_cnacc_data.tmp` |
| `OutputData` | 合并 → 行数校验 → `mv` 就位 → 清理 `Temp/` |

核心逻辑：

```
白名单 = (国内候选 - 被墙域名 - 排除规则) ∪ 权威国内列表 ∪ 添加规则 - 移除规则
```

**GFW 列表虽然不产出，但必须继续拉取** —— 它是「国内候选 - 被墙域名」这一步的减数。

## 修改时的注意事项

### `set -euo pipefail` 与 grep

grep 无匹配时返回 1，在 `set -e` 下会中断脚本。**允许结果为空**的 grep 必须补 `|| true`
（`PickRule` 内部已包含）。真正不该为空的情况交给 `OutputData` 的行数下限统一拦截，
这样报错信息比 `set -e` 的静默退出清楚得多。

### 空正则陷阱

`ToPattern` 在列表为空时返回 `$^` 而非空串。原因：ERE 里空的 `()` 匹配一切，
`grep -Ev "()"` 会把整份白名单删光。改动这个函数前先想清楚这一点。

### 自定义规则标记

只有影响 **C（中国）列表**的标记会被解析：`(@%@) (@%!) (!&@) (@@@)` 加入，
`(!%!) (@&!) (!%@) (!!!)` 移除，`(*%*) (***)` 排除，`(!%*) (!**)` 关键词排除。
仅影响 G 列表的 `(@&@) (!&!) (*&*) (!&*)` 会被忽略 —— 因为本 fork 不产出黑名单。

### 数据源变更

改 `GetData` 里的数组即可。新增源后务必本地跑一次并对比行数变化，
突增或突降数千行通常意味着源的格式和预期不符。

## 等价性回归

改动 `AnalyseData` 后，用同一份数据快照对比新旧产物：

```bash
MIN_LINES=999999999 bash release.sh || true      # 生成 Temp/whitelist_full.out
git stash && MIN_LINES=999999999 bash release.sh || true
# 比对两次的 Temp/whitelist_full.out 的 md5
```

上游算法与本 fork 已验证逐字节等价（md5 `5e72cb3098525ef455a49801f94f0d68`，2026-08-21 数据快照）。

## CI

`.github/workflows/main.yml` 使用默认 `GITHUB_TOKEN` + `permissions: contents: write`，
产物无变化时跳过提交。**不要**引入外部远程脚本来做 push（上游的做法，供应链风险）。
