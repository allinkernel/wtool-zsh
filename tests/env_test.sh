#!/usr/bin/env bash
# shell/zsh 的 env 测试：env.zsh 和 env.bash 必须给同一批别名/函数，
# 且核心函数（_up_to_have_dir / cw / pdd / WSL 那几个）在两个 shell 里行为一致。
#
#   bash tests/env_test.sh
#
# 没装 zsh 就只测 bash（会打印跳过），因为 bash 版存在的意义就是"没有 zsh 的机器"。
set -u

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd -- "$here/.." && pwd)

pass=0; fail=0
ok ()  { pass=$((pass + 1)); printf '  ok   %s\n' "$*"; }
bad () { fail=$((fail + 1)); printf '  FAIL %s\n' "$*"; }
chk () { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1（期望 [$3] 实际 [$2]）"; fi; }

T=$(mktemp -d "${TMPDIR:-/tmp}/wtool-shell-zsh.XXXXXX")
trap 'rm -rf -- "$T"' EXIT INT TERM

# 假的 repo 工作区：$T/ws/.repo，测试从 $T/ws/a/b 往上找
mkdir -p "$T/ws/.repo" "$T/ws/a/b"

sh_eval () {   # <shell> <片段>：source 对应 env 后在假工作区里跑
    local sh=$1 snippet=$2
    ( cd "$T/ws/a/b" && WTOOL_PROJECT_DIR="$proj" "$sh" -c \
        "set -u; source \"$proj/env.$sh\"; $snippet" ) 2>&1
}

for sh in bash zsh; do
    if ! command -v "$sh" >/dev/null 2>&1; then
        echo "== env.$sh：跳过（没装 $sh）=="
        continue
    fi
    echo "== env.$sh =="

    out=$(sh_eval "$sh" 'alias gs; alias gll; alias kls')
    case $out in
        *"git status"*) ok "$sh：git 别名在" ;;
        *) bad "$sh：git 别名没定义 [$out]" ;;
    esac
    case $out in
        *"git log"*) ok "$sh：gll 指到 git log" ;;
        *) bad "$sh：gll 不对 [$out]" ;;
    esac

    chk "$sh：_up_to_have_dir 往上找到 .repo" \
        "$(sh_eval "$sh" '_up_to_have_dir .repo')" "$T/ws"
    chk "$sh：_up_to_have_dir 找不到就返回 1" \
        "$(sh_eval "$sh" 'cd /; _up_to_have_dir .repo >/dev/null; echo rc=$?')" "rc=1"

    chk "$sh：cw 跳到 repo 根" \
        "$(sh_eval "$sh" 'cw >/dev/null && printf "%s\n" "$PWD"')" "$T/ws"

    # pwd 被本项目的函数接管，pdd/pss 靠它落下的临时文件
    chk "$sh：pss 报出上一次 pwd 的目录" \
        "$(sh_eval "$sh" 'pwd >/dev/null; pss')" "$T/ws/a/b"
    chk "$sh：pdd 能跳回 pss 记下的目录" \
        "$(sh_eval "$sh" 'pwd >/dev/null; cd /; pdd >/dev/null; printf "%s\n" "$PWD"')" "$T/ws/a/b"

    # WSL 探测：按本机实际情况断言（这台机器就是 WSL，别写死）
    if [ -e /usr/bin/wslpath ]; then
        chk "$sh：this_is_wsl 在 WSL 上返回 0" \
            "$(sh_eval "$sh" 'this_is_wsl; echo rc=$?')" "rc=0"
        chk "$sh：win 在 WSL 上给出 Windows 路径" \
            "$(sh_eval "$sh" 'win >/dev/null 2>&1; echo rc=$?')" "rc=0"
    else
        chk "$sh：this_is_wsl 在非 WSL 上返回 1" \
            "$(sh_eval "$sh" 'this_is_wsl; echo rc=$?')" "rc=1"
        chk "$sh：win 在非 WSL 上返回 1" \
            "$(sh_eval "$sh" 'win >/dev/null 2>&1; echo rc=$?')" "rc=1"
    fi
    chk "$sh：this_is_not_wsl 与 this_is_wsl 相反" \
        "$(sh_eval "$sh" 'this_is_wsl && this_is_not_wsl; echo rc=$?')" "rc=1"
done

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
