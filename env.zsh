# 迁移自 mytool/zsh/wsw-zshrc/wsw.zsh（原 wsw-zshrc）。纯 zsh，由 ~/.zshrc 里的 wtool 块 source。
#
# WTOOL_PROJECT_DIR 由 wtool 块导出 = $HOME/.wtool/wtool-work-dir/links/shell/zsh
[[ -n "$WTOOL_PROJECT_DIR" ]] || WTOOL_PROJECT_DIR="$HOME/.wtool/wtool-work-dir/links/shell/zsh"

# 这个脚本是给zsh去source的
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
_up_to_have_dir ()
{
    # 创建一个subshell，也就是fork当前shell进程，完成目录探测工作，这是否是一个性能糟糕的设计，用一段时间再说吧
    target_dir=$1
    # 基于PWD变量比pwd命令要靠谱些, 不会因为当前路径不存在就让此函数陷入dead loop
    cur_dir=${PWD}
    while [[ ! -e ${cur_dir}/${target_dir} ]]; do
        # 先判"已经在 / 了"再往上走，让 / 那一格**被测到**（和 env.bash 等价）：
        # 原来写成先 ${cur_dir:h} 再判 == /，走到 / 就直接 return 1，
        # 挂在根下的目标永远找不到（2026-10-04 修，用例见 tests/env_test.sh）。
        [[ ${cur_dir} == / ]] && return 1
        cur_dir=${cur_dir:h}
    done
    echo ${cur_dir}
    return 0
}

# 原来写的是 cd ${WSW_REPO_TOP}；迁移后自包含：
# 从本项目真实路径向上找到含 .repo 的目录（也就是 wtool 集合的根）。
cw ()
{
    local d="${WTOOL_PROJECT_ROOT:-$PWD}"
    while [[ "$d" != "/" && ! -e "$d/.repo" ]]; do
        d="${d:h}"
    done
    if [[ -e "$d/.repo" ]]; then
        cd "$d"
    else
        echo "cw: 找不到 .repo（不在 repo 工作区内？）" >&2
        return 1
    fi
}

unset gba &>/dev/null
unalias gba &>/dev/null
gba ()
{
    if command -v batcat &>/dev/null; then
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
    [[ -e /usr/bin/wslpath ]] && return 0 || return 1
}

