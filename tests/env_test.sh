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
mkdir -p "$T/ws/.repo" "$T/ws/a/b" "$T/ws/ab" "$T/empty"

# wrg 的夹具：一棵含 Android.mk / Android.bp 的小树（目标名 + 一条注释里的假目标）
mkdir -p "$T/src/foo" "$T/src/bar"
cat > "$T/src/foo/Android.mk" <<'EOF'
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := libfoo
LOCAL_SRC_FILES := foo.c
include $(BUILD_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_PACKAGE_NAME := FooApp
include $(BUILD_PACKAGE)

# LOCAL_MODULE := libcommented
EOF
cat > "$T/src/bar/Android.bp" <<'EOF'
cc_library {
    name: "libbar",
    srcs: ["bar.c"],
}

android_app {
    name: "BarApp",
}
EOF

# wrg 三后端（rg / fd / find）的夹具：正则元字符、大小写、注释、隐藏目录。
# 单独一棵树（$T/src2），免得动到上面 $T/src 的既有期望值。
mkdir -p "$T/src2/keep" "$T/src2/.hidden"
cat > "$T/src2/keep/Android.mk" <<'EOF'
LOCAL_MODULE := liba+b
LOCAL_MODULE := libaaab
LOCAL_PACKAGE_NAME := MixCase
EOF
cat > "$T/src2/keep/Android.bp" <<'EOF'
cc_library {
    name: "baseTarget",
}

cc_library {
    name: "libc.d",
}

cc_library {
    name: "libcxd",
}

// name: "libcommented"
EOF
cat > "$T/src2/.hidden/Android.bp" <<'EOF'
cc_library {
    name: "libhidden",
}
EOF

# wrg 第三类文件（Makefile 构建目标）的夹具：$T/src3。
# 一棵树里三类文件都有，用来比三条后端；Makefile 的行号被断言钉着，改动要连用例一起改。
mkdir -p "$T/src3/keep"
cat > "$T/src3/keep/Makefile" <<'EOF'
# mkfix: comment targets are not targets
LOCAL_PATH := $(call my-dir)
VAR := mkvarname
VAR ?= mkqname
ifeq ($(strip $(MKTARGETS)),)
endif
ifeq (nomkcolon,plain)
endif
.PHONY: mkphony1 mkphony2
mkrule:
	@echo hi
mkrule2 mkrule3: $(deps)
	@echo hi
$(MKTARGET): dep
mkslash/out.bin: dep
# mkcommented: x
mkmulti: dep1 dep2
mkshared: dep
EOF
printf 'gnumk:\n\t@echo hi\n' > "$T/src3/keep/GNUmakefile"
printf 'lowmk:\n\t@echo hi\n' > "$T/src3/keep/makefile"
printf 'extramk:\n\t@echo hi\n' > "$T/src3/keep/extra.mk"
printf 'makmk:\n\t@echo hi\n' > "$T/src3/keep/other.mak"
# Android.mk 里故意放一条"只有 Makefile 语义才认"的规则行（mkandroidrule）：
# Android.mk 不归 Makefile 语义管，它必须搜不到 —— 被两套语义各算一遍的话这里就露馅
printf 'LOCAL_MODULE := mkandroidmod\nmkandroidrule:\n\t@echo hi\nLOCAL_MODULE := mkshared\n' \
    > "$T/src3/keep/Android.mk"
printf 'cc_library {\n    name: "mkbpname",\n}\ncc_library {\n    name: "mkshared",\n}\n' \
    > "$T/src3/keep/Android.bp"

# 只有 Makefile 的树（Makefile 单独也算"有可搜文件"）；
# 只有 Makefile.am 的树（Makefile.am 不在文件集合里 → 仍旧算"没有可搜文件"）
mkdir -p "$T/mkonly" "$T/amonly"
printf 'mkonly:\n\t@echo hi\n' > "$T/mkonly/Makefile"
printf 'amtarget:\n\t@echo hi\n' > "$T/amonly/Makefile.am"

# wrg 假阳性的夹具（$T/src4）：这些"看起来像目标定义"的行都不是目标。
# 第 3、4 行照抄真 AOSP（build/make/core/Makefile 里 recipe 用 TAB 缩进，
# define 体内那行用空格缩进）；每行都埋了真目标名 fpzreal 和一个只在那一行出现的探针名。
# 行号被断言钉着，改动要连用例一起改。
mkdir -p "$T/src4/keep"
cat > "$T/src4/keep/Makefile" <<'EOF'
.PHONY: fpzreal
fpzreal: $(FPZ_DEPS)
	@echo "Target fpzreal fprec1 fs image: $(1)"
  @echo "Install fpzreal fprec2 fs image: $@"
define fpzdefine
  @echo "Uncompress fpzdeftarget $1"
endef
$(info fpzinfo: $(FPZ_DEPS))
# fpzcommented: comment
VAR := fpzvar
export A := fpzexport
ifeq ($(strip $(FPZ)),)
endif
	fpztabtarget: $(X)
fpzmulti1 fpzmulti2: dep
EOF

# wrg 模糊算法（去 _ + 逐级截断）的夹具（$T/src5）：名字里故意混着有 _ / 没 _ 两种写法，
# 让三类文件都过一遍（Android.bp 的 name、Makefile 的目标名）。行号同样被断言钉着。
mkdir -p "$T/src5/keep"
cat > "$T/src5/keep/Android.bp" <<'EOF'
cc_library {
    name: "vbmetasystem",
}

cc_library {
    name: "vbmetasystem_ext",
}

cc_library {
    name: "vbmeta_system_other",
}
EOF
printf '.PHONY: vbmeta_system_mk\nvbmeta_system_mk: dep\n\t@echo hi\n' > "$T/src5/keep/Makefile"

# wrg 高亮分两段（红 = 输入匹配到的那一段、绿 = 目标名里其余部分）的夹具（$T/src6）：
# 查 `-i ystemim`（归一化后 7 个字符，能整段命中）时这 4 个名字各钉一个边界 ——
#   ① systemimage            匹配段在中间，前面 `s` 绿、后面 `age` 绿；
#   ② vbmetasystemimage      同上，前面 `vbmetas` 绿；
#   ③ systemimagesystemim    子串出现两次，只有第一次红，第二次连同尾巴一起绿；
#   ④ vbmetasystemim         匹配段正好在结尾 → 没有后段绿码。
# 行号被断言钉着（2 / 6 / 10 / 14），改动要连用例一起改。
mkdir -p "$T/src6/keep"
cat > "$T/src6/keep/Android.bp" <<'EOF'
cc_library {
    name: "systemimage",
}

cc_library {
    name: "vbmetasystemimage",
}

cc_library {
    name: "systemimagesystemim",
}

cc_library {
    name: "vbmetasystemim",
}
EOF

# wrg 后端探测的夹具：一堆只有一个可执行名的假 PATH（内容为空也行，探测只看命令在不在）
mkdir -p "$T/bin-rg" "$T/bin-fdfind" "$T/bin-fd-find" "$T/bin-fd" "$T/bin-none"
for c in rg fdfind fd-find fd; do : > "$T/bin-$c/$c"; chmod +x "$T/bin-$c/$c"; done
# auto 那条路要真跑一遍 rg：装的 wrapper 记一笔再 exec 真的 rg
real_rg=$(command -v rg 2>/dev/null || true)
if [ -n "$real_rg" ]; then
    printf '#!/bin/sh\n: > "%s"\nexec "%s" "$@"\n' "$T/rg-used" "$real_rg" > "$T/bin-rg/rg"
    chmod +x "$T/bin-rg/rg"
fi

# win 服务器分支的夹具：假 smb.conf（只通过 WTOOL_SMB_CONF 注入，绝不碰真 /etc/samba）
smb="$T/smb.conf"
cat > "$smb" <<EOF
[global]
   workgroup = WG

[proj]
   path = $T/ws/a

[ws]
   path = $T/ws

[elsewhere]
   path = /nowhere
EOF
smb_nomatch="$T/smb-nomatch.conf"
cat > "$smb_nomatch" <<EOF
[other]
   path = /nowhere
EOF

sh_eval () {   # <shell> <片段>：source 对应 env 后在假工作区里跑
    local sh=$1 snippet=$2
    # 夹具自带干净环境：调用者可能是个 wtool 管着的 shell（块里导出了
    # WTOOL_PROJECT_ROOT / WTOOL_PROJECT_DIR / WTOOL_PROJECT_ID）。
    # 不清掉的话 cw 会顺着继承来的 WTOOL_PROJECT_ROOT 跳到真工作区，
    # "cw 跳到 repo 根"那条断言就会挂（实测 18/2，2026-10-04）。
    ( cd "$T/ws/a/b" && env -u WTOOL_PROJECT_ROOT -u WTOOL_PROJECT_ID \
        WTOOL_PROJECT_DIR="$proj" "$sh" -c \
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

    # 最顶层那一格：目标挂在 / 下时也要命中。env.zsh 原来走到 / 就直接 return 1，
    # / 那一格从来没被测过（env.bash 会测），两份因此不等价 —— 2026-10-04 修。
    # 用 "etc"：起点 $T/ws/a/b 在 /tmp 下，往上几层不会撞见同名目录。
    chk "$sh：_up_to_have_dir 命中挂在 / 下的目录（最顶层那一格）" \
        "$(sh_eval "$sh" 'test -e /etc || exit 9
            d=$(_up_to_have_dir etc); rc=$?; printf "%s|rc=%s\n" "$d" "$rc"')" "/|rc=0"

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
        chk "$sh：win 在 WSL 上就是 wslpath -w .（逐字一致）" \
            "$(sh_eval "$sh" 'win')" "$(wslpath -w "$T/ws/a/b")"
    else
        chk "$sh：this_is_wsl 在非 WSL 上返回 1" \
            "$(sh_eval "$sh" 'this_is_wsl; echo rc=$?')" "rc=1"
        chk "$sh：win 在非 WSL 上返回 1" \
            "$(sh_eval "$sh" 'win >/dev/null 2>&1; echo rc=$?')" "rc=1"
    fi
    chk "$sh：this_is_not_wsl 与 this_is_wsl 相反" \
        "$(sh_eval "$sh" 'this_is_wsl && this_is_not_wsl; echo rc=$?')" "rc=1"

    # ---- start 的补全注册（真正的 TAB 行为在容器里用 pty 验，这里只钉注册）----
    case $sh in
        bash)
            out=$(sh_eval "$sh" 'complete -p start')
            case $out in
                *"-o default"*start*) ok "$sh：start 注册了文件名补全（complete -o default -o filenames）" ;;
                *) bad "$sh：start 没有补全注册 [$out]" ;;
            esac ;;
        zsh)
            chk "$sh：跑了 compinit 时 start 用 _files 补全" \
                "$(sh_eval "$sh" 'autoload -Uz compinit && compinit -u
                    source "$WTOOL_PROJECT_DIR/env.zsh"
                    print -r -- ${_comps[start]}')" "_files"
            out=$(sh_eval "$sh" 'compctl -L start')
            case $out in
                *compctl*-f*start*) ok "$sh：没跑 compinit 时退回 compctl -f" ;;
                *) bad "$sh：start 在没 compinit 的环境里没补全注册 [$out]" ;;
            esac ;;
    esac

    # ---- win 的服务器分支（非 WSL）：WSL 机上用函数替身压低 this_is_wsl，两边跑同一张表 ----
    win_srv='this_is_wsl () { return 1; }'
    target=$(cd "$T/ws/a/b" && /usr/bin/pwd -P)
    want="//10.1.2.3/proj/b
