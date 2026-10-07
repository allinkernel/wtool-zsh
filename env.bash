# 迁移自 mytool/zsh/wsw-zshrc（原 wsw-zshrc）。与 env.zsh 等价（bash 版），
# 由 ~/.bashrc 里的 wtool 块 source。
#
# 这里的别名/函数本来就不依赖 zsh：路径拼接从 ${var:h} 换成 ${var%/*}，
# 其它（[[ ]]、command -v、alias、wslpath）bash 都认。
# 唯一刻意保留的"怪东西"是覆盖 pwd 的那个函数 —— 它是 pdd/pss 的基础。
[ -n "$WTOOL_PROJECT_DIR" ] || WTOOL_PROJECT_DIR="$HOME/.wtool/wtool-work-dir/links/shell/zsh"

export PATH=~/bin:$PATH
export LD_LIBRARY_PATH=~/usr/lib64

# 设置终端颜色为256真彩色，否则vim等的主题显示会受影响
export TERM=xterm-256color

# 这些都是简单的命令，根本不需要写个函数去实现
alias gs="git status"
alias gss="git status --short"
alias gd="git diff"
alias gds="git diff --staged"
alias gll="git log"
alias gl="git log"

alias s="ls"
alias sl="ls"
alias lks="ls"
alias kls="ls"

# 下边开始定义函数

# 往上找含 <target_dir> 的目录（bash 版：${var%/*} 代替 ${var:h}）
_up_to_have_dir ()
{
    target_dir=$1
    # 基于PWD变量比pwd命令要靠谱些, 不会因为当前路径不存在就让此函数陷入dead loop
    cur_dir=${PWD}
    while [ ! -e "${cur_dir}/${target_dir}" ]; do
        [ "${cur_dir}" = "/" ] && return 1
        case ${cur_dir} in
            */*) cur_dir=${cur_dir%/*} ;;
            *)   cur_dir=/ ;;
        esac
        [ -z "${cur_dir}" ] && cur_dir=/
    done
    echo "${cur_dir}"
    return 0
}

# 从本项目真实路径向上找到含 .repo 的目录（也就是 wtool 集合的根）
cw ()
{
    local d="${WTOOL_PROJECT_ROOT:-$PWD}"
    while [ "$d" != "/" ] && [ ! -e "$d/.repo" ]; do
        case $d in
            */*) d="${d%/*}" ;;
            *)   d=/ ;;
        esac
    done
    if [ -e "$d/.repo" ]; then
        cd "$d"
    else
        echo "cw: 找不到 .repo（不在 repo 工作区内？）" >&2
        return 1
    fi
}

unset -f gba 2>/dev/null
unalias gba 2>/dev/null
gba ()
{
    if command -v batcat >/dev/null 2>&1; then
        git branch -a | batcat
    else
        git branch -a | cat
    fi
}

pwd ()
{
    /usr/bin/pwd | tee /tmp/wsw-temp-pwd-id-$(id -u)
}

pdd ()
{
    cd $(cat /tmp/wsw-temp-pwd-id-$(id -u) | tr -d ' ')
}

pss ()
{
    cat /tmp/wsw-temp-pwd-id-$(id -u)
}

this_is_wsl ()
{
    [ -e /usr/bin/wslpath ] && return 0 || return 1
}

this_is_not_wsl ()
{
    [ ! -e /usr/bin/wslpath ] && return 0 || return 1
}

# ---------------------------------------------------------------------------
# win：把当前目录翻译成"别的机器也能用"的路径
#   WSL（有 wslpath）：Windows 路径，就是 `wslpath -w .`
#   非 WSL（普通服务器）：两行 —— samba 路径 + scp 路径
#     //<ip>/<share><相对路径>   share 取 /etc/samba/smb.conf 里最长前缀匹配的那个
#     <user>@<ip>:<绝对路径>     可以直接 `scp <文件> $(win 里第二行)/`
#   ip：优先 $WIN_IP，否则从 `ip -4 addr` 里取第一个非 lo 的地址
#   smb.conf 的路径可以用 $WTOOL_SMB_CONF 覆盖（默认 /etc/samba/smb.conf）
# ---------------------------------------------------------------------------