this_is_not_wsl ()
{
    [[ ! -e /usr/bin/wslpath ]] && return 0 || return 1
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
    # 只认 $WIN_IP：**不做 ip addr 探测**。
    # 阿里云那类机器探出来的是内网 / VPC 地址，不是能对外用的地址；
    # 猜错了比不猜更坏（用户 2026-10-07 要求）。
    [ -n "${WIN_IP:-}" ] || return 1
    printf '%s\n' "${WIN_IP}"
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
    [[ -n "${target}" ]] || target="${1:-$PWD}"

    ip=$(_win_ip)
    if [[ -z "${ip}" ]]; then
        echo "win: 没设 WIN_IP（本命令不自动探测 IP —— 服务器上探到的常常是内网地址）。" >&2
        echo "     请在 .bashrc/.zshrc 里设 WIN_IP=<本机对外的地址>" >&2
        return 1
    fi

    conf="${WTOOL_SMB_CONF:-/etc/samba/smb.conf}"
    best=""; best_rel=""; best_len=0; rc=0
    if [[ -r "${conf}" ]]; then
        shares=$(_win_smb_shares "${conf}")
        while IFS= read -r line; do
            [[ -n "${line}" ]] || continue
            name="${line%%|*}"
            spath="${line#*|}"
            [[ -n "${name}" && -n "${spath}" ]] || continue
            sraw="${spath}"
            spath=$(realpath -m -- "${sraw}" 2>/dev/null)
            [[ -n "${spath}" ]] || spath="${sraw}"
            case "${target}" in
                "${spath}")   rel="" ;;
                "${spath}"/*) rel="${target#"${spath}"}" ;;
                *)            continue ;;
            esac
            if (( ${#spath} > best_len )); then
                best="${name}"
                best_rel="${rel}"
                best_len=${#spath}
            fi
        done <<EOF
${shares}
EOF
        if [[ -n "${best}" ]]; then
            # 三种写法都给：
            #   \\ip\share\rel   → Windows 资源管理器地址栏 / CMD / PowerShell（UNC）
            #   //ip/share/rel   → Linux：mount -t cifs //srv/share 、smbclient //srv/share
            #   smb://ip/share/rel → 浏览器 / macOS Finder / GNOME Files
            _unc=$(printf '%s' "${best_rel}" | sed 's|/|\\|g')
            printf '%s\n' "\\\\${ip}\\${best}${_unc}"
            echo "//${ip}/${best}${best_rel}"
            echo "smb://${ip}/${best}${best_rel}"
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
    # 用法：win [路径]            —— WSL 上给 Windows 路径；服务器上给 samba/scp 三种写法
    #       win -s|--server [路径] —— **强制走服务器分支**（在 WSL 上也能看/测那条路）
    case ${1:-} in
    -s | --server)
        shift
        _win_server "$@"
        return $?
        ;;
    esac
    if this_is_wsl; then
        # 带参数就给那个路径的 Windows 路径（老版本忽略参数、永远给 cwd —— 已修）
        wslpath -w "${1:-.}" || return 1
        return 0
    fi
    _win_server "$@"
}

# ── 代理开关：proxy_on / proxy_off ───────────────────────────────────
# 原来这两条是 .zshrc 里写死 127.0.0.1:7897 的别名；现在搬到这里，取值顺序：
#   ① 参数：proxy_on <IP> [端口]
#   ② 环境变量：PROXY_IP / PROXY_PORT（上次 proxy_on 留下的，同 shell 不用再问）
#   ③ 交互式询问（终端里才问；脚本/管道里直接报错，绝不挂住）
# no_proxy 采取"保存原值 + 追加"：proxy_off 会把它还原，不会吃掉你内网的 no_proxy。
unalias proxy_on proxy_off 2>/dev/null || true

proxy_on ()
{
    unalias proxy_on 2>/dev/null || true
    local _ip _port
    _ip="${1:-${PROXY_IP:-}}"
    _port="${2:-${PROXY_PORT:-}}"
    if [ -z "${_ip}" ]; then
        if [ ! -t 0 ]; then
            echo "proxy_on: 没有 PROXY_IP，且当前不是交互终端。" >&2
            echo "     用法：proxy_on <IP> [端口]，或先 export PROXY_IP=<地址>" >&2
            return 2
        fi
        printf 'PROXY_IP [127.0.0.1]: ' >&2
        IFS= read -r _ip || _ip=""
        [ -n "${_ip}" ] || _ip=127.0.0.1
    fi
    if [ -z "${_port}" ]; then
        if [ ! -t 0 ]; then
            echo "proxy_on: 没有 PROXY_PORT，且当前不是交互终端。" >&2
            echo "     用法：proxy_on <IP> <端口>，或先 export PROXY_PORT=<端口>" >&2
            return 2
        fi
        printf 'PROXY_PORT [7897]: ' >&2
        IFS= read -r _port || _port=""
        [ -n "${_port}" ] || _port=7897
    fi
    case "${_port}" in
        ''|*[!0-9]*)
            echo "proxy_on: 端口必须是数字：'${_port}'" >&2
            return 2
            ;;
    esac
    export PROXY_IP="${_ip}" PROXY_PORT="${_port}"
    export http_proxy="http://${_ip}:${_port}"
    export https_proxy="http://${_ip}:${_port}"
    export all_proxy="socks5://${_ip}:${_port}"
    export HTTP_PROXY="http://${_ip}:${_port}"
    export HTTPS_PROXY="http://${_ip}:${_port}"
    export ALL_PROXY="socks5://${_ip}:${_port}"
    # no_proxy：第一次开时把原值存起来，之后只追加（proxy_off 还原）
    if [ -z "${_PROXY_NO_PROXY_SAVED+x}" ]; then
        _PROXY_NO_PROXY_SAVED="${no_proxy-}"
        export _PROXY_NO_PROXY_SAVED
    fi
    if [ -n "${no_proxy:-}" ]; then
        case ",${no_proxy}," in
            *",localhost,"*) : ;;
            *) no_proxy="${no_proxy},localhost,127.0.0.1,::1,.local" ;;
        esac
    else
        no_proxy="localhost,127.0.0.1,::1,.local"
    fi
    export no_proxy NO_PROXY="${no_proxy}"
    echo "Proxy ON  http://${_ip}:${_port}  (all_proxy=socks5://${_ip}:${_port})"
    echo "          no_proxy=${no_proxy}"
    return 0
}

proxy_off ()
{
    unalias proxy_off 2>/dev/null || true
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    if [ -n "${_PROXY_NO_PROXY_SAVED+x}" ]; then
        if [ -n "${_PROXY_NO_PROXY_SAVED}" ]; then
            no_proxy="${_PROXY_NO_PROXY_SAVED}"
            export no_proxy NO_PROXY="${no_proxy}"
        else
            unset no_proxy NO_PROXY
        fi
        unset _PROXY_NO_PROXY_SAVED
    fi
    echo 'Proxy OFF（代理变量已清除；PROXY_IP/PROXY_PORT 留着，下次 proxy_on 不用再问）'
    return 0
}

start ()
{
    this_is_not_wsl && echo "only wsl support this" && return 1
    powershell.exe -Command "Set-Location -Path \"$(win)\"; Start-Process $1"
}

# ---------------------------------------------------------------------------
# wrg：在当前目录树下按"构建目标名"找 Android.bp / Android.mk / Makefile
#   wrg [选项] <名字>         精确匹配目标名
#   wrg [选项] -i <片段>      模糊匹配：枚举所有目标名（三类文件），两边都去掉 _ 再比，
#                             查询串从尾部逐级截断，用"实际能命中的最长前缀"去匹配
#                             （最短试到 4 个字符）
#   wrg [选项] -e <名字> ...  多名字查询（取并集），-i 时每个名字各做一次模糊
#   选项位置自由：wrg x -A3 与 wrg -A3 x 等价；布尔短选项可捆绑（-il）；
#   带值短选项的值可以贴着写（-A3）也可以放下一格（-A 3）；-- 之后一律当查询串；
#   位置参数只能有一个查询串（多个 → rc 2 + 用法），多个名字用 -e。
# 认三类文件（-t/--type 可以只搜其中一类）：
#   Android.bp  → name: "xxx"
#   Android.mk  → LOCAL_MODULE / LOCAL_PACKAGE_NAME
#   其它 Makefile（Makefile / makefile / GNUmakefile / *.mk（Android.mk 除外）/ *.mak）
#               → 构建目标名：规则行（^[[:space:]]*目标([[:space:]]+目标)*[[:space:]]*:）
#                 冒号前那串不含 = $ # " ' 的词，外加 .PHONY: 声明的那些词；一行多个目标逐个算
#   以 TAB 开头的行一律不算目标定义（Makefile 的 recipe 必须 TAB 缩进）；
#   目标列表（冒号前那段）里有引号的也不算 —— @echo "aaa: bbb" 这种是字符串不是目标。
# 输出：文件:行号:命中行（路径形状与 find 一致带 ./ 前缀，按文件+行号排序；
#   命中的那一段在终端里高亮，管道/重定向时不着色）；
#   给了 -A/-B/-C 时上下文行打成"文件-行号-原文"、块与块之间打一行 --（grep 惯例），
#   上下文的计算和着色一样在共用的 awk 那一层（三条后端因此逐字一致）。
# 搜索后端：rg → fd（按 fdfind / fd-find / fd 探测）→ find，前一个没有才用下一个。
#   rg / fd 默认跳过隐藏目录和 .gitignore 里的目录（例如 .repo/、out/），更快；
#   要连这些目录一起搜（find 的老行为）就用 WRG_SEARCH=find。
#   WRG_SEARCH=auto(默认)/rg/fd/find、WRG_COLOR=auto(默认)/always/never 是测试和兜底用的：
#   指定了就必须用它，找不到那个可执行文件就报错（rc=2），不会偷偷换成别的。
# ---------------------------------------------------------------------------

# 模糊匹配"枚举目标名"用的粗筛正则：不含查询串，把候选行全捞出来交给 awk 抠名字
# （三条后端各用自己的办法扫文件；rg 这条路要靠它们，正则本身必须是宽的）
_WRG_RE_BP_NAME='^[[:space:]]*name[[:space:]]*:[[:space:]]*"'
_WRG_RE_MK_NAME='^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*'
_WRG_RE_MAKE_NAME='^[^=#$:]*:'   # 第一个冒号出现在 = # $ 之前 —— rule_prefix() 认的行一定匹配它

# 三种后端共用的一段 awk：
#   WRG_PASS=search  扫文件出结果（find / fd 那条路）；
#   WRG_PASS=recheck 给 stdin 上的 "路径:行号:原文" 做真判命中（rg 那几套正则只是粗筛）；
#   WRG_PASS=paint   给同一形状的行上色：命中的那一段红粗（\033[1;31m … \033[0m），
#                    目标名里其余没匹配到的部分绿、不加粗（\033[32m … \033[0m）；
#   WRG_PASS=ctx     先按 -B/-A 把命中行展开成带上下文的输出（命中行照旧着色，上下文行
#                    不着色、形状是"路径-行号-原文"，块与块之间打一行 --），见 4.5.4；
#   WRG_PASS=names   扫文件、WRG_PASS=names3 读 "路径:行号:原文"，两者都只枚举目标名，
#                    最后打印"查询串去 _ 后能命中的最长前缀"（模糊匹配第一步，一行一个查询）。
# 判命中 / 抠目标名 / 枚举名字 / 着色 / 上下文都只有这一份，三个后端共用，保证输出一致。
# 进来的环境变量：WRG_PAT（查询串，一行一个）、WRG_FUZZY、WRG_KINDS（认哪几类文件，
# 1=bp 2=mk 3=其它 Makefile）、WRG_BEFORE / WRG_AFTER（上下文行数）、WRG_COLOR_ON。
_WRG_AWK='BEGIN {
    fuzzy = ENVIRON["WRG_FUZZY"] + 0
    pass = ENVIRON["WRG_PASS"]
    np = split(ENVIRON["WRG_PAT"], P, "\n")
    if (np == 0) { np = 1; P[1] = "" }
    for (i = 1; i <= np; i++) {
        NP[i] = key(P[i]); NL[i] = length(NP[i])
        F1[i] = substr(NP[i], 1, 1); ML[i] = 0
    }
    kinds = ENVIRON["WRG_KINDS"]; if (kinds == "") kinds = "123"
    bctx = ENVIRON["WRG_BEFORE"] + 0
    actx = ENVIRON["WRG_AFTER"] + 0
    on = ENVIRON["WRG_COLOR_ON"] + 0
    collect = (pass == "names" || pass == "names3")
    hlen = 0; nh = 0; cfile = ""; anyout = 0; newblk = 0
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
# 目标名的归一化形式：去掉 _ 再转小写（模糊匹配时查询串和候选名两边都这么归一）
function key(s,   i, n, c, o) {
    o = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c != "_") o = o c
    }
    return tolower(o)
}
# 第 i 个查询串判一个候选值算不算命中：精确比整个名字；模糊把两边都归一化后找子串。
# 命中返回"命中段在原串里的 0 基起点"，段长写进全局 hlen
# （原串里可能夹着 _，高亮要按原串的下标来，所以不能直接用归一化后的长度）
function hit1(val, i,   nv, p, j, n, c, k, st) {
    if (!fuzzy) {
        if (val == P[i]) { hlen = length(val); return 0 }
        return -1
    }
    if (NL[i] == 0) return -1
    nv = key(val)
    p = index(nv, NP[i])
    if (p == 0) return -1
    k = 0; st = 0; n = length(val)
    for (j = 1; j <= n; j++) {
        c = substr(val, j, 1)
        if (c == "_") continue
        k++
        if (k == p) st = j
        if (k == p + NL[i] - 1) { hlen = j - st + 1; return st - 1 }
    }
    return -1
}
# 多个查询串：按顺序取第一个命中的（-e a -e b 就是"并集"，同一个名字只算一次）
function hit(val,   i, o) {
    for (i = 1; i <= np; i++) { o = hit1(val, i); if (o >= 0) return o }
    return -1
}
# 枚举模式（collect）用：把一个候选目标名和每个查询串比"最长公共前缀"，记进 ML[]。
# 归一化只做"去掉 _ + 转小写"，所以查询串的前缀出现在某个名字里
# ⇔ 那个名字里有一段和它逐字相同（这就是"逐级截断"要找的东西）
function addname(nm,   i, k, m, j, l, st) {
    for (i = 1; i <= np; i++) {
        if (NL[i] == 0 || ML[i] >= NL[i]) continue
        k = key(nm); m = length(k)
        for (j = 1; j <= m; j++) {
            if (substr(k, j, 1) != F1[i]) continue
            l = 1
            for (st = 2; st <= NL[i] && j + st - 1 <= m; st++) {
                if (substr(k, j + st - 1, 1) != substr(NP[i], st, 1)) break
                l = st
            }
            if (l > ML[i]) ML[i] = l
            if (ML[i] >= NL[i]) break
        }
    }
}
# 每个候选值都从这儿过：枚举模式只记名字；别的模式判命中（命中写全局 v / vs，一行只认第一个）
function take(vv, oo) {
    if (collect) { addname(vv); return 0 }
    if (hit(vv) >= 0) { v = vv; vs = oo; return 1 }
    return 0
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
# 目标必须是"不含 = $ # 引号 的词"：扫到这几个字符里的任何一个就否决整行
# （VAR ?= x / VAR = x / ifeq (...) / include $(...) / # 注释 都在这儿挡掉）；
# 冒号紧跟 = 的是赋值不是规则（VAR := x），::= 也是赋值。
# 以 TAB 开头的一律否决：Makefile 的 recipe 必须 TAB 缩进，那是命令行不是目标定义。
function rule_prefix(line,   i, n, c) {
    if (substr(line, 1, 1) == "\t") return ""
    n = length(line); i = 1
    while (i <= n && substr(line, i, 1) ~ /[[:space:]]/) i++
    while (i <= n) {
        c = substr(line, i, 1)
        if (c == "=" || c == "$" || c == "#") return ""
        if (c == "\"" || c == "\047") return ""   # 目标列表里不许有引号（@echo "aaa: bbb"）
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
# （声明部分在 # 注释处截断）。一行里可能有多个目标，挨个过 take()：
# 正常模式取第一个命中的（写进全局 v / vs 并返回 1），枚举模式全记下来。
function cand_make(line,   pre, cnt, i, ph, rest, cut, rn, w) {
    pre = rule_prefix(line)
    if (pre == "") return 0
    ph = 0; cnt = words(pre, 0)
    for (i = 1; i <= cnt; i++) {
        if (W[i] == ".PHONY") ph = 1
        if (take(W[i], WO[i])) return 1
    }
    if (!ph) return 0
    rest = substr(line, length(pre) + 2)          # 冒号（在 length(pre)+1）之后
    cut = index(rest, "#")
    if (cut > 0) rest = substr(rest, 1, cut - 1)
    rn = words(rest, length(pre) + 1)
    for (i = 1; i <= rn; i++) {
        w = W[i]
        if (w ~ /[$=\\]/) continue                # .PHONY: $(TARGETS) / 续行反斜杠 不算
        if (index(w, "\"") > 0 || index(w, "\047") > 0) continue   # 声明词里的引号也不算
        if (take(w, WO[i])) return 1
    }
    return 0
}
function cand_bp(line,   vv) {
    if (substr(line, 1, 1) == "\t") return 0     # TAB 开头 = recipe / 正文，不是目标定义
    if (match(line, /^[[:space:]]*name[[:space:]]*:[[:space:]]*"[^"]*"/)) {
        vv = substr(line, RSTART, RLENGTH)
        sub(/^[^"]*"/, "", vv); sub(/"[[:space:]]*$/, "", vv)
        return take(vv, RSTART + RLENGTH - 1 - length(vv))
    }
    return 0
}
function cand_mk(line,   vv) {
    if (substr(line, 1, 1) == "\t") return 0     # TAB 开头 = recipe 正文，不是目标定义
    if (match(line, /^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*[^[:space:]#]+/)) {
        vv = substr(line, RSTART, RLENGTH)
        sub(/^[^=]*=[[:space:]]*/, "", vv)
        return take(vv, RSTART + RLENGTH - length(vv))
    }
    return 0
}
function cand(p, line,   k) {
    k = kind(p)
    if (k == 0 || index(kinds, k) == 0) return 0   # -t/--type 没选中的类不算
    if (k == 1) return cand_bp(line)
    if (k == 2) return cand_mk(line)
    return cand_make(line)
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
# 打一行结果：命中行 "路径:行号:原文"（on 时按 4.5.2 分两段上色），
# 上下文行 "路径-行号-原文"（永不着色）。块边界的 -- 也在这儿打。
function put(ln, txt, ishit,   o, vlen, mid) {
    if (newblk) { if (anyout) print "--"; newblk = 0 }
    anyout = 1
    if (ishit && on && cand(cfile, txt)) {
        o = hit(v)
        if (o >= 0 && v != "") {
            vlen = length(v); mid = ""
            if (o > 0) mid = mid "\033[32m" substr(txt, vs, o) "\033[0m"
            mid = mid "\033[1;31m" substr(txt, vs + o, hlen) "\033[0m"
            if (o + hlen < vlen) mid = mid "\033[32m" substr(txt, vs + o + hlen, vlen - o - hlen) "\033[0m"
            print cfile ":" ln ":" substr(txt, 1, vs - 1) mid substr(txt, vs + vlen)
            return
        }
    }
    if (ishit) print cfile ":" ln ":" txt
    else print cfile "-" ln "-" txt
}
# ctx pass 用：把当前文件（cfile）的命中行号（HL[]，升序）展开成带上下文的输出。
# 命中窗口 [行号-B, 行号+A] 重叠或相邻的合并成一块（不重复打印、也不多打 --）；
# 块与块之间、文件与文件之间打一行 --（grep 惯例）。
function flush(   i, lo, hi, m, ln, txt, hp, r, ishit, cur_lo, cur_hi) {
    if (cfile == "" || nh == 0) { cfile = ""; nh = 0; return }
    m = 0
    cur_lo = HL[1] - bctx; if (cur_lo < 1) cur_lo = 1
    cur_hi = HL[1] + actx
    for (i = 2; i <= nh; i++) {
        lo = HL[i] - bctx; if (lo < 1) lo = 1
        hi = HL[i] + actx
        if (lo <= cur_hi + 1) { if (hi > cur_hi) cur_hi = hi; continue }
        m++; RL[m] = cur_lo; RH[m] = cur_hi
        cur_lo = lo; cur_hi = hi
    }
    m++; RL[m] = cur_lo; RH[m] = cur_hi
    i = 1; ln = 0; hp = 1; r = 1
    while (i <= m && r > 0) {
        r = (getline txt < cfile)
        if (r <= 0) break
        ln++
        if (ln > RH[i]) { i++; continue }
        if (ln < RL[i]) continue
        while (hp <= nh && HL[hp] < ln) hp++
        ishit = (hp <= nh && HL[hp] == ln)
        if (ln == RL[i]) newblk = 1
        put(ln, txt, ishit)
    }
    if (ln == 0) {                     # 文件读不出来（删了 / 没权限）：上下文退化成只有命中行
        for (i = 1; i <= nh; i++) { newblk = 1; put(HL[i], HT[i], 1) }
    }
    close(cfile)
    cfile = ""; nh = 0
}
# 上色：命中的那一段 = 红 + 加粗；目标名里其余（没匹配到的）部分 = 绿、不加粗。
# 精确模式命中的就是整个名字，两头都是空的 → 只有红段（和以前一样）；
# 模糊模式只标第一处命中（hit() 找的就是第一处），后面的（含同一个子串第二次出现）
# 都算"没匹配到" → 绿。两头空的那对绿码不打，免得输出里多出没用的转义。
pass == "paint" {
    if (!split3($0)) { print; next }
    if (!cand(fp, ft)) { print; next }
    o = hit(v)
    if (o < 0 || v == "") { print; next }
    vlen = length(v); mid = ""
    if (o > 0) mid = mid "\033[32m" substr(ft, vs, o) "\033[0m"
    mid = mid "\033[1;31m" substr(ft, vs + o, hlen) "\033[0m"
    if (o + hlen < vlen) mid = mid "\033[32m" substr(ft, vs + o + hlen, vlen - o - hlen) "\033[0m"
    print fp ":" fl ":" substr(ft, 1, vs - 1) mid substr(ft, vs + vlen)
    next
}
pass == "recheck" {
    if (!split3($0)) next
    if (!cand(fp, ft)) next
    print
    next
}
pass == "names3" {
    if (!split3($0)) next
    cand(fp, ft)
    next
}
# ctx：命中行按"路径:行号:原文"进来（shell 侧已经排好序），按文件攒够一批再展开
pass == "ctx" {
    if (!split3($0)) next
    if (fp != cfile) { flush(); cfile = fp; nh = 0 }
    nh++; HL[nh] = fl + 0; HT[nh] = ft
    next
}
{
    if (pass == "names") { cand(norm(FILENAME), $0); next }
    p = norm(FILENAME)
    if (!cand(p, $0)) next
    print p ":" FNR ":" $0
}
END {
    if (pass == "ctx") { flush(); exit }
    if (collect) {
        for (i = 1; i <= np; i++) {
            if (NL[i] == 0) continue
            floor = (NL[i] < 4) ? NL[i] : 4      # 最短试到 4 个字符；查询本身更短就整个试
            if (ML[i] >= floor) print substr(NP[i], 1, ML[i])
        }
    }
}
'

_wrg_usage ()
{
    echo "Usage: wrg [选项] <名字>"
    echo "       wrg [选项] -e <名字> [-e <名字> ...]"
    echo "选项位置自由：wrg x -A3 与 wrg -A3 x 等价；-- 之后一律当查询串。"
    echo ""
    echo "  -i, --ignore-case         模糊匹配：去 _ 后按子串找（默认精确匹配整个目标名）"
    echo "  -e, --regexp <名字>       多名字查询（可重复，取并集；-i 时每个都做模糊）"
    echo "  -t, --type bp|mk|make     只搜某类文件：bp=Android.bp mk=Android.mk"
    echo "                            make=其它 Makefile（可重复 / 逗号分隔；不写=三类都搜）"
    echo "  -A, --after-context <n>   命中行之后 n 行也打印（上下文行不着色）"
    echo "  -B, --before-context <n>  命中行之前 n 行"
    echo "  -C, --context <n>         前后各 n 行（等价 -A n -B n；块之间打一行 --）"
    echo "  -l, --files               只打印命中的文件路径（去重、排序）"
    echo "  -c, --count               打印每个文件的命中条数（路径:条数）"
    echo "  -m, --max-count <n>       全局最多输出 n 条命中（按输出顺序取前 n）"
    echo "      --color[=WHEN]        auto（默认）/ always / never；always 压过 NO_COLOR"
    echo "  -h, --help                这份帮助"
    echo "  -v, --version             版本与搜索后端"
    echo ""
    echo "环境：WRG_SEARCH=auto|rg|fd|find  WRG_COLOR=auto|always|never  NO_COLOR"
}

# 版本：打印版本号 + 当前会用的后端（后端取不到就 [?]，版本本身照样 rc 0）
_wrg_version ()
{
    local b
    b=$(_wrg_backend 2>/dev/null) || b='?'
    printf 'wrg 1.0（后端 %s）\n' "${b}"
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

# 模糊匹配"粗筛"用的正则：归一化（去 _）之后含这段前缀 ⇔ 原文本里这些字符按顺序出现、
# 中间只夹着 _。所以每个字符后面都挂一个 "_*"，整段 (?i:...) 忽略大小写。
# 判命中仍在 awk 里（它按归一化后的名字算），这条只是让 rg 少吐几行。
_wrg_re_us ()
{
    printf '%s' "${1}" | awk '
        { out = ""; n = length($0)
          for (i = 1; i <= n; i++) {
              c = substr($0, i, 1)
              if (index("\\^$.*+?()[]{}|", c) > 0) out = out "\\"
              out = out c "_*"
          }
          printf "(?i:%s)", out }'
}

# 查询串的归一化形式：去掉 _ 再转小写（和 awk 里 key() 一个口径）
_wrg_norm ()
{
    printf '%s' "${1}" | tr -d '_' | tr 'A-Z' 'a-z'
}

# 选中的类型 → 提示语里的文件名（三类都选时逐字等于老提示语）
_wrg_type_names ()
{
    local s=''
    if [ "$1" -eq 1 ]; then s='Android.bp'; fi
    if [ "$2" -eq 1 ]; then s=${s:+$s / }'Android.mk'; fi
    if [ "$3" -eq 1 ]; then s=${s:+$s / }'Makefile'; fi
    printf '%s\n' "${s}"
}

# 选中的类型 → fd 的 -g 文件名 glob（fd 的 -g 是开关，所有名字合成一个 glob）
_wrg_fd_glob ()
{
    local g=''
    if [ "$1" -eq 1 ]; then g='Android.bp'; fi
    if [ "$2" -eq 1 ]; then g=${g:+$g,}'Android.mk'; fi
    if [ "$3" -eq 1 ]; then g=${g:+$g,}'Makefile,makefile,GNUmakefile,*.mk,*.mak'; fi
    printf '{%s}\n' "${g}"
}

# 模糊匹配第一步：枚举三类文件里的**所有目标名**（用和搜索同一个后端，每次都重扫当前
# 目录、不缓存），把查询串去 _ 后从尾部逐级截断，打印"实际能命中的最长前缀"；
# 短于 4 个字符不再往下截（查询本身不足 4 个字符就整个试）；一个都没命中就什么都不打印。
# $3 $4 $5 = -t 选中的三类文件开关，$6 = kinds 掩码（判命中那一层的口径）。
_wrg_prefix ()
{
    local tool=$1 pat=$2 tbp=$3 tmk=$4 tmake=$5 kinds=$6 pfx
    case "${tool}" in
    rg)
        pfx=$( { if [ "${tbp}" -eq 1 ]; then
                     "${tool}" --no-heading --line-number --with-filename --color=never -g Android.bp -e "${_WRG_RE_BP_NAME}" . 2>/dev/null
                 fi
                 if [ "${tmk}" -eq 1 ]; then
                     "${tool}" --no-heading --line-number --with-filename --color=never -g Android.mk -e "${_WRG_RE_MK_NAME}" . 2>/dev/null
                 fi
                 if [ "${tmake}" -eq 1 ]; then
                     "${tool}" --no-heading --line-number --with-filename --color=never --type amake --type make -g '!Android.bp' -g '!Android.mk' -e "${_WRG_RE_MAKE_NAME}" . 2>/dev/null
                 fi
               } | WRG_PAT="${pat}" WRG_KINDS="${kinds}" WRG_PASS=names3 awk "${_WRG_AWK}" ) ;;
    find)
        pfx=$(WRG_PAT="${pat}" WRG_KINDS="${kinds}" WRG_PASS=names \
            find . -type f \( -name Android.bp -o -name Android.mk -o -name Makefile -o -name makefile -o -name GNUmakefile -o -name '*.mk' -o -name '*.mak' \) \
            -exec awk "${_WRG_AWK}" {} + 2>/dev/null) ;;
    *)
        pfx=$(WRG_PAT="${pat}" WRG_KINDS="${kinds}" WRG_PASS=names \
            "${tool}" -t f -g "$(_wrg_fd_glob "${tbp}" "${tmk}" "${tmake}")" -X awk "${_WRG_AWK}" 2>/dev/null) ;;
    esac
    # find -exec {} + / fd -X 会按命令行长度分批，每批各打印一行 → 取最长的那一行
    printf '%s\n' "${pfx}" | awk 'length($0) > length(m) { m = $0 } END { if (m != "") print m }'
}

