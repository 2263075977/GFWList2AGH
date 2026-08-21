#!/bin/bash
###############################################################################
# GFWList2AGH (slim) — 中国域名白名单生成器
#
#   精简自 hezhijie0327/GFWList2AGH，只保留一个产物：
#     gfwlist2domain/whitelist_full.txt   纯域名列表，每行一个
#
#   供 SmartDNS 的 domain-set 使用：
#     domain-set -name china -type list -file /etc/smartdns/china_domain.txt
#
#   用法: bash release.sh
#   环境变量: MIN_LINES  产物行数下限，低于则判定构建失败（默认 100000）
###############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${REPO_ROOT}/Temp"
MODIFY_FILE="${REPO_ROOT}/data/data_modify.txt"
OUTPUT_FILE="${REPO_ROOT}/gfwlist2domain/whitelist_full.txt"
MIN_LINES="${MIN_LINES:-100000}"

# 合法域名：至少两段，全小写
DOMAIN_REGEX="^(([a-z]{1})|([a-z]{1}[a-z]{1})|([a-z]{1}[0-9]{1})|([0-9]{1}[a-z]{1})|([a-z0-9][-\.a-z0-9]{1,61}[a-z0-9]))\.([a-z]{2,13}|[a-z0-9-]{2,30}\.[a-z]{2,3})$"
# 顶级域名：仅 example.com / example.com.cn 这种两三段形式
LITE_DOMAIN_REGEX="^([a-z]{2,13}|[a-z0-9-]{2,30}\.[a-z]{2,3})$"


# ── 工具函数 ──────────────────────────────────────────────────

# 拉取数据源。HTTP 错误 / 超时直接失败，宁可整轮构建挂掉，
# 也不要拿半份数据生成残缺白名单推上去。
Fetch() {
    curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 15 --max-time 180 "$1"
}

# 从 data_modify.txt 提取指定标记的域名
#   $1 标记的 grep 模式    $2 域名正则
PickRule() {
    grep -v "#" "${WORK_DIR}/modify.tmp" \
        | grep "$1" \
        | tr -d "!%&()*@" \
        | grep -E "$2" \
        | sort | uniq || true
}

# 把域名列表压成 grep -E 用的 "a.com|b.com"
# ⚠️ 列表为空时必须返回永不匹配的模式：空的 () 在 ERE 里匹配一切，
#    会让后面的 grep -Ev 把整份白名单删光。
ToPattern() {
    local pattern
    pattern="$(xargs < "$1" | sed "s/ /|/g")"
    if [ -z "${pattern}" ]; then
        echo '$^'
    else
        echo "${pattern}"
    fi
}

# 集合差集：输出 $2 中不存在于 $1 的行
Subtract() {
    awk 'NR == FNR { tmp[$0] = 1 } NR > FNR { if ( tmp[$0] != 1 ) print }' "$1" "$2"
}


# ── 拉取数据 ──────────────────────────────────────────────────
GetData() {
    cnacc_domain=(
        "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/apple-cn.txt"
        "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt"
        "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/google-cn.txt"
        "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Surge/China/China_Domain.list"
    )
    cnacc_trusted=(
        "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf"
        "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/apple.china.conf"
        "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/google.china.conf"
    )
    # GFW 列表本身不产出，但白名单要把被墙域名从国内清单里剔掉，所以必须拉
    gfwlist_base64=(
        "https://raw.githubusercontent.com/Loukky/gfwlist-by-loukky/master/gfwlist.txt"
        "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt"
        "https://raw.githubusercontent.com/poctopus/gfwlist-plus/master/gfwlist-plus.txt"
    )
    gfwlist_domain=(
        "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"
        "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/greatfire.txt"
        "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt"
        "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Surge/Global/Global_Domain.list"
        "https://raw.githubusercontent.com/pexcn/gfwlist-extras/master/gfwlist-extras.txt"
    )

    rm -rf "${WORK_DIR}" && mkdir -p "${WORK_DIR}"

    for url in "${cnacc_domain[@]}"; do
        Fetch "${url}" | sed "s/^\.//g" >> "${WORK_DIR}/cnacc_domain.tmp"
    done
    for url in "${cnacc_trusted[@]}"; do
        Fetch "${url}" >> "${WORK_DIR}/cnacc_trusted.tmp"
    done
    for url in "${gfwlist_base64[@]}"; do
        Fetch "${url}" | base64 -d >> "${WORK_DIR}/gfwlist_base64.tmp"
    done
    for url in "${gfwlist_domain[@]}"; do
        Fetch "${url}" | sed "s/^\.//g" >> "${WORK_DIR}/gfwlist_domain.tmp"
    done

    # 自定义规则读本仓库的文件，不再拉上游仓库 —— 这是 fork 的意义所在
    cp "${MODIFY_FILE}" "${WORK_DIR}/modify.tmp"
}


