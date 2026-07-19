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
    origin_dir=${cur_dir}
    while [[ ! -e ${cur_dir}/${target_dir} ]]; do
        cur_dir=${cur_dir:h}
        [[ ${cur_dir} == / ]] && return 1
    done
    echo ${cur_dir}
    return 0
}

cw ()
{
    cd ${WSW_REPO_TOP}
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

win ()
{
    this_is_wsl && { wslpath -w . && return 0 } || return 1
}

start ()
{
    this_is_not_wsl && echo "only wsl support this" && return 1
    powershell.exe -Command "Set-Location -Path \"$(win)\"; Start-Process $1"
}