# 要不要上色：$1 = 生效的取值（--color 优先，否则 WRG_COLOR，默认 auto）、
# $2 = 1 表示这是显式 --color（rg 的语义：显式 always 压过 NO_COLOR；env 里的 WRG_COLOR
# 仍旧被 NO_COLOR 压过）。auto 要 stdout 是终端、而且 NO_COLOR 为空。
# 返回 0 上色 / 1 不上色 / 2 取值不认（已报错）。
_wrg_color ()
{
    case "${1}" in
        always)
            if [ "${2}" -eq 1 ]; then return 0; fi
            if [ -n "${NO_COLOR:-}" ]; then return 1; fi
            return 0 ;;
        never)   return 1 ;;
        auto)    ;;
        *)
            echo "wrg: WRG_COLOR 只认 auto / always / never（现在是 ${1}）" >&2
            return 2 ;;
    esac
    if [ -n "${NO_COLOR:-}" ]; then return 1; fi
    [ -t 1 ] || return 1
    return 0
}

wrg ()
{
    local fuzzy=0 files_only=0 count_only=0 maxc=-1 ctxa=0 ctxb=0 color=0 has_color=0 clicolor=''
    local t_bp=0 t_mk=0 t_make=0 kinds='' endopts=0 npos=0 qn=0 np=0 qlist='' plist=''
    local arg opt val hasval=0 rest c v tv rem rem2 q pat pfx esc us vals
    local tool errname rc=0 out has brc=0 crc=0 cwhen=''

    # ---- 参数扫描：位置自由，长/短选项都认（不用 getopts，POSIX 那套不认长选项）----
    while [ $# -gt 0 ]; do
        arg=$1; shift
        opt=''; val=''; hasval=0
        if [ "${endopts}" -eq 0 ]; then
            case "${arg}" in
            --)
                endopts=1
                continue ;;
            --?*)
                case "${arg}" in
                *=*) opt=${arg%%=*}; val=${arg#*=}; hasval=1 ;;
                *)   opt=${arg} ;;
                esac
                if [ "${hasval}" -eq 1 ]; then
                    case "${opt}" in
                    --color|--type|--max-count|--context|--after-context|--before-context|--regexp) ;;
                    *) echo "wrg: ${opt} 不接受值（现在是 ${val}）" >&2; _wrg_usage >&2; return 2 ;;
                    esac
                fi ;;
            -[!-]*)
                # 短选项簇：布尔项就地处理，遇到要值的把剩下的字符当值（-ilA3 = -i -l -A 3）
                rest=${arg#-}
                while [ -n "${rest}" ]; do
                    c=${rest%"${rest#?}"}; rest=${rest#?}
                    case "${c}" in
                    i) fuzzy=1 ;;
                    l) files_only=1 ;;
                    c) count_only=1 ;;
                    h) _wrg_usage; return 0 ;;
                    v) _wrg_version; return 0 ;;
                    A|B|C|m|e|t)
                        opt="-${c}"
                        if [ -n "${rest}" ]; then val=${rest}; hasval=1; rest=''; fi
                        break ;;
                    *) echo "wrg: 不认识的选项 -${c}" >&2; _wrg_usage >&2; return 2 ;;
                    esac
                done
                if [ -z "${opt}" ]; then continue; fi ;;
            *)
                opt='@' ;;
            esac
        else
            opt='@'
        fi

        # 要值的选项：值可以贴在后面（-A3 / --color=always），也可以放下一格（-A 3）
        case "${opt}" in
        -A|-B|-C|-m|-e|-t|--after-context|--before-context|--context|--max-count|--regexp|--type|--color)
            if [ "${hasval}" -eq 0 ]; then
                if [ $# -eq 0 ]; then
                    echo "wrg: 选项 ${opt} 缺值" >&2; _wrg_usage >&2; return 2
                fi
                val=$1; hasval=1; shift
            fi ;;
        esac

        case "${opt}" in
        '@')
            if [ "${npos}" -ge 1 ]; then
                echo "wrg: 只认一个查询串（多出来的：${arg}；多个名字请用 -e）" >&2
                _wrg_usage >&2
                return 2
            fi
            npos=1
            if [ -z "${arg}" ]; then
                echo "wrg: 查询串不能为空" >&2; _wrg_usage >&2; return 2
            fi
            qn=$((qn + 1))
            if [ "${qn}" -eq 1 ]; then qlist=${arg}; else qlist=${qlist}'
