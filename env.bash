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

win ()
{
    this_is_wsl && { wslpath -w . && return 0; } || return 1
}

start ()
{
    this_is_not_wsl && echo "only wsl support this" && return 1
    powershell.exe -Command "Set-Location -Path \"$(win)\"; Start-Process $1"
}