# 本机地址：优先 $WIN_IP；取不到就返回 1，由调用方报清楚
_win_ip ()
{
    if [ -n "${WIN_IP:-}" ]; then
        echo "${WIN_IP}"
        return 0
    fi
    command -v ip >/dev/null 2>&1 || return 1
    ip -4 addr show 2>/dev/null | awk '
        /^[0-9]+:[[:space:]]/ { iface = $2; sub(/:$/, "", iface); next }
        iface != "lo" && $1 == "inet" { sub(/\/.*/, "", $2); print $2; exit }
    '
}

# smb.conf 里的 [share] 和 path=，每行一条：share|path
_win_smb_shares ()
{
    awk '
        /^[[:space:]]*[#;]/ { next }
        /^[[:space:]]*\[[^]]+\]/ {
            share = $0
            sub(/^[[:space:]]*\[/, "", share)
            sub(/\].*$/, "", share)
            next
        }
        /^[[:space:]]*[Pp][Aa][Tt][Hh][[:space:]]*=/ {
            p = $0
            sub(/^[^=]*=[[:space:]]*/, "", p)
            sub(/[[:space:]]+$/, "", p)
            gsub(/^"|"$/, "", p)
            if (share != "" && p != "") print share "|" p
        }
    ' "$1"
}

# 非 WSL 分支：samba 路径 + scp 路径。算不出来就在 stderr 说清楚，绝不静默返回空。
_win_server ()
{
    local target ip conf shares line name spath sraw rel best best_rel best_len rc
    target=$(realpath -m -- "${1:-$PWD}" 2>/dev/null)
    [ -n "${target}" ] || target="${1:-$PWD}"

    ip=$(_win_ip)
    if [ -z "${ip}" ]; then
        echo "win: 拿不到本机 IP（WIN_IP 没设，ip addr 里也没有）。" >&2
        echo "     请在 .bashrc/.zshrc 里设 WIN_IP=<本机对外的地址>" >&2
        return 1
    fi

    conf="${WTOOL_SMB_CONF:-/etc/samba/smb.conf}"
    best=""; best_rel=""; best_len=0; rc=0
    if [ -r "${conf}" ]; then
        shares=$(_win_smb_shares "${conf}")
        while IFS= read -r line; do
            [ -n "${line}" ] || continue
            name="${line%%|*}"
            spath="${line#*|}"
            [ -n "${name}" ] && [ -n "${spath}" ] || continue
            sraw="${spath}"
            spath=$(realpath -m -- "${sraw}" 2>/dev/null)
            [ -n "${spath}" ] || spath="${sraw}"
            case "${target}" in
                "${spath}")   rel="" ;;
                "${spath}"/*) rel="${target#"${spath}"}" ;;
                *)            continue ;;
            esac
            if [ ${#spath} -gt ${best_len} ]; then
                best="${name}"
                best_rel="${rel}"
                best_len=${#spath}
            fi
        done <<EOF
${shares}
EOF
        if [ -n "${best}" ]; then
            echo "//${ip}/${best}${best_rel}"
        else
            echo "win: ${conf} 里没有 share 的 path 匹配 ${target}" >&2
            rc=1
        fi
    else
        echo "win: 读不到 samba 配置 ${conf}" >&2
        rc=1
    fi
    echo "$(whoami)@${ip}:${target}"
    return ${rc}
}

win ()
{
    if this_is_wsl; then
        wslpath -w . || return 1
        return 0
    fi
    _win_server "$@"
}

start ()
{
    this_is_not_wsl && echo "only wsl support this" && return 1
    powershell.exe -Command "Set-Location -Path \"$(win)\"; Start-Process $1"
}

# ---------------------------------------------------------------------------
# wrg：在当前目录树下按"构建目标名"找 Android.bp / Android.mk / Makefile
#   wrg <名字>      精确匹配目标名
#   wrg -i <片段>   模糊匹配（目标名里含这个片段，忽略大小写）
# 认三类文件：
#   Android.bp  → name: "xxx"
#   Android.mk  → LOCAL_MODULE / LOCAL_PACKAGE_NAME
#   其它 Makefile（Makefile / makefile / GNUmakefile / *.mk（Android.mk 除外）/ *.mak）
#               → 构建目标名：规则行（^[[:space:]]*目标([[:space:]]+目标)*[[:space:]]*:）
#                 冒号前那串不含 = $ # 的词，外加 .PHONY: 声明的那些词；一行多个目标逐个算
# 输出：文件:行号:命中行（路径形状与 find 一致带 ./ 前缀，按文件+行号排序；
#   命中的那一段在终端里高亮，管道/重定向时不着色）
# 搜索后端：rg → fd（按 fdfind / fd-find / fd 探测）→ find，前一个没有才用下一个。
#   rg / fd 默认跳过隐藏目录和 .gitignore 里的目录（例如 .repo/、out/），更快；
#   要连这些目录一起搜（find 的老行为）就用 WRG_SEARCH=find。
#   WRG_SEARCH=auto(默认)/rg/fd/find、WRG_COLOR=auto(默认)/always/never 是测试和兜底用的：
#   指定了就必须用它，找不到那个可执行文件就报错（rc=2），不会偷偷换成别的。
# ---------------------------------------------------------------------------
_WRG_FD_GLOB='{Android.bp,Android.mk,Makefile,makefile,GNUmakefile,*.mk,*.mak}'   # fd 的 -g 是"开关"（不带参数），所有文件名合成一个 glob

# 三种后端共用的一段 awk：WRG_PASS=search 扫文件出结果；WRG_PASS=recheck 给 stdin 上的
# "路径:行号:原文" 做真判命中（rg 那三套正则只是粗筛，判命中一定回到这里）；
# WRG_PASS=paint 给同一形状的行上色（高亮 = \033[1;31m … \033[0m，只包住命中的那一段）。
# 判命中 / 抠目标名的逻辑只有这一份，三个后端共用，保证输出一致。
_WRG_AWK='BEGIN {
    pat = ENVIRON["WRG_PAT"]; lpat = tolower(pat); fuzzy = ENVIRON["WRG_FUZZY"] + 0
    pass = ENVIRON["WRG_PASS"]
}
function norm(p) {
    if (p ~ /^\// || p ~ /^\.\//) return p
    return "./" p
}
function base(p,   b) {
    b = p; sub(/.*\//, "", b); return b
}
# 文件分三类：1 = Android.bp，2 = Android.mk，3 = 其它 Makefile（按目标名找），
# 0 = 不归 wrg 管（rg 的 --type make 会多带 Makefile.am / Makefile.in，落这儿丢掉）
function kind(p,   b) {
    b = base(p)
    if (b == "Android.bp") return 1
    if (b == "Android.mk") return 2
    if (b == "Makefile" || b == "makefile" || b == "GNUmakefile") return 3
    if (b ~ /[.]mk$/ || b ~ /[.]mak$/) return 3
    return 0
}
# 这个候选值算不算命中：精确比整个名字，模糊找子串（忽略大小写）
function hit(val) {
    if (fuzzy) return index(tolower(val), lpat) - 1
    return (val == pat) ? 0 : -1
}
# 把 s 按空白切成词：词进全局 W[]，它在"整行"里的起始下标（1 基）进全局 WO[]，
# 高亮就靠 WO[] 定位。off 是 s 在整行里的 0 基偏移。返回词数。
function words(s, off,   n, i, c, cnt, start) {
    n = length(s); cnt = 0; start = 0
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c ~ /[[:space:]]/) { start = 0; continue }
        if (start == 0) { cnt++; W[cnt] = ""; WO[cnt] = off + i; start = i }
        W[cnt] = W[cnt] c
    }
    return cnt
}
# 规则行：^[[:space:]]*<目标>([[:space:]]+<目标>)*[[:space:]]*:
# 返回冒号前那串（含行首空白）；不是规则行返回空串。
# 目标必须是"不含 = $ # 的词"：扫到这三个字符里的任何一个就否决整行
# （VAR ?= x / VAR = x / ifeq (...) / include $(...) / # 注释 都在这儿挡掉）；
# 冒号紧跟 = 的是赋值不是规则（VAR := x），::= 也是赋值。
function rule_prefix(line,   i, n, c) {
    n = length(line); i = 1
    while (i <= n && substr(line, i, 1) ~ /[[:space:]]/) i++
    while (i <= n) {
        c = substr(line, i, 1)
        if (c == "=" || c == "$" || c == "#") return ""
        if (c == ":") {
            if (substr(line, i + 1, 1) == "=") return ""
            if (substr(line, i + 1, 1) == ":" && substr(line, i + 2, 1) == "=") return ""
            return substr(line, 1, i - 1)
        }
        i++
    }
    return ""
}
# Makefile 一行里的候选目标：规则行冒号前那串词，外加 .PHONY: 声明的词
# （声明部分在 # 注释处截断）。一行里可能有多个目标，挨个试，第一个命中的
# 写进全局 v / vs 并返回 1。
function cand_make(line,   pre, cnt, i, ph, rest, cut, rn, w) {
    pre = rule_prefix(line)
    if (pre == "") return 0
    ph = 0; cnt = words(pre, 0)
    for (i = 1; i <= cnt; i++) {
        if (W[i] == ".PHONY") ph = 1
        if (hit(W[i]) >= 0) { v = W[i]; vs = WO[i]; return 1 }
    }
    if (!ph) return 0
    rest = substr(line, length(pre) + 2)          # 冒号（在 length(pre)+1）之后
    cut = index(rest, "#")
    if (cut > 0) rest = substr(rest, 1, cut - 1)
    rn = words(rest, length(pre) + 1)
    for (i = 1; i <= rn; i++) {
        w = W[i]
        if (w ~ /[$=\\]/) continue                # .PHONY: $(TARGETS) / 续行反斜杠 不算
        if (hit(w) >= 0) { v = w; vs = WO[i]; return 1 }
    }
    return 0
}
function cand_bp(line) {
    if (match(line, /^[[:space:]]*name[[:space:]]*:[[:space:]]*"[^"]*"/)) {
        v = substr(line, RSTART, RLENGTH)
        sub(/^[^"]*"/, "", v); sub(/"[[:space:]]*$/, "", v)
        vs = RSTART + RLENGTH - 1 - length(v)
        return (hit(v) >= 0)
    }
    return 0
}
function cand_mk(line) {
    if (match(line, /^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*[^[:space:]#]+/)) {
        v = substr(line, RSTART, RLENGTH)
        sub(/^[^=]*=[[:space:]]*/, "", v)
        vs = RSTART + RLENGTH - length(v)
        return (hit(v) >= 0)
    }
    return 0
}
function cand(p, line,   k) {
    k = kind(p)
    if (k == 1) return cand_bp(line)
    if (k == 2) return cand_mk(line)
    if (k == 3) return cand_make(line)
    return 0
}
# 把 "路径:行号:原文" 拆进全局 fp / fl / ft，拆不开返回 0
function split3(s,   i1, i2) {
    i1 = index(s, ":")
    if (i1 == 0) return 0
    i2 = i1 + index(substr(s, i1 + 1), ":")
    if (i2 == i1) return 0
    fp = substr(s, 1, i1 - 1); fl = substr(s, i1 + 1, i2 - i1 - 1); ft = substr(s, i2 + 1)
    return 1
}
pass == "paint" {
    if (!split3($0)) { print; next }
    if (!cand(fp, ft)) { print; next }
    o = hit(v)
    if (o < 0 || v == "") { print; next }
    len = fuzzy ? length(pat) : length(v)
    print fp ":" fl ":" substr(ft, 1, vs - 1 + o) "\033[1;31m" substr(ft, vs + o, len) "\033[0m" substr(ft, vs + o + len)
    next
}
pass == "recheck" {
    if (!split3($0)) next
    if (!cand(fp, ft)) next
    print
    next
}
{
    p = norm(FILENAME)
    if (!cand(p, $0)) next
    print p ":" FNR ":" $0
}
'

