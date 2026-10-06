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
    if [[ -n "${WIN_IP:-}" ]]; then
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
    [[ -n "${target}" ]] || target="${1:-$PWD}"

    ip=$(_win_ip)
    if [[ -z "${ip}" ]]; then
        echo "win: 拿不到本机 IP（WIN_IP 没设，ip addr 里也没有）。" >&2
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
# wrg：在当前目录树下按"构建目标名"找 Android.mk / Android.bp
#   wrg <名字>      精确匹配目标名
#   wrg -i <片段>   模糊匹配（目标名里含这个片段，忽略大小写）
# 认这两种写法：Android.mk 的 LOCAL_MODULE / LOCAL_PACKAGE_NAME，Android.bp 的 name: "xxx"
# 输出：文件:行号:命中行
# ---------------------------------------------------------------------------
_wrg_usage ()
{
    echo "Usage: wrg <名字>        # 精确匹配目标名"
    echo "       wrg -i <片段>     # 模糊匹配（子串、忽略大小写）"
}

wrg ()
{
    local fuzzy=0 pat out rc
    case "${1:-}" in
        -h|--help) _wrg_usage; return 0 ;;
        -i)        fuzzy=1; shift ;;
        -*)        echo "wrg: 不认识的选项 ${1}" >&2; _wrg_usage >&2; return 2 ;;
    esac
    if [[ $# -ne 1 || -z "${1}" ]]; then
        _wrg_usage >&2
        return 2
    fi
    pat="${1}"

    if [[ -z "$(find . -type f \( -name Android.mk -o -name Android.bp \) -print -quit 2>/dev/null)" ]]; then
        echo "wrg: 当前目录树下没有 Android.mk / Android.bp" >&2
        return 1
    fi

    out=$(WRG_PAT="${pat}" WRG_FUZZY="${fuzzy}" find . -type f \( -name Android.mk -o -name Android.bp \) -exec awk '
        BEGIN { pat = ENVIRON["WRG_PAT"]; lpat = tolower(pat); fuzzy = ENVIRON["WRG_FUZZY"] + 0 }
        function hit(v) {
            if (fuzzy) return index(tolower(v), lpat) > 0
            return v == pat
        }
        FILENAME ~ /Android[.]bp$/ {
            if (match($0, /^[[:space:]]*name[[:space:]]*:[[:space:]]*"[^"]*"/)) {
                v = substr($0, RSTART, RLENGTH)
                sub(/^[^"]*"/, "", v)
                sub(/"[[:space:]]*$/, "", v)
                if (hit(v)) print FILENAME ":" FNR ":" $0
            }
            next
        }
        FILENAME ~ /Android[.]mk$/ {
            if (match($0, /^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*[^[:space:]#]+/)) {
                v = substr($0, RSTART, RLENGTH)
                sub(/^[^=]*=[[:space:]]*/, "", v)
                if (hit(v)) print FILENAME ":" FNR ":" $0
            }
            next
        }
    ' {} + 2>/dev/null)
    rc=$?
    if [[ ${rc} -ne 0 ]]; then
        echo "wrg: 搜索失败（find/awk 退出码 ${rc}）" >&2
        return 1
    fi
    if [[ -z "${out}" ]]; then
        echo "wrg: 没有匹配 '${pat}' 的目标名" >&2
        return 1
    fi
    printf '%s\n' "${out}" | sort -t: -k1,1 -k2,2n
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