'${arg}; fi ;;
        -i|--ignore-case) fuzzy=1 ;;
        -l|--files)       files_only=1 ;;
        -c|--count)       count_only=1 ;;
        -h|--help)        _wrg_usage; return 0 ;;
        -v|--version)     _wrg_version; return 0 ;;
        -A|--after-context)
            case "${val}" in
            ''|*[!0-9]*) echo "wrg: ${opt} 需要一个非负整数（现在是 ${val}）" >&2; _wrg_usage >&2; return 2 ;;
            esac
            ctxa=${val} ;;
        -B|--before-context)
            case "${val}" in
            ''|*[!0-9]*) echo "wrg: ${opt} 需要一个非负整数（现在是 ${val}）" >&2; _wrg_usage >&2; return 2 ;;
            esac
            ctxb=${val} ;;
        -C|--context)
            case "${val}" in
            ''|*[!0-9]*) echo "wrg: ${opt} 需要一个非负整数（现在是 ${val}）" >&2; _wrg_usage >&2; return 2 ;;
            esac
            ctxa=${val}; ctxb=${val} ;;
        -m|--max-count)
            case "${val}" in
            ''|*[!0-9]*) echo "wrg: ${opt} 需要一个非负整数（现在是 ${val}）" >&2; _wrg_usage >&2; return 2 ;;
            esac
            maxc=${val} ;;
        -e|--regexp)
            if [ -z "${val}" ]; then
                echo "wrg: ${opt} 需要一个名字" >&2; _wrg_usage >&2; return 2
            fi
            qn=$((qn + 1))
            if [ "${qn}" -eq 1 ]; then qlist=${val}; else qlist=${qlist}'