$(whoami)@10.1.2.3:$target"
    chk "$sh：win（非 WSL）给出 samba 路径 + scp 路径两行" \
        "$(sh_eval "$sh" "$win_srv
            WIN_IP=10.1.2.3 WTOOL_SMB_CONF='$smb' win")" "$want"
    chk "$sh：win（非 WSL）按最长前缀挑 share，且按路径分隔符对齐" \
        "$(sh_eval "$sh" "$win_srv
            cd '$T/ws/ab'
            WIN_IP=10.1.2.3 WTOOL_SMB_CONF='$smb' win | head -1")" "//10.1.2.3/ws/ab"

    rc=0
    out=$(sh_eval "$sh" "$win_srv
        WIN_IP=10.1.2.3 WTOOL_SMB_CONF='$smb_nomatch' win") || rc=$?
    chk "$sh：win（非 WSL）没有匹配的 share：退出码 1" "$rc" "1"
    case $out in
        *"没有 share 的 path 匹配"*) ok "$sh：win 报清楚是 smb.conf 不匹配" ;;
        *) bad "$sh：win 报错不清楚 [$out]" ;;
    esac
    case $out in
        *"@10.1.2.3:$target"*) ok "$sh：win 仍然给出 scp 那一行" ;;
        *) bad "$sh：win 把 scp 那一行也吞了 [$out]" ;;
    esac

    rc=0
    out=$(sh_eval "$sh" "$win_srv
        WIN_IP=10.1.2.3 WTOOL_SMB_CONF='$T/no-such-smb.conf' win") || rc=$?
    chk "$sh：win（非 WSL）读不到 smb.conf：退出码 1" "$rc" "1"
    case $out in
        *"读不到 samba 配置"*) ok "$sh：win 说清了读不到哪个文件" ;;
        *) bad "$sh：读不到 smb.conf 的报错不清楚 [$out]" ;;
    esac

    rc=0
    out=$(sh_eval "$sh" "$win_srv
        unset WIN_IP
        _win_ip () { return 1; }
        win") || rc=$?
    chk "$sh：win（非 WSL）取不到 IP：退出码 1" "$rc" "1"
    case $out in
        *WIN_IP*) ok "$sh：提示去 rc 文件里设 WIN_IP" ;;
        *) bad "$sh：取不到 IP 的报错没提 WIN_IP [$out]" ;;
    esac

    # WIN_IP 没设时的兜底：从 ip addr 取（本机没有非 lo 的 IPv4 就跳过这条）
    real_ip=$(ip -4 addr show 2>/dev/null | awk '
        /^[0-9]+:[[:space:]]/ { iface = $2; sub(/:$/, "", iface); next }
        iface != "lo" && $1 == "inet" { sub(/\/.*/, "", $2); print $2; exit }')
    if [ -n "$real_ip" ]; then
        chk "$sh：win（非 WSL）WIN_IP 没设时用 ip addr 里的地址" \
            "$(sh_eval "$sh" "$win_srv
                unset WIN_IP
                WTOOL_SMB_CONF='$smb' win | tail -1")" \
            "$(whoami)@$real_ip:$target"
    fi

    # ---- wrg：Android.mk / Android.bp 里的目标名 ----
    chk "$sh：wrg 精确匹配 Android.mk 的 LOCAL_MODULE" \
        "$(sh_eval "$sh" "cd '$T/src'; wrg libfoo")" \
        "./foo/Android.mk:3:LOCAL_MODULE := libfoo"
    chk "$sh：wrg 精确匹配 Android.mk 的 LOCAL_PACKAGE_NAME" \
        "$(sh_eval "$sh" "cd '$T/src'; wrg FooApp")" \
        "./foo/Android.mk:8:LOCAL_PACKAGE_NAME := FooApp"
    chk "$sh：wrg 精确匹配 Android.bp 的 name" \
        "$(sh_eval "$sh" "cd '$T/src'; wrg BarApp")" \
        "./bar/Android.bp:7:    name: \"BarApp\","

    want="./bar/Android.bp:2:    name: \"libbar\",
./foo/Android.mk:3:LOCAL_MODULE := libfoo"
    chk "$sh：wrg 模糊匹配（-i）两个文件都命中、按文件排序" \
        "$(sh_eval "$sh" "cd '$T/src'; wrg -i lib")" "$want"
    chk "$sh：wrg -i 忽略大小写" \
        "$(sh_eval "$sh" "cd '$T/src'; wrg -i LIBFOO")" \
        "./foo/Android.mk:3:LOCAL_MODULE := libfoo"

    rc=0
    out=$(sh_eval "$sh" "cd '$T/src'; wrg libcommented") || rc=$?
    chk "$sh：wrg 不吃注释里的 LOCAL_MODULE" "$rc" "1"
    rc=0
    out=$(sh_eval "$sh" "cd '$T/src'; wrg lib") || rc=$?
    chk "$sh：wrg 精确匹配不认前缀（lib 不命中 libfoo）" "$rc" "1"
    rc=0
    out=$(sh_eval "$sh" "cd '$T/empty'; wrg libfoo") || rc=$?
    chk "$sh：wrg 在没有这三类文件的目录：退出码 1，不炸" "$rc" "1"
    case $out in
        *"没有 Android.bp / Android.mk / Makefile"*) ok "$sh：wrg 说清了当前树下没有这三类文件" ;;
        *) bad "$sh：wrg 的提示不清楚 [$out]" ;;
    esac
    # 模糊那条路要先枚举目标名再搜：没有可搜文件时也得先报这个（别报成"没有匹配"）
    rc=0
    out=$(sh_eval "$sh" "cd '$T/empty'; wrg -i libfoo; echo rc=\$?") || rc=$?
    chk "$sh：wrg -i 在没有这三类文件的目录：同样报"没有可搜文件"" "$out" \
        "wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile
