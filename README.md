# GFWList2AGH (slim)

精简自 [hezhijie0327/GFWList2AGH](https://github.com/hezhijie0327/GFWList2AGH)，**只产出一份中国域名白名单**，专供 SmartDNS 分流使用。

## 唯一产物

```
gfwlist2domain/whitelist_full.txt    纯域名列表，每行一个，约 11.2 万条
```

```bash
curl -O https://raw.githubusercontent.com/2263075977/GFWList2AGH/main/gfwlist2domain/whitelist_full.txt
```

SmartDNS 里这样用：

```
domain-set -name china -type list -file /etc/smartdns/china_domain.txt
nameserver /domain-set:china/domestic
```

## 自动更新

GitHub Actions 每天 **02:35 (UTC+8)** 构建并提交。下游拉取建议排在 04:00 之后，留出约 1.5 小时余量给 GitHub 的调度延迟（scheduled workflow 在高峰期能迟到半小时以上）和 raw CDN 缓存（约 5 分钟）。

> ⚠️ **Fork 后必做**：GitHub 会禁用 fork 仓库的所有 workflow。进 Actions 页点一次
> *"I understand my workflows, go ahead and enable them"*，`schedule` 才会开始跑。
> 也可以在 Actions 页手动 `Run workflow` 立即触发一次。

### 数据源挂了会怎样

原则是「宁可不更新，也不要把分流规则打残」：

`release.sh` 用 `curl -f` + 3 次重试，任一数据源返回非 2xx 直接中断构建；产物先写进 `Temp/`，通过 10 万行下限校验后才 `mv` 就位。构建失败时仓库里的上一版产物原样保留，下游拉到的仍是最后一份好数据。

> 建议消费端再加一道：拉取后校验行数与域名格式，装载失败自动回滚旧规则。

## 自定义规则

编辑 **本仓库的** `data/data_modify.txt`，push 后下次构建生效。

| 标记 | 作用 |
| --- | --- |
| `(@%@)` | 加入白名单（直连） |
| `(!%!)` | 移出白名单 |
| `(*%*)` | 排除域名及其子域名 |
| `(!%*)` | 按关键词排除 |
| `(@%!)` | 加入白名单，同时从 GFW 列表移除 |
| `(@&!)` | 加入 GFW 列表，同时从白名单移除（强制走代理） |

优先级：**移除(!) > 添加(@) > 排除(*)**

> ⚠️ 文件开头「自定义规则语法」段落里那些 `(***)example.org` **不是注释，是生效中的规则**。
> 其中 `(*%*)` / `(!%*)` 两条是唯一的排除规则来源，删掉不会有报错，但请留意其存在。
> （本 fork 已加空值保护，即使删光也不会像上游那样把白名单清空。）

## 本地构建

```bash
bash release.sh
# ✅ .../gfwlist2domain/whitelist_full.txt — 112066 个域名

MIN_LINES=1 bash release.sh    # 调试时放宽行数下限
```

依赖：`bash` `curl` `awk` `sed` `grep` `base64` `sort` `rev` `cut` `xargs`。

## 与上游的差异

| | 上游 | 本 fork |
| --- | --- | --- |
| 输出格式 | 7 种（AdGuardHome / Bind9 / DNSMasq / SmartDNS / Unbound / domain…） | 仅 `domain` 白名单 |
| 产物文件数 | 44 | 1 |
| `data_modify.txt` | 从上游作者仓库拉取，**本地文件不生效** | 读本仓库的 `data/data_modify.txt` |
| 构建耗时 | 数分钟（11 万次 `echo >>` × 7 格式） | 数十秒（一次 `sort -u`） |
| CI 推送 | `sudo bash` 上游作者的远程脚本，硬编码其用户名 | 内置 `git push`，`GITHUB_TOKEN` 最小权限 |
| 数据源失败 | 静默生成残缺产物并推送 | `curl -f` + 重试 + 行数下限，失败则保留旧产物 |
| 空排除规则 | 空正则 `()` 匹配一切，白名单被清空 | 回退为永不匹配的 `$^` |

算法本身**逐字节等价**：同一份数据快照下，新旧两版产出的 `whitelist_full.txt` md5 相同。

## 许可证

Apache License 2.0 with Commons Clause v1.0，见 [LICENSE](LICENSE)。