'${val}; fi ;;
        -t|--type)
            if [ -z "${val}" ]; then
                echo "wrg: ${opt} 需要一个类型（bp / mk / make）" >&2; _wrg_usage >&2; return 2
            fi
            rem2=${val}
            while [ -n "${rem2}" ]; do
                tv=${rem2%%,*}
                case "${rem2}" in
                *,*) rem2=${rem2#*,} ;;
                *)   rem2='' ;;
                esac
                case "${tv}" in
                bp)   t_bp=1 ;;
                mk)   t_mk=1 ;;
                make) t_make=1 ;;
                '')   ;;                      # 空段忽略（"bp,,mk" / 结尾多一个逗号）
                *) echo "wrg: ${opt} 只认 bp / mk / make（现在是 ${tv}）" >&2; _wrg_usage >&2; return 2 ;;
                esac
            done ;;
        --color)
            case "${val}" in
            auto|always|never) ;;
            *) echo "wrg: --color 只认 auto / always / never（现在是 ${val}）" >&2; _wrg_usage >&2; return 2 ;;
            esac
            clicolor=${val}; has_color=1 ;;
        *)
            echo "wrg: 不认识的选项 ${opt}" >&2; _wrg_usage >&2; return 2 ;;
        esac
    done

    if [ "${qn}" -eq 0 ]; then
        _wrg_usage >&2
        return 2
    fi
    # 诊断信息（"没有匹配 '…' 的目标名"）里用的是**用户输入的原串**，不是截断后的前缀
    case "${qlist}" in
    *'