rc=1"
    rc=0
    out=$(sh_eval "$sh" 'wrg') || rc=$?
    chk "$sh：wrg 不带参数：退出码 2（报用法）" "$rc" "2"

    # ---- wrg 的搜索后端：rg → fd（fdfind/fd-find/fd）→ find ----
    # 本机有哪几个后端（自己探，不用被测代码），没装的那些用例就跳过
    have_rg=0; command -v rg >/dev/null 2>&1 && have_rg=1
    have_fd=''
    for c in fdfind fd-find fd; do
        if command -v "$c" >/dev/null 2>&1; then have_fd=$c; break; fi
    done

    wrg_to () {   # <WRG_SEARCH 值> <输出文件> <wrg 参数...>：在 $T/src2 里跑，stdout+stderr 都收
        local v=$1 f=$2; shift 2
        sh_eval "$sh" "cd '$T/src2'; WRG_SEARCH='$v'; wrg $*" > "$f"
    }

    esc=$(printf '\033')

    # 参考：find 是改动前的老行为
    # 注意：模糊模式用 libc（不碰 .hidden 里的 libhidden）—— 命中落在隐藏目录里时
    # fd/rg 与 find 本来就不一样，那是另一条用例专门盯着的语义差异
    wrg_to find "$T/o-fuzzy-find" -i libc
    wrg_to find "$T/o-exact-find" 'liba+b'
    for v in auto fd rg; do
        [ "$v" = fd ] && [ -z "$have_fd" ] && continue
        [ "$v" = rg ] && [ "$have_rg" -eq 0 ] && continue
        wrg_to "$v" "$T/o-fuzzy-$v" -i libc
        wrg_to "$v" "$T/o-exact-$v" 'liba+b'
        if cmp -s "$T/o-fuzzy-$v" "$T/o-fuzzy-find" && cmp -s "$T/o-exact-$v" "$T/o-exact-find"; then
            ok "$sh：wrg WRG_SEARCH=$v 与 find 逐字一致（cmp：模糊 -i libc + 精确 liba+b）"
        else
            bad "$sh：wrg WRG_SEARCH=$v 与 find 不一致（cmp：模糊 -i libc 或精确 liba+b）"
        fi
    done

    # 元字符当字面量：正则没转义的话 liba+b 会连 libaaab 一起命中
    chk "$sh：wrg 精确匹配里的 + 是字面量（不命中 libaaab）" \
        "$(sh_eval "$sh" "cd '$T/src2'; wrg 'liba+b'")" "./keep/Android.mk:1:LOCAL_MODULE := liba+b"
    if [ "$have_rg" -eq 1 ]; then
        chk "$sh：wrg（rg）精确匹配里的 . 是字面量（不命中 libcxd）" \
            "$(sh_eval "$sh" "cd '$T/src2'; WRG_SEARCH=rg; wrg 'libc.d'")" \
            './keep/Android.bp:6:    name: "libc.d",'
    fi

    # 每条后端的边界：无命中 → 1 + 提示；树下没有这三类文件 → 1 + 提示
    for v in find fd rg; do
        case $v in fd) [ -n "$have_fd" ] || continue ;; rg) [ "$have_rg" -eq 1 ] || continue ;; esac
        chk "$sh：wrg（$v 后端）没有命中：rc=1 + 提示" \
            "$(sh_eval "$sh" "cd '$T/src2'; WRG_SEARCH='$v'; wrg libnosuch; echo rc=\$?")" \
            "wrg: 没有匹配 'libnosuch' 的目标名