_wrg_usage ()
{
    echo "Usage: wrg <名字>        # 精确匹配目标名"
    echo "       wrg -i <片段>     # 模糊匹配（子串、忽略大小写）"
}

# 挑搜索后端：打印要用的可执行名（find 就是字面量 find）。
# WRG_SEARCH=auto 按 rg → fdfind → fd-find → fd 探测，都没有就用 find；
# 指定成 rg / fd / find 时就必须存在，否则 stderr 报错并返回 2。
_wrg_backend ()
{
    local c
    case "${WRG_SEARCH:-auto}" in
        auto|'')
            for c in rg fdfind fd-find fd; do
                if command -v "$c" >/dev/null 2>&1; then printf '%s\n' "$c"; return 0; fi
            done
            printf 'find\n'; return 0 ;;
        rg)
            if command -v rg >/dev/null 2>&1; then printf 'rg\n'; return 0; fi
            echo "wrg: WRG_SEARCH=rg 但 PATH 里没有 rg" >&2
            return 2 ;;
        fd)
            for c in fdfind fd-find fd; do
                if command -v "$c" >/dev/null 2>&1; then printf '%s\n' "$c"; return 0; fi
            done
            echo "wrg: WRG_SEARCH=fd 但 PATH 里没有 fdfind / fd-find / fd" >&2
            return 2 ;;
        find) printf 'find\n'; return 0 ;;
        *)
            echo "wrg: WRG_SEARCH 只认 auto / rg / fd / find（现在是 ${WRG_SEARCH}）" >&2
            return 2 ;;
    esac
}