'*) pat=${qlist%%'
'*} ;;
    *)  pat=${qlist} ;;
    esac

    # 没写 -t 就是三类都搜
    if [ "${t_bp}" -eq 0 ] && [ "${t_mk}" -eq 0 ] && [ "${t_make}" -eq 0 ]; then
        t_bp=1; t_mk=1; t_make=1
    fi
    kinds=''
    if [ "${t_bp}" -eq 1 ]; then kinds="${kinds}1"; fi
    if [ "${t_mk}" -eq 1 ]; then kinds="${kinds}2"; fi
    if [ "${t_make}" -eq 1 ]; then kinds="${kinds}3"; fi

    tool=$(_wrg_backend); brc=$?
    if [ "${brc}" -ne 0 ]; then return ${brc}; fi

    if [ "${has_color}" -eq 1 ]; then cwhen=${clicolor}; else cwhen=${WRG_COLOR:-auto}; fi
    color=0
    _wrg_color "${cwhen}" "${has_color}"; crc=$?
    if [ "${crc}" -eq 2 ]; then return 2; fi
    if [ "${crc}" -eq 0 ]; then color=1; fi

    # 先看树里有没有选中类型的文件，没有就没必要往下走
    case "${tool}" in
    rg)
        errname="${tool}"
        # rg --files 只看文件名，和后面的搜索遵守同一套 ignore 规则
        has=$(
            set -- --files
            if [ "${t_bp}" -eq 1 ]; then set -- "$@" -g Android.bp; fi
            if [ "${t_mk}" -eq 1 ]; then set -- "$@" -g Android.mk; fi
            if [ "${t_make}" -eq 1 ]; then set -- "$@" -g Makefile -g makefile -g GNUmakefile -g '*.mk' -g '*.mak'; fi
            "${tool}" "$@" . 2>/dev/null | head -n 1
        )
        if [ -z "${has}" ]; then
            echo "wrg: 当前目录树下没有 $(_wrg_type_names "${t_bp}" "${t_mk}" "${t_make}")" >&2
            return 1
        fi
        ;;
    find)
        errname="find/awk"
        has=$(
            set -- -type f \(
            v=0
            if [ "${t_bp}" -eq 1 ]; then set -- "$@" -name Android.bp; v=1; fi
            if [ "${t_mk}" -eq 1 ]; then
                if [ "${v}" -eq 1 ]; then set -- "$@" -o; fi
                set -- "$@" -name Android.mk; v=1
            fi
            if [ "${t_make}" -eq 1 ]; then
                if [ "${v}" -eq 1 ]; then set -- "$@" -o; fi
                set -- "$@" -name Makefile -o -name makefile -o -name GNUmakefile -o -name '*.mk' -o -name '*.mak'
            fi
            set -- "$@" \)
            find . "$@" -print -quit 2>/dev/null
        )
        if [ -z "${has}" ]; then
            echo "wrg: 当前目录树下没有 $(_wrg_type_names "${t_bp}" "${t_mk}" "${t_make}")" >&2
            return 1
        fi
        ;;
    *)
        errname="${tool}/awk"
        if [ -z "$("${tool}" -t f -g "$(_wrg_fd_glob "${t_bp}" "${t_mk}" "${t_make}")" 2>/dev/null | head -n 1)" ]; then
            echo "wrg: 当前目录树下没有 $(_wrg_type_names "${t_bp}" "${t_mk}" "${t_make}")" >&2
            return 1
        fi
        ;;
    esac

    # 每个查询串先定"实际拿去找"的模式：精确 = 原样；模糊 = 枚举目标名算出的最长可命中前缀。
    # 只有"实际匹配"和用户输入（去 _ 之后）不一样时才打表头，正常命中保持干净输出。
    # 模糊那条路上某个名字一个都没命中 → 报一行、跳过它（全都跳过了才 rc 1）。
    rem=${qlist}
    while [ -n "${rem}" ]; do
        case "${rem}" in
        *'