rc=1"
        chk "$sh：wrg（$v 后端）树下没有这三类文件：rc=1 + 提示" \
            "$(sh_eval "$sh" "cd '$T/empty'; WRG_SEARCH='$v'; wrg libnosuch; echo rc=\$?")" \
            "wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile
rc=1"
        chk "$sh：wrg（$v 后端）只有 Makefile.am：也算没有可搜文件" \
            "$(sh_eval "$sh" "cd '$T/amonly'; WRG_SEARCH='$v'; wrg amtarget; echo rc=\$?")" \
            "wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile
rc=1"
    done
    # 只有 Makefile 的树：新文件集合真的算数（不靠 Android.* 也能搜）
    for v in find fd rg; do
        case $v in fd) [ -n "$have_fd" ] || continue ;; rg) [ "$have_rg" -eq 1 ] || continue ;; esac
        chk "$sh：wrg（$v 后端）树里只有 Makefile 也搜得到" \
            "$(sh_eval "$sh" "cd '$T/mkonly'; WRG_SEARCH='$v'; wrg mkonly")" \
            "./Makefile:1:mkonly:"
    done

    # ---- wrg：第三类文件 —— Makefile 的构建目标名（$T/src3）----
    chk "$sh：wrg Makefile 规则行的目标（冒号前那串词）" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg mkrule")" \
        './keep/Makefile:10:mkrule:'
    chk "$sh：wrg Makefile 多目标行：冒号前每个词都算（第二个）" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg mkrule3")" \
        './keep/Makefile:12:mkrule2 mkrule3: $(deps)'
    chk "$sh：wrg Makefile 精确匹配不认前缀（mkrule 不命中 mkrule2/3）" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg mkrule | grep -c mkrule || true")" "1"
    chk "$sh：wrg .PHONY 声明的目标算（第二个词）" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg mkphony2")" \
        './keep/Makefile:9:.PHONY: mkphony1 mkphony2'
    chk "$sh：wrg .PHONY 行里冒号前的 .PHONY 本身也是目标" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg .PHONY")" \
        './keep/Makefile:9:.PHONY: mkphony1 mkphony2'
    chk "$sh：wrg 目标名带 / 的也算（路径形状的目标）" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg mkslash/out.bin")" \
        './keep/Makefile:15:mkslash/out.bin: dep'
    chk "$sh：wrg 三类文件混在一棵树里：同名的都命中、按路径排序" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg mkshared")" \
        './keep/Android.bp:5:    name: "mkshared",
./keep/Android.mk:4:LOCAL_MODULE := mkshared
./keep/Makefile:18:mkshared: dep'
    chk "$sh：wrg 认 GNUmakefile" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg gnumk")" './keep/GNUmakefile:1:gnumk:'
    chk "$sh：wrg 认小写 makefile" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg lowmk")" './keep/makefile:1:lowmk:'
    chk "$sh：wrg 认 *.mk" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg extramk")" './keep/extra.mk:1:extramk:'
    chk "$sh：wrg 认 *.mak" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg makmk")" './keep/other.mak:1:makmk:'
    chk "$sh：wrg Android.mk 里的 LOCAL_MODULE 照旧算" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg mkandroidmod")" \
        './keep/Android.mk:1:LOCAL_MODULE := mkandroidmod'
    chk "$sh：wrg 同一个目标只出现一次（Android.mk 不被两套语义各算一遍）" \
        "$(sh_eval "$sh" "cd '$T/src3'; wrg mkandroidmod | wc -l")" "1"
    rc=0
    out=$(sh_eval "$sh" "cd '$T/src3'; wrg mkandroidrule; echo rc=\$?") || rc=$?
    chk "$sh：wrg Android.mk 里的规则行不算目标（Android.mk 不归 Makefile 语义管）" "$out" \
        "wrg: 没有匹配 'mkandroidrule' 的目标名