# 把目标名里对正则（rg 用的那种 ERE）有意义的字符转义成字面量
_wrg_re_escape ()
{
    printf '%s' "${1}" | awk '
        { out = ""; n = length($0)
          for (i = 1; i <= n; i++) {
              c = substr($0, i, 1)
              if (index("\\^$.*+?()[]{}|", c) > 0) out = out "\\"
              out = out c
          }
          printf "%s", out }'
}

# 要不要上色：WRG_COLOR=auto（默认，只有 stdout 是终端才上色）/ always / never；
# NO_COLOR 非空时一律不上色（优先级最高）。返回 0 上色 / 1 不上色 / 2 取值不认（已报错）。
_wrg_color ()
{
    case "${WRG_COLOR:-auto}" in
        auto|'') [ -t 1 ] || return 1 ;;
        always)  ;;
        never)   return 1 ;;
        *)
            echo "wrg: WRG_COLOR 只认 auto / always / never（现在是 ${WRG_COLOR}）" >&2
            return 2 ;;
    esac
    [ -n "${NO_COLOR:-}" ] && return 1
    return 0
}

wrg ()
{
    local fuzzy=0 pat out rc tool errname brc color crc esc o1 o2 o3 r1 r2 r3 re_bp re_mk re_make
    case "${1:-}" in
        -h|--help) _wrg_usage; return 0 ;;
        -i)        fuzzy=1; shift ;;
        -*)        echo "wrg: 不认识的选项 ${1}" >&2; _wrg_usage >&2; return 2 ;;
    esac
    if [ $# -ne 1 ] || [ -z "${1}" ]; then
        _wrg_usage >&2
        return 2
    fi
    pat="${1}"

    tool=$(_wrg_backend); brc=$?
    if [ ${brc} -ne 0 ]; then return ${brc}; fi

    color=0
    _wrg_color; crc=$?
    if [ ${crc} -eq 2 ]; then return 2; fi
    if [ ${crc} -eq 0 ]; then color=1; fi

    case "${tool}" in
    rg)
        errname="${tool}"
        # 先看树里有没有这三类文件（rg --files 只看文件名，和后面的搜索遵守同一套 ignore 规则）
        if [ -z "$("${tool}" --files -g Android.bp -g Android.mk -g Makefile -g makefile -g GNUmakefile -g '*.mk' -g '*.mak' . 2>/dev/null | head -n 1)" ]; then
            echo "wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile" >&2
            return 1
        fi
        # 三类文件的写法不一样 → 各搜一次再合并；值要做正则转义，
        # 关键词那部分的大小写要敏感（模糊只对值用 (?i:...)）
        esc=$(_wrg_re_escape "${pat}")
        if [ ${fuzzy} -eq 0 ]; then
            re_bp="^[[:space:]]*name[[:space:]]*:[[:space:]]*\"${esc}\""
            re_mk='^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*'"${esc}"'([[:space:]#]|$)'
            re_make='(^|[^[:alnum:]_])'"${esc}"'([^[:alnum:]_]|$)'
        else
            # 模糊：只让"值"那一段忽略大小写（(?i:...)），关键词仍旧大小写敏感；
            # Makefile 那套不能加词边界 —— -i system 得能命中 vbmetasystemimage 这种
            re_bp="^[[:space:]]*name[[:space:]]*:[[:space:]]*\"[^\"]*(?i:${esc})[^\"]*\""
            re_mk='^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*[^[:space:]#]*(?i:'"${esc}"')'
            re_make="(?i:${esc})"
        fi
        o1=$("${tool}" --no-heading --line-number --with-filename --color=never -g Android.bp -e "${re_bp}" . 2>/dev/null); r1=$?
        o2=$("${tool}" --no-heading --line-number --with-filename --color=never -g Android.mk -e "${re_mk}" . 2>/dev/null); r2=$?
        # 第三套 = 其它 Makefile：--type amake 是 *.bp/*.mk、--type make 是 Makefile/*.mk/*.mak，
        # 两套都会捎上 Android.bp / Android.mk，用 -g '!…' 排掉，免得被 Makefile 语义再算一遍
        o3=$("${tool}" --no-heading --line-number --with-filename --color=never --type amake --type make -g '!Android.bp' -g '!Android.mk' -e "${re_make}" . 2>/dev/null); r3=$?
        rc=0
        if [ ${r1} -gt 1 ]; then rc=${r1}; fi     # rg：1 = 没命中，>1 才是真错
        if [ ${r2} -gt 1 ]; then rc=${r2}; fi
        if [ ${r3} -gt 1 ]; then rc=${r3}; fi
        # 三套正则只是"粗筛"（Makefile 那套尤其松）：真判命中回到共用的 awk（recheck），
        # 三条后端 + 两个 shell 的输出才逐字一致
        out=$(printf '%s\n%s\n%s' "${o1}" "${o2}" "${o3}" | \
            WRG_PAT="${pat}" WRG_FUZZY="${fuzzy}" WRG_PASS=recheck awk "${_WRG_AWK}")
        ;;
    find)
        errname="find/awk"
        if [ -z "$(find . -type f \( -name Android.bp -o -name Android.mk -o -name Makefile -o -name makefile -o -name GNUmakefile -o -name '*.mk' -o -name '*.mak' \) -print -quit 2>/dev/null)" ]; then
            echo "wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile" >&2
            return 1
        fi
        out=$(WRG_PAT="${pat}" WRG_FUZZY="${fuzzy}" WRG_PASS=search \
            find . -type f \( -name Android.bp -o -name Android.mk -o -name Makefile -o -name makefile -o -name GNUmakefile -o -name '*.mk' -o -name '*.mak' \) -exec awk "${_WRG_AWK}" {} + 2>/dev/null)
        rc=$?
        ;;
    *)
        errname="${tool}/awk"
        if [ -z "$("${tool}" -t f -g "${_WRG_FD_GLOB}" 2>/dev/null | head -n 1)" ]; then
            echo "wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile" >&2
            return 1
        fi
        out=$(WRG_PAT="${pat}" WRG_FUZZY="${fuzzy}" WRG_PASS=search \
            "${tool}" -t f -g "${_WRG_FD_GLOB}" -X awk "${_WRG_AWK}" 2>/dev/null)
        rc=$?
        # fd 没命中时的退出码各版本不一样（9.0.0 给 0，有的给 1）：空输出 + 1 当"没命中"
        if [ -z "${out}" ] && [ ${rc} -eq 1 ]; then rc=0; fi
        ;;
    esac

    if [ ${rc} -ne 0 ]; then
        echo "wrg: 搜索失败（${errname} 退出码 ${rc}）" >&2
        return 1
    fi
    if [ -z "${out}" ]; then
        echo "wrg: 没有匹配 '${pat}' 的目标名" >&2
        return 1
    fi
    # 先按纯文本排序，再（只在终端上）过一遍着色，ANSI 不会污染排序键
    if [ ${color} -eq 1 ]; then
        printf '%s\n' "${out}" | sort -t: -k1,1 -k2,2n | \
            WRG_PAT="${pat}" WRG_FUZZY="${fuzzy}" WRG_PASS=paint awk "${_WRG_AWK}"
    else
        printf '%s\n' "${out}" | sort -t: -k1,1 -k2,2n
    fi
    return 0
}

# start 的补全：当前目录的文件/目录名（bash 的 complete；非交互式 source 也没关系）
complete -o default -o filenames start