'*) q=${rem%%'
'*}; rem=${rem#*'
'} ;;
        *)  q=${rem}; rem='' ;;
        esac
        if [ "${fuzzy}" -eq 1 ]; then
            pfx=$(_wrg_prefix "${tool}" "${q}" "${t_bp}" "${t_mk}" "${t_make}" "${kinds}")
            if [ -z "${pfx}" ]; then
                echo "wrg: 没有匹配 '${q}' 的目标名" >&2
                continue
            fi
            if [ "${pfx}" != "$(_wrg_norm "${q}")" ]; then
                printf '用户输入%s\n' "${q}"
                printf '实际匹配%s\n' "${pfx}"
                printf '匹配目标名如下：\n'
            fi
            q=${pfx}
        fi
        np=$((np + 1))
        if [ "${np}" -eq 1 ]; then plist=${q}; else plist=${plist}'
'${q}; fi
    done
    if [ "${np}" -eq 0 ]; then return 1; fi

    case "${tool}" in
    rg)
        # 三类文件的写法不一样 → 各搜一次再合并；值要做正则转义，
        # 关键词那部分的大小写要敏感（模糊只对值用 (?i:...)）。
        # 多个查询串（-e）合成一个 alternation，粗筛一次就够，真判命中仍在 awk。
        vals=''; us=''
        rem=${plist}
        while [ -n "${rem}" ]; do
            case "${rem}" in
            *'