rc=1"

    # 反例：赋值（VAR := / VAR ?=）、ifeq（有 $ / 没有 $）、注释里的冒号、$ 变量目标
    # 都不能被当成目标名 —— 这是新规则最容易出错的地方
    for probe in 'mkvarname|VAR := 赋值' 'mkqname|VAR ?= 赋值' 'mkcommented|# 注释里的冒号' \
                 'MKTARGET|$(MKTARGET): 这种变量目标' 'nomkcolon|ifeq（没有 $）' \
                 'MKTARGETS|ifeq（里面有 $）'; do
        pname=${probe%%|*}; pwhat=${probe#*|}
        rc=0
        out=$(sh_eval "$sh" "cd '$T/src3'; wrg -i '$pname'; echo rc=\$?") || rc=$?
        chk "$sh：wrg 不把 $pwhat 当目标（$pname）" "$out" \
            "wrg: 没有匹配 '$pname' 的目标名
rc=1"
    done

    # Makefile 夹具上的三后端一致性（cmp）+ 着色一致性
    wrg3_to () {   # <WRG_SEARCH 值> <输出文件> <wrg 参数...>：在 $T/src3 里跑
        local v=$1 f=$2; shift 2
        sh_eval "$sh" "cd '$T/src3'; WRG_SEARCH='$v'; wrg $*" > "$f"
    }
    wrg3_to find "$T/o3-fuzzy-find" -i mkrule
    wrg3_to find "$T/o3-exact-find" mkshared
    for v in auto fd rg; do
        [ "$v" = fd ] && [ -z "$have_fd" ] && continue
        [ "$v" = rg ] && [ "$have_rg" -eq 0 ] && continue
        wrg3_to "$v" "$T/o3-fuzzy-$v" -i mkrule
        wrg3_to "$v" "$T/o3-exact-$v" mkshared
        if cmp -s "$T/o3-fuzzy-$v" "$T/o3-fuzzy-find" && cmp -s "$T/o3-exact-$v" "$T/o3-exact-find"; then
            ok "$sh：wrg（Makefile 夹具）WRG_SEARCH=$v 与 find 逐字一致（cmp：-i mkrule + 精确 mkshared）"
        else
            bad "$sh：wrg（Makefile 夹具）WRG_SEARCH=$v 与 find 不一致（cmp：-i mkrule 或精确 mkshared）"
        fi
    done
    wrg3_to auto "$T/o3-color-auto" mkshared
    chk "$sh：wrg（Makefile 夹具）管道里也没有 ANSI（grep -c ESC）" \
        "$(grep -c "$esc" "$T/o3-color-auto" || true)" "0"
    chk "$sh：WRG_COLOR=always：Makefile 规则行只包住命中的目标名那一段" \
        "$(sh_eval "$sh" "cd '$T/src3'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg mkrule3")" \
        "./keep/Makefile:12:mkrule2 ${esc}[1;31mmkrule3${esc}[0m: \$(deps)"
    chk "$sh：WRG_COLOR=always：.PHONY 行只包住声明里的那个目标" \
        "$(sh_eval "$sh" "cd '$T/src3'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg mkphony2")" \
        "./keep/Makefile:9:.PHONY: mkphony1 ${esc}[1;31mmkphony2${esc}[0m"
    chk "$sh：WRG_COLOR=always：Makefile 模糊 -i 命中段红粗、目标名其余部分绿" \
        "$(sh_eval "$sh" "cd '$T/src3'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i kphony1")" \
        "./keep/Makefile:9:.PHONY: ${esc}[32mm${esc}[0m${esc}[1;31mkphony1${esc}[0m mkphony2"
    chk "$sh：WRG_COLOR=always：Android.mk 的值从等号后第一个字符开始包" \
        "$(sh_eval "$sh" "cd '$T/src3'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg mkandroidmod")" \
        "./keep/Android.mk:1:LOCAL_MODULE := ${esc}[1;31mmkandroidmod${esc}[0m"
    if [ "$have_rg" -eq 1 ] || [ -n "$have_fd" ]; then
        chk "$sh：Makefile 夹具的着色输出 auto 与 find 也逐字一致" \
            "$(sh_eval "$sh" "cd '$T/src3'; unset NO_COLOR; WRG_COLOR=always; wrg -i mkrule")" \
            "$(sh_eval "$sh" "cd '$T/src3'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i mkrule")"
    fi

    # ---- wrg：假阳性 —— recipe / 字符串 / 变量都不算目标（$T/src4）----
    # 正反两面一起钉：真目标（fpzreal）照旧命中，埋在假阳性行里的同一个词一个都不许出现
    chk "$sh：wrg 只认真目标：recipe 行一个都不命中、真目标照旧命中" \
        "$(sh_eval "$sh" "cd '$T/src4'; wrg fpzreal")" \
        './keep/Makefile:1:.PHONY: fpzreal
./keep/Makefile:2:fpzreal: $(FPZ_DEPS)'
    chk "$sh：wrg 的输出里没有 @echo 那种 recipe 行（grep -c @echo）" \
        "$(sh_eval "$sh" "cd '$T/src4'; wrg fpzreal | grep -c '@echo' || true")" "0"
    chk "$sh：wrg -i 同样只认真目标（recipe 行不命中）" \
        "$(sh_eval "$sh" "cd '$T/src4'; wrg -i fpzreal")" \
        './keep/Makefile:1:.PHONY: fpzreal
./keep/Makefile:2:fpzreal: $(FPZ_DEPS)'
    chk "$sh：wrg 的多目标真目标照旧（fpzmulti2）" \
        "$(sh_eval "$sh" "cd '$T/src4'; wrg fpzmulti2")" \
        './keep/Makefile:15:fpzmulti1 fpzmulti2: dep'

    # 每一种假阳性形状单独一条（精确 + 模糊都要不命中）
    for probe in 'fprec1|TAB 缩进的 recipe（@echo "…: …"）' \
                 'fprec2|空格缩进的 recipe（@echo "…: …"）' \
                 'fpzdeftarget|define 体内的 recipe' \
                 'fpzinfo|$(info …: …)' \
                 'fpzcommented|# 注释里的冒号' \
                 'fpzvar|VAR := 赋值' \
                 'fpzexport|export A := 赋值' \
                 'fpztabtarget|TAB 缩进的目标形状行'; do
        pname=${probe%%|*}; pwhat=${probe#*|}
        rc=0
        out=$(sh_eval "$sh" "cd '$T/src4'; wrg '$pname'; echo rc=\$?") || rc=$?
        chk "$sh：wrg 不把 $pwhat 当目标（精确 $pname）" "$out" \
            "wrg: 没有匹配 '$pname' 的目标名
rc=1"
        rc=0
        out=$(sh_eval "$sh" "cd '$T/src4'; wrg -i '$pname'; echo rc=\$?") || rc=$?
        chk "$sh：wrg 不把 $pwhat 当目标（模糊 $pname）" "$out" \
            "wrg: 没有匹配 '$pname' 的目标名
rc=1"
    done

    # ---- wrg：新的模糊算法（去 _ + 逐级截断到 4）----
    want5='用户输入vbmeta_systmmm
实际匹配vbmetasyst
匹配目标名如下：
./keep/Android.bp:2:    name: "vbmetasystem",
./keep/Android.bp:6:    name: "vbmetasystem_ext",
./keep/Android.bp:10:    name: "vbmeta_system_other",
./keep/Makefile:1:.PHONY: vbmeta_system_mk
./keep/Makefile:2:vbmeta_system_mk: dep'
    chk "$sh：wrg -i 故意写错尾部：打表头 + 命中" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbmeta_systmmm")" "$want5"
    chk "$sh：wrg -i 表头第一行照抄用户输入（带 _，不归一化）" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbmeta_sys_tmmm | sed -n 1p")" \
        "用户输入vbmeta_sys_tmmm"
    chk "$sh：wrg -i 表头第二行是实际匹配的前缀（去 _ 又截断过）" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbmeta_sys_tmmm | sed -n 2p")" \
        "实际匹配vbmetasyst"
    chk "$sh：wrg -i 表头第三行是固定措辞" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbmeta_sys_tmmm | sed -n 3p")" \
        "匹配目标名如下："
    # _ 归一：查询带 _ 与不带 _ 是同一个键（都不打表头，命中同一批）
    chk "$sh：wrg -i 查询带 _ 与不带 _ 等价（vbmeta_system）" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbmeta_system")" \
        './keep/Android.bp:2:    name: "vbmetasystem",
./keep/Android.bp:6:    name: "vbmetasystem_ext",
./keep/Android.bp:10:    name: "vbmeta_system_other",
./keep/Makefile:1:.PHONY: vbmeta_system_mk
./keep/Makefile:2:vbmeta_system_mk: dep'
    chk "$sh：wrg -i 正常命中不打表头（grep -c 用户输入 = 0）" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbmetasystem | grep -c '用户输入' || true")" "0"
    chk "$sh：wrg -i 截断命中才打表头（grep -c 用户输入 = 1）" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbmeta_systmmm | grep -c '用户输入' || true")" "1"
    # 逐级截断的下界是 4：vbmzzzzzz 只共享 vbm（3 个字符）→ 不命中；
    # 4 个字符（vbme）和"查询本身不足 4 个字符"（vbm）都照旧命中
    rc=0
    out=$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbmzzzzzz; echo rc=\$?") || rc=$?
    chk "$sh：wrg -i 逐级截断到 4 就不再往下（vbmzzzzzz 不命中）" "$out" \
        "wrg: 没有匹配 'vbmzzzzzz' 的目标名
rc=1"
    chk "$sh：wrg -i 截断到 4 个字符仍然命中（vbme）" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbme | wc -l")" "5"
    chk "$sh：wrg -i 查询不足 4 个字符就整个试（vbm）" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i vbm | wc -l")" "5"
    # 元字符在模糊那条路里也是字面量（粗筛正则要转义）
    chk "$sh：wrg -i 里的 . 是字面量（不命中 libcxd）" \
        "$(sh_eval "$sh" "cd '$T/src2'; wrg -i 'libc.d'")" \
        './keep/Android.bp:6:    name: "libc.d",'
    # 高亮：模糊时命中段红粗、目标名里其余部分绿（原文里有 _ 的按原串下标切两段）
    chk "$sh：WRG_COLOR=always：模糊命中段红粗 + 名字其余部分绿（含 _ 的原文也对）" \
        "$(sh_eval "$sh" "cd '$T/src5'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i vbmeta_systmmm")" \
        "用户输入vbmeta_systmmm
实际匹配vbmetasyst
匹配目标名如下：
./keep/Android.bp:2:    name: \"${esc}[1;31mvbmetasyst${esc}[0m${esc}[32mem${esc}[0m\",
./keep/Android.bp:6:    name: \"${esc}[1;31mvbmetasyst${esc}[0m${esc}[32mem_ext${esc}[0m\",
./keep/Android.bp:10:    name: \"${esc}[1;31mvbmeta_syst${esc}[0m${esc}[32mem_other${esc}[0m\",
./keep/Makefile:1:.PHONY: ${esc}[1;31mvbmeta_syst${esc}[0m${esc}[32mem_mk${esc}[0m
./keep/Makefile:2:${esc}[1;31mvbmeta_syst${esc}[0m${esc}[32mem_mk${esc}[0m: dep"

    # 三后端在 src5 上逐字一致（模糊带表头 + 精确各一条），着色也一致
    wrg5_to () {   # <WRG_SEARCH 值> <输出文件> <wrg 参数...>：在 $T/src5 里跑
        local v=$1 f=$2; shift 2
        sh_eval "$sh" "cd '$T/src5'; WRG_SEARCH='$v'; wrg $*" > "$f"
    }
    wrg5_to find "$T/o5-fuzzy-find" -i vbmeta_systmmm
    wrg5_to find "$T/o5-plain-find" -i vbmeta_system
    wrg5_to find "$T/o5-exact-find" vbmetasystem
    for v in auto fd rg; do
        [ "$v" = fd ] && [ -z "$have_fd" ] && continue
        [ "$v" = rg ] && [ "$have_rg" -eq 0 ] && continue
        wrg5_to "$v" "$T/o5-fuzzy-$v" -i vbmeta_systmmm
        wrg5_to "$v" "$T/o5-plain-$v" -i vbmeta_system
        wrg5_to "$v" "$T/o5-exact-$v" vbmetasystem
        if cmp -s "$T/o5-fuzzy-$v" "$T/o5-fuzzy-find" && cmp -s "$T/o5-plain-$v" "$T/o5-plain-find" &&
           cmp -s "$T/o5-exact-$v" "$T/o5-exact-find"; then
            ok "$sh：wrg（模糊算法夹具）WRG_SEARCH=$v 与 find 逐字一致（cmp：截断带表头 + 归一 + 精确）"
        else
            bad "$sh：wrg（模糊算法夹具）WRG_SEARCH=$v 与 find 不一致"
        fi
    done
    chk "$sh：wrg（模糊算法夹具）管道里没有 ANSI（grep -c ESC）" \
        "$(grep -c "$esc" "$T/o5-fuzzy-find" || true)" "0"
    if [ "$have_rg" -eq 1 ] || [ -n "$have_fd" ]; then
        chk "$sh：模糊算法夹具的着色输出 auto 与 find 逐字一致" \
            "$(sh_eval "$sh" "cd '$T/src5'; unset NO_COLOR; WRG_COLOR=always; wrg -i vbmeta_systmmm")" \
            "$(sh_eval "$sh" "cd '$T/src5'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i vbmeta_systmmm")"
    fi
    # 模糊匹配是"子串"不是"名字必须以它开头"：mid-名字里的一段照样命中（截断后打表头）
    chk "$sh：wrg -i 不锚定在名字开头（metasystemim 截成 metasystem 命中 vbmetasystem）" \
        "$(sh_eval "$sh" "cd '$T/src5'; wrg -i metasystemim")" \
        "用户输入metasystemim
实际匹配metasystem
匹配目标名如下：
./keep/Android.bp:2:    name: \"vbmetasystem\",
./keep/Android.bp:6:    name: \"vbmetasystem_ext\",
./keep/Android.bp:10:    name: \"vbmeta_system_other\",
./keep/Makefile:1:.PHONY: vbmeta_system_mk
./keep/Makefile:2:vbmeta_system_mk: dep"
    # 查询不带 _ 、目标名带 _ ：粗筛正则必须容忍名字里的 _（rg / fd 那条路最容易漏）
    if [ "$have_rg" -eq 1 ]; then
        chk "$sh：wrg（rg）模糊：带 _ 的目标名也命中" \
            "$(sh_eval "$sh" "cd '$T/src5'; WRG_SEARCH=rg; wrg -i vbmetasystem | grep -c 'vbmeta_system_other'")" "1"
    fi
    if [ -n "$have_fd" ]; then
        chk "$sh：wrg（fd）模糊：带 _ 的目标名也命中" \
            "$(sh_eval "$sh" "cd '$T/src5'; WRG_SEARCH=fd; wrg -i vbmetasystem | grep -c 'vbmeta_system_other'")" "1"
    fi

    # ---- wrg：高亮分两段 —— 输入匹配到的那一段红粗、目标名里其余部分绿（$T/src6）----
    # 四行的完整 ANSI 字节：①② 匹配段在中间（前面 / 后面都绿）、③ 子串出现两次
    # （第二次连同尾巴一起绿）、④ 匹配段正好在结尾（没有后段绿码）。
    # 行内其它字符（`name: "` / `",`）不着色。
    chk "$sh：WRG_COLOR=always 模糊 -i ystemim：四行完整 ANSI 字节（红段位置 + 绿段覆盖其余）" \
        "$(sh_eval "$sh" "cd '$T/src6'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i ystemim")" \
        "./keep/Android.bp:2:    name: \"${esc}[32ms${esc}[0m${esc}[1;31mystemim${esc}[0m${esc}[32mage${esc}[0m\",
./keep/Android.bp:6:    name: \"${esc}[32mvbmetas${esc}[0m${esc}[1;31mystemim${esc}[0m${esc}[32mage${esc}[0m\",
./keep/Android.bp:10:    name: \"${esc}[32ms${esc}[0m${esc}[1;31mystemim${esc}[0m${esc}[32magesystemim${esc}[0m\",
./keep/Android.bp:14:    name: \"${esc}[32mvbmetas${esc}[0m${esc}[1;31mystemim${esc}[0m\","
    # 一个名字里出现两次匹配子串：红段只有一个（第一次），第二次在绿段里
    chk "$sh：一个名字里命中两次：只有第一处红（红段计数 = 1）" \
        "$(sh_eval "$sh" "cd '$T/src6'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i ystemim | sed -n 3p | grep -o -F '${esc}[1;31m' | wc -l")" "1"
    # 精确模式行为不变：整名红粗、没有绿段
    chk "$sh：WRG_COLOR=always 精确：整名红粗、无绿段" \
        "$(sh_eval "$sh" "cd '$T/src6'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg systemimage")" \
        "./keep/Android.bp:2:    name: \"${esc}[1;31msystemimage${esc}[0m\","
    chk "$sh：精确输出里一个绿段都没有（grep -c 绿色码 = 0）" \
        "$(sh_eval "$sh" "cd '$T/src6'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg systemimage | grep -c -F '${esc}[32m' || true")" "0"
    # 模糊但整名命中（-i systemimage 的第 1 行）：没匹配到的部分为空 → 同样不打绿段
    chk "$sh：模糊整名命中也没有绿段（-i systemimage 第 1 行）" \
        "$(sh_eval "$sh" "cd '$T/src6'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i systemimage | sed -n 1p")" \
        "./keep/Android.bp:2:    name: \"${esc}[1;31msystemimage${esc}[0m\","
    # 管道 / NO_COLOR：老规矩不变（整段纯文本，不是"去掉颜色码后的样子"）
    wrg6_to () {   # <WRG_SEARCH 值> <输出文件> <wrg 参数...>：在 $T/src6 里跑
        local v=$1 f=$2; shift 2
        sh_eval "$sh" "cd '$T/src6'; WRG_SEARCH='$v'; wrg $*" > "$f"
    }
    wrg6_to auto "$T/o6-plain-auto" -i ystemim
    chk "$sh：wrg（分两段夹具）管道里没有 ANSI（grep -c ESC）" \
        "$(grep -c "$esc" "$T/o6-plain-auto" || true)" "0"
    chk "$sh：NO_COLOR 压过 WRG_COLOR=always（分两段夹具：整段纯文本）" \
        "$(sh_eval "$sh" "cd '$T/src6'; NO_COLOR=1; WRG_SEARCH=find; WRG_COLOR=always; wrg -i ystemim")" \
        './keep/Android.bp:2:    name: "systemimage",
./keep/Android.bp:6:    name: "vbmetasystemimage",
./keep/Android.bp:10:    name: "systemimagesystemim",
./keep/Android.bp:14:    name: "vbmetasystemim",'
    # 三后端 + 两个 shell 的着色输出逐字一致（分两段后同样成立）
    if [ "$have_rg" -eq 1 ] || [ -n "$have_fd" ]; then
        c6_find=$(sh_eval "$sh" "cd '$T/src6'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i ystemim")
        chk "$sh：分两段着色：auto 与 find 逐字一致" \
            "$(sh_eval "$sh" "cd '$T/src6'; unset NO_COLOR; WRG_COLOR=always; wrg -i ystemim")" "$c6_find"
        if [ "$have_rg" -eq 1 ]; then
            chk "$sh：分两段着色：rg 与 find 逐字一致" \
                "$(sh_eval "$sh" "cd '$T/src6'; unset NO_COLOR; WRG_SEARCH=rg; WRG_COLOR=always; wrg -i ystemim")" "$c6_find"
        fi
        if [ -n "$have_fd" ]; then
            chk "$sh：分两段着色：fd 与 find 逐字一致" \
                "$(sh_eval "$sh" "cd '$T/src6'; unset NO_COLOR; WRG_SEARCH=fd; WRG_COLOR=always; wrg -i ystemim")" "$c6_find"
        fi
    fi

    # 后端探测顺序（用只有一个可执行名的假 PATH 逼出来）
    chk "$sh：探测顺序：PATH 里只有 rg → 选 rg" \
        "$(sh_eval "$sh" "PATH='$T/bin-rg'; _wrg_backend")" "rg"
    chk "$sh：探测顺序：PATH 里只有 fdfind → 选 fdfind" \
        "$(sh_eval "$sh" "PATH='$T/bin-fdfind'; _wrg_backend")" "fdfind"
    chk "$sh：探测顺序：PATH 里只有 fd-find → 选 fd-find" \
        "$(sh_eval "$sh" "PATH='$T/bin-fd-find'; _wrg_backend")" "fd-find"
    chk "$sh：探测顺序：PATH 里只有 fd → 选 fd" \
        "$(sh_eval "$sh" "PATH='$T/bin-fd'; _wrg_backend")" "fd"
    chk "$sh：探测顺序：一个都没有 → 回退 find" \
        "$(sh_eval "$sh" "PATH='$T/bin-none'; _wrg_backend")" "find"

    if [ -n "$real_rg" ]; then
        rm -f "$T/rg-used"
        chk "$sh：auto：PATH 里有 rg 时走 rg，输出正确" \
            "$(sh_eval "$sh" "cd '$T/src2'; PATH='$T/bin-rg':\$PATH; wrg baseTarget")" \
            './keep/Android.bp:2:    name: "baseTarget",'
        if [ -f "$T/rg-used" ]; then
            ok "$sh：auto：确实调用了 PATH 里那个 rg（wrapper 留下的记号）"
        else
            bad "$sh：auto：没有走 PATH 里的 rg（wrapper 没被调到）"
        fi
    fi

    # 强制指定：指定的可执行不存在 / 取值不认 → 报错返回 2，不许偷偷换别的
    chk "$sh：WRG_SEARCH=rg 但 PATH 里没有 rg：rc=2 + 报错" \
        "$(sh_eval "$sh" "PATH='$T/bin-none'; WRG_SEARCH=rg; wrg libfoo; echo rc=\$?")" \
        "wrg: WRG_SEARCH=rg 但 PATH 里没有 rg
rc=2"
    chk "$sh：WRG_SEARCH=fd 但 PATH 里没有 fd：rc=2 + 报错" \
        "$(sh_eval "$sh" "PATH='$T/bin-none'; WRG_SEARCH=fd; wrg libfoo; echo rc=\$?")" \
        "wrg: WRG_SEARCH=fd 但 PATH 里没有 fdfind / fd-find / fd
rc=2"
    chk "$sh：WRG_SEARCH 取值不认：rc=2 + 报错" \
        "$(sh_eval "$sh" "WRG_SEARCH=zzz; wrg libfoo; echo rc=\$?")" \
        "wrg: WRG_SEARCH 只认 auto / rg / fd / find（现在是 zzz）
rc=2"

    # ---- 高亮：只有 stdout 是终端才上色，管道里必须是纯文本 ----
    wrg_to auto "$T/o-color-auto" -i base
    chk "$sh：管道/重定向时输出里没有 ANSI 转义（grep -c ESC）" \
        "$(grep -c "$esc" "$T/o-color-auto" || true)" "0"
    chk "$sh：WRG_COLOR=always 精确匹配：只把整个目标名包成红色" \
        "$(sh_eval "$sh" "cd '$T/src2'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg baseTarget")" \
        "./keep/Android.bp:2:    name: \"${esc}[1;31mbaseTarget${esc}[0m\","
    chk "$sh：WRG_COLOR=always 模糊 -i base：命中段红粗、名字其余部分绿" \
        "$(sh_eval "$sh" "cd '$T/src2'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i base")" \
        "./keep/Android.bp:2:    name: \"${esc}[1;31mbase${esc}[0m${esc}[32mTarget${esc}[0m\","
    chk "$sh：NO_COLOR 非空时压过 WRG_COLOR=always（不着色）" \
        "$(sh_eval "$sh" "cd '$T/src2'; NO_COLOR=1; WRG_SEARCH=find; WRG_COLOR=always; wrg baseTarget")" \
        './keep/Android.bp:2:    name: "baseTarget",'
    chk "$sh：WRG_COLOR 取值不认：rc=2 + 报错" \
        "$(sh_eval "$sh" "cd '$T/src2'; WRG_COLOR=zzz; wrg baseTarget; echo rc=\$?")" \
        "wrg: WRG_COLOR 只认 auto / always / never（现在是 zzz）
rc=2"
    if [ "$have_rg" -eq 1 ] || [ -n "$have_fd" ]; then
        chk "$sh：着色输出在 auto 与 find 之间也逐字一致" \
            "$(sh_eval "$sh" "cd '$T/src2'; unset NO_COLOR; WRG_COLOR=always; wrg -i base")" \
            "$(sh_eval "$sh" "cd '$T/src2'; unset NO_COLOR; WRG_SEARCH=find; WRG_COLOR=always; wrg -i base")"
    fi
    # 真终端才自动上色：用 pty（script）验一条，验不了就跳过
    if command -v script >/dev/null 2>&1; then
        printf '%s\n' "WTOOL_PROJECT_DIR='$proj'; export WTOOL_PROJECT_DIR" \
                      ". '$proj/env.$sh'" \
                      "cd '$T/src2'" \
                      "wrg baseTarget" > "$T/tty-$sh.sh"
        out=$(env -u NO_COLOR script -qec "$sh $T/tty-$sh.sh" /dev/null 2>/dev/null | tr -d '\r')
        case $out in
            *"${esc}[1;31mbaseTarget${esc}[0m"*)
                ok "$sh：stdout 是终端时自动高亮（pty 实测）" ;;
            *)
                bad "$sh：stdout 是终端时没自动高亮 [$out]" ;;
        esac
    fi

    # ---- fd / rg 跳过隐藏目录、find 不跳（文档里写明的语义差异）----
    if [ "$have_rg" -eq 1 ]; then
        chk "$sh：隐藏目录里的目标：rg 搜不到（rc=1）" \
            "$(sh_eval "$sh" "cd '$T/src2'; WRG_SEARCH=rg; wrg libhidden; echo rc=\$?")" \
            "wrg: 没有匹配 'libhidden' 的目标名
rc=1"
    fi
    if [ -n "$have_fd" ]; then
        chk "$sh：隐藏目录里的目标：fd 搜不到（rc=1）" \
            "$(sh_eval "$sh" "cd '$T/src2'; WRG_SEARCH=fd; wrg libhidden; echo rc=\$?")" \
            "wrg: 没有匹配 'libhidden' 的目标名
rc=1"
    fi
    chk "$sh：隐藏目录里的目标：find 搜得到（rc=0）" \
        "$(sh_eval "$sh" "cd '$T/src2'; WRG_SEARCH=find; wrg libhidden; echo rc=\$?")" \
        "./.hidden/Android.bp:2:    name: \"libhidden\",
rc=0"
done

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