# ── 计算白名单 ────────────────────────────────────────────────
AnalyseData() {
    cd "${WORK_DIR}"

    ## 1. 解析 data_modify.txt 的自定义规则（只取影响 C 列表的标记）
    PickRule "\(\@\%\@\)\|\(\@\%\!\)\|\(\!\&\@\)\|\(\@\@\@\)" "${DOMAIN_REGEX}"      > cnacc_addition.tmp
    PickRule "\(\!\%\!\)\|\(\@\&\!\)\|\(\!\%\@\)\|\(\!\!\!\)" "${DOMAIN_REGEX}"      > cnacc_subtraction.tmp
    PickRule "\(\*\%\*\)\|\(\*\*\*\)"                         "${DOMAIN_REGEX}"      > cnacc_exclusion.tmp
    PickRule "\(\*\%\*\)\|\(\*\*\*\)"                         "${LITE_DOMAIN_REGEX}" > lite_cnacc_exclusion.tmp
    PickRule "\(\!\%\*\)\|\(\!\*\*\)"                         "${DOMAIN_REGEX}"      > cnacc_keyword.tmp
    PickRule "\(\!\%\*\)\|\(\!\*\*\)"                         "${LITE_DOMAIN_REGEX}" > lite_cnacc_keyword.tmp
    cat cnacc_addition.tmp | grep -E "${LITE_DOMAIN_REGEX}" | sort | uniq > lite_cnacc_addition.tmp || true

    ## 2. 权威国内域名（felixonmars/dnsmasq-china-list），无条件信任
    cat cnacc_trusted.tmp | sed "s/\/114\.114\.114\.114//g;s/server\=\///g" \
        | tr "A-Z" "a-z" | grep -E "${DOMAIN_REGEX}" | sort | uniq > cnacc_trust.tmp
    cat cnacc_trust.tmp | grep -E "${LITE_DOMAIN_REGEX}" | sort | uniq > lite_cnacc_trust.tmp || true

    ## 3. 候选清单：国内域名 / 被墙域名
    cat cnacc_domain.tmp | sed "s/domain\://g;s/full\://g" \
        | tr "A-Z" "a-z" | grep -E "${DOMAIN_REGEX}" | sort | uniq > cnacc_checklist.tmp
    cat gfwlist_base64.tmp gfwlist_domain.tmp \
        | sed "s/domain\://g;s/full\://g;s/http\:\/\///g;s/https\:\/\///g" \
        | tr -d "|" | tr "A-Z" "a-z" | grep -E "${DOMAIN_REGEX}" | sort | uniq > gfwlist_checklist.tmp
    cat cnacc_checklist.tmp   | rev | cut -d "." -f 1,2 | rev | sort | uniq > lite_cnacc_checklist.tmp
    cat gfwlist_checklist.tmp | rev | cut -d "." -f 1,2 | rev | sort | uniq > lite_gfwlist_checklist.tmp

    ## 4. 国内域名 = 候选 - 被墙域名，再套排除/关键词规则
    cnacc_exclusion="$(ToPattern cnacc_exclusion.tmp)"
    cnacc_keyword="$(ToPattern cnacc_keyword.tmp)"
    lite_cnacc_exclusion="$(ToPattern lite_cnacc_exclusion.tmp)"
    lite_cnacc_keyword="$(ToPattern lite_cnacc_keyword.tmp)"

    Subtract gfwlist_checklist.tmp cnacc_checklist.tmp \
        | grep -Ev "(\.(${cnacc_exclusion})$)|(^${cnacc_exclusion}$)|(${cnacc_keyword})" > cnacc_raw.tmp || true
    Subtract lite_gfwlist_checklist.tmp lite_cnacc_checklist.tmp \
        | grep -Ev "(\.(${lite_cnacc_exclusion})$)|(^${lite_cnacc_exclusion}$)|(${lite_cnacc_keyword})" > lite_cnacc_raw.tmp || true

    ## 5. 汇总 → 减去移除规则（移除(!) > 添加(@) > 排除(*)）
    cat cnacc_raw.tmp lite_cnacc_raw.tmp cnacc_addition.tmp lite_cnacc_addition.tmp \
        cnacc_trust.tmp lite_cnacc_trust.tmp | sort | uniq > cnacc_added.tmp
    cat lite_cnacc_raw.tmp lite_cnacc_addition.tmp lite_cnacc_trust.tmp | sort | uniq > lite_cnacc_added.tmp

    Subtract cnacc_subtraction.tmp cnacc_added.tmp      > cnacc_data.tmp
    Subtract cnacc_subtraction.tmp lite_cnacc_added.tmp > lite_cnacc_data.tmp

    cd "${REPO_ROOT}"
}


# ── 写出产物 ──────────────────────────────────────────────────
OutputData() {
    cat "${WORK_DIR}/cnacc_data.tmp" "${WORK_DIR}/lite_cnacc_data.tmp" \
        | sort | uniq > "${WORK_DIR}/whitelist_full.out"

    # 健全性检查：数据源挂掉时保住仓库里的上一版产物，不覆盖
    lines="$(wc -l < "${WORK_DIR}/whitelist_full.out" | tr -d " ")"
    if [ "${lines}" -lt "${MIN_LINES}" ]; then
        echo "❌ 产物仅 ${lines} 行（下限 ${MIN_LINES}），数据源多半异常，保留旧产物" >&2
        exit 1
    fi

    mkdir -p "$(dirname "${OUTPUT_FILE}")"
    mv "${WORK_DIR}/whitelist_full.out" "${OUTPUT_FILE}"
    rm -rf "${WORK_DIR}"
    echo "✅ ${OUTPUT_FILE} — ${lines} 个域名"
}


## Process
GetData
AnalyseData
OutputData