'*) q=${rem%%'
'*}; rem=${rem#*'
'} ;;
            *)  q=${rem}; rem='' ;;
            esac
            esc=$(_wrg_re_escape "${q}")
            if [ -z "${vals}" ]; then vals=${esc}; else vals=${vals}'|'"${esc}"; fi
            if [ -z "${us}" ]; then us=$(_wrg_re_us "${q}"); else us=${us}'|'"$(_wrg_re_us "${q}")"; fi
        done
        if [ "${fuzzy}" -eq 0 ]; then
            re_bp='^[[:space:]]*name[[:space:]]*:[[:space:]]*"('"${vals}"')"'
            re_mk='^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*('"${vals}"')([[:space:]#]|$)'
            re_make='(^|[^[:alnum:]_])('"${vals}"')([^[:alnum:]_]|$)'
        else
            # 模糊：只让"值"那一段忽略大小写（(?i:...)），关键词仍旧大小写敏感；
            # Makefile 那套不能加词边界 —— -i system 得能命中 vbmetasystemimage 这种
            re_bp='^[[:space:]]*name[[:space:]]*:[[:space:]]*"[^"]*('"${us}"')[^"]*"'
            re_mk='^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*[^[:space:]#]*('"${us}"')'
            re_make='('"${us}"')'
        fi
        o1=''; o2=''; o3=''; r1=0; r2=0; r3=0
        if [ "${t_bp}" -eq 1 ]; then
            o1=$("${tool}" --no-heading --line-number --with-filename --color=never -g Android.bp -e "${re_bp}" . 2>/dev/null); r1=$?
        fi
        if [ "${t_mk}" -eq 1 ]; then
            o2=$("${tool}" --no-heading --line-number --with-filename --color=never -g Android.mk -e "${re_mk}" . 2>/dev/null); r2=$?
        fi
        # 第三套 = 其它 Makefile：--type amake 是 *.bp/*.mk、--type make 是 Makefile/*.mk/*.mak，
        # 两套都会捎上 Android.bp / Android.mk，用 -g '!…' 排掉，免得被 Makefile 语义再算一遍
        if [ "${t_make}" -eq 1 ]; then
            o3=$("${tool}" --no-heading --line-number --with-filename --color=never --type amake --type make -g '!Android.bp' -g '!Android.mk' -e "${re_make}" . 2>/dev/null); r3=$?
        fi
        rc=0
        if [ "${r1}" -gt 1 ]; then rc=${r1}; fi     # rg：1 = 没命中，>1 才是真错
        if [ "${r2}" -gt 1 ]; then rc=${r2}; fi
        if [ "${r3}" -gt 1 ]; then rc=${r3}; fi
        # 三套正则只是"粗筛"（Makefile 那套尤其松）：真判命中回到共用的 awk（recheck），
        # 三条后端 + 两个 shell 的输出才逐字一致
        out=$(printf '%s\n%s\n%s' "${o1}" "${o2}" "${o3}" | \
            WRG_PAT="${plist}" WRG_FUZZY="${fuzzy}" WRG_KINDS="${kinds}" WRG_PASS=recheck awk "${_WRG_AWK}")
        ;;
    find)
        # 文件名谓词不跟着 -t 变：多认的文件由 awk 的 kinds 掩码丢掉（三条后端结果仍然一致）
        out=$(WRG_PAT="${plist}" WRG_FUZZY="${fuzzy}" WRG_KINDS="${kinds}" WRG_PASS=search \
            find . -type f \( -name Android.bp -o -name Android.mk -o -name Makefile -o -name makefile -o -name GNUmakefile -o -name '*.mk' -o -name '*.mak' \) -exec awk "${_WRG_AWK}" {} + 2>/dev/null)
        rc=$?
        ;;
    *)
        out=$(WRG_PAT="${plist}" WRG_FUZZY="${fuzzy}" WRG_KINDS="${kinds}" WRG_PASS=search \
            "${tool}" -t f -g "$(_wrg_fd_glob "${t_bp}" "${t_mk}" "${t_make}")" -X awk "${_WRG_AWK}" 2>/dev/null)
        rc=$?
        # fd 没命中时的退出码各版本不一样（9.0.0 给 0，有的给 1）：空输出 + 1 当"没命中"
        if [ -z "${out}" ] && [ "${rc}" -eq 1 ]; then rc=0; fi
        ;;
    esac

    if [ "${rc}" -ne 0 ]; then
        echo "wrg: 搜索失败（${errname} 退出码 ${rc}）" >&2
        return 1
    fi
    # 先按纯文本排序（ANSI 不参与排序键）：-m 取前 n 条、上下文展开都在排序之后
    if [ -n "${out}" ]; then
        out=$(printf '%s\n' "${out}" | sort -t: -k1,1 -k2,2n)
    fi
    if [ "${maxc}" -ge 0 ]; then
        # 用 awk 截断，不用 head：head 提前退出会让 printf 吃 SIGPIPE，多打一句 write error
        out=$(printf '%s\n' "${out}" | awk -v n="${maxc}" 'NR <= n')
    fi
    if [ -z "${out}" ]; then
        echo "wrg: 没有匹配 '${pat}' 的目标名" >&2
        return 1
    fi

    # -l / -c 只出行（grep 的 -l 也压过 -c），不看上下文、不着色
    if [ "${files_only}" -eq 1 ]; then
        printf '%s\n' "${out}" | awk '{ p = $0; sub(/:.*/, "", p); if (p != last) { print p; last = p } }'
        return 0
    fi
    if [ "${count_only}" -eq 1 ]; then
        printf '%s\n' "${out}" | awk '{ p = $0; sub(/:.*/, "", p)
            if (p != last) { if (last != "") printf "%s:%d\n", last, c; last = p; c = 0 }
            c++ } END { if (last != "") printf "%s:%d\n", last, c }'
        return 0
    fi
    # 上色 / 上下文都过共用的 awk（三条后端因此逐字一致）：
    # 没有上下文（不写 -A/-B/-C，或 -A0 -B0 / -C0）走老的 paint 那条路，输出逐字不变
    if [ "${ctxa}" -eq 0 ] && [ "${ctxb}" -eq 0 ]; then
        if [ "${color}" -eq 1 ]; then
            printf '%s\n' "${out}" | sort -t: -k1,1 -k2,2n | \
                WRG_PAT="${plist}" WRG_FUZZY="${fuzzy}" WRG_KINDS="${kinds}" WRG_PASS=paint awk "${_WRG_AWK}"
        else
            printf '%s\n' "${out}"
        fi
    else
        printf '%s\n' "${out}" | \
            WRG_PAT="${plist}" WRG_FUZZY="${fuzzy}" WRG_KINDS="${kinds}" \
            WRG_BEFORE="${ctxb}" WRG_AFTER="${ctxa}" WRG_COLOR_ON="${color}" WRG_PASS=ctx awk "${_WRG_AWK}"
    fi
    return 0
}

# start 的补全：当前目录的文件/目录名。
# compinit 由 shell/oh-my-zsh（priority=10）负责跑；装了它就是 compdef + _files，
# 没装（只装本项目）时退回 compctl -f —— 两条路都不是"没有补全"。
if (( $+functions[compdef] )); then
    compdef _files start
else
    compctl -f start
fi
