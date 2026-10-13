#!/bin/sh
# shell/zsh —— 在容器里为每个发行版编一棵 zsh（wtool ③ 类项目，ADR-0045 §1.4）
#
# 两种跑法，**只有第一种是引擎用的**：
#
#   ① 容器里（引擎驱动，`build/layers.tsv` 那一行就是它）：
#        sh /proj/scripts/build.sh --in-docker --target=ubuntu_24.04
#      装依赖 → 编 → `make install` 到 /root/.wtool/usr（**影子 $HOME** 的形状）。
#      引擎随后把容器里 `root/.wtool/*` 导成
#          __output/<target>/<层>/payload/usr/{bin,lib,share}
#      （见 harness/architecture.md §4 的"引擎对每一层做四件事"）。
#
#   ② 宿主上（人敲，一条命令从零到"能装"）：
#        sh scripts/build.sh
#      = 引擎编三个发行版的层 → 给每个发行版做一条 `usr` 别名链 →
#        把**本机这个发行版**那套选成 `__output/usr`。
#      `wtool.xml` 的 `<export_usr src="__output/usr"/>` 认的就是最后这条链
#      （三条链都是**相对**软链，落在 `__output/` 里，不进 git）。
#
# ‼️ **有 `build/layers.tsv` 时 `wtool build` 不跑这个脚本**（引擎自己驱动容器，
#    wtool.sh 的 build 分派点先看层清单）。所以第 ② 种跑法不会递归 ——
#    它是给人用的便捷入口，不是引擎的第二条构建路径。
# ‼️ 容器的 `/proj` 是**只读**挂的：这个脚本在容器里**不往项目目录写任何东西**，
#    产物只落 `/root/.wtool/`（引擎要的就是这个形状）。
#
# 为什么按发行版各编一份（实测，见 README「三个发行版」一节）：
#   · 24.04 编出来的二进制要求 GLIBC_2.38 → 22.04（2.35）上起不来；
#   · `--enable-cap` 会让二进制硬依赖 libcap.so.2，而 ubuntu:26.04 基础镜像里没有它
#     → 统一 `--disable-cap`；
#   · 基础镜像里没有 zsh / gcc / xz，构建层自己装（**先换 http 源**：镜像里没有 CA）。

set -eu

# ── 影子 $HOME 的形状（引擎的约定，别改）────────────────────────────────
# `wt_layer_export` 只取容器里 `root/.wtool/*` 并剥掉两节 → payload 相对 $WTOOL_HOME。
PREFIX=/root/.wtool/usr

# 换 apt 源用的镜像（http！https 要 CA，基础镜像里没有）。
MIRROR=${ZSH_BUILD_MIRROR:-mirrors.ustc.edu.cn}

log() { printf '  [build.sh] %s\n' "$*"; }

die() { printf '错误: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
用法:
  sh scripts/build.sh                      # 宿主上：编三个发行版并选本机那套
  sh scripts/build.sh --in-docker --target=ubuntu_24.04
                                           # 容器里（build/layers.tsv 调它）
  sh scripts/build.sh --list               # 只打印 targets.tsv 的内容
EOF
}

# ── 读 build/targets.tsv：<target>\t<镜像>[\t<代号>\t<glibc>] ──────────────
# 只认前两列（引擎的 docker-targets 也是这么读的）；后两列是给人看的。
targets_file() { printf '%s/build/targets.tsv\n' "$PROJ"; }

target_image() {   # <target>
    awk -F'\t' -v t="$1" '$1==t{print $2; found=1} END{exit !found}' "$(targets_file)"
}

host_target() {   # 宿主是哪个 target（照 /etc/os-release，不猜）
    _id=""; _ver=""
    if [ -r /etc/os-release ]; then
        _id=$(sed -n 's/^ID=["]*\([^"]*\)["]*$/\1/p' /etc/os-release | head -1)
        _ver=$(sed -n 's/^VERSION_ID=["]*\([^"]*\)["]*$/\1/p' /etc/os-release | head -1)
    fi
    [ -n "$_id" ] && [ -n "$_ver" ] || die "读不出 /etc/os-release 里的 ID / VERSION_ID"
    printf '%s_%s\n' "$_id" "$_ver"
}

# ── 容器里：把依赖装好、把 zsh 编出来 ────────────────────────────────────
apt_prepare() {
    # deb822（24.04+）和老的 one-line 两种形状都要认。**只换主机名**，
    # /ubuntu/ 那一段路径跟着镜像走。
    _changed=0
    for _f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
        [ -f "$_f" ] || continue
        grep -qE '(archive|security)\.ubuntu\.com' "$_f" 2>/dev/null || continue
        sed -i -E "s|https?://(archive\|security)\.ubuntu\.com|http://$MIRROR|g" "$_f"
        _changed=1
    done
    [ "$_changed" = 1 ] && log "apt 源换到 http://$MIRROR（http，不用 CA）"

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    # autoconf：**git 检出里没有 `configure`**（只有 configure.ac）—— 上游 release 的
    #   tarball 才带生成好的 configure。我们编的是自己 fork 的源码树，所以得先跑
    #   `Util/preconfig`（= autoconf + autoheader）。少了它报的是
    #   `./configure: not found`，看着像"源码没拷进去"，很容易查错方向。
    # xz-utils：这条路上还用不到（源码是从 /proj 拷的），但留着 ——
    #   一旦改成下载上游 tarball（.tar.xz），少了它就是一个难查的失败。
    # libncurses-dev：**没有它 configure 直接失败** ——
    #   `No terminal handling library was found on your system`。
    #   基础镜像里只有运行库 libtinfo.so.6，没有 `ncurses.h`（头文件在 -dev 包里），
    #   而 zsh 必须要一个 termcap/curses 库才能编行编辑那一套。
    apt-get install -y -qq --no-install-recommends \
        build-essential autoconf ca-certificates xz-utils libncurses-dev >/dev/null
    log "依赖就绪：$(cc --version | head -1)；$(autoconf --version | head -1)"
}

in_docker() {   # <target>
    _t=$1
    log "target=$_t  prefix=$PREFIX"

    apt_prepare

    # 源码：从只读的 /proj 拷到可写的 /src。__output/__layer/__release 是产物，
    # 不进编译（`.git` 也不要 —— 好几十 MB，而且 `make` 用不着它）。
    rm -rf /src
    mkdir -p /src
    tar -C /proj -cf - \
        --exclude=./.git --exclude=./__output --exclude=./__layer --exclude=./__release \
        . | tar -C /src -xf -
    [ -f /src/configure.ac ] || die "/proj 里没有 zsh 源码（configure.ac 都没有）"
    log "源码就位：$(du -sh /src | cut -f1)"

    # ‼️ 三个 --disable-* 都是**有意的**（README 有实测数字）：
    #   --disable-cap    → 否则二进制硬依赖 libcap.so.2，26.04 基础镜像里没有
    #   --disable-gdbm   → 否则依赖 libgdbm（默认就是 off，写出来是为了"别哪天被默认值改了"）
    #   --disable-pcre   → 否则依赖 libpcre（同上）
    cd /src
    if [ ! -f configure ]; then
        # git 检出没有 configure（上游只在 release tarball 里带）。preconfig 会跑
        # autoconf + autoheader 把它生成出来 —— 这一步在**容器里**做，
        # 免得宿主被塞进一个 autoconf 版本决定的 300KB 生成文件（也不进 git）。
        log "Util/preconfig（autoconf + autoheader —— git 检出里没有 configure）"
        ./Util/preconfig >/tmp/zsh-preconfig.log 2>&1 \
            || { tail -20 /tmp/zsh-preconfig.log >&2; die "Util/preconfig 失败（日志 /tmp/zsh-preconfig.log）"; }
    fi
    log "configure --prefix=$PREFIX"
    ./configure --prefix="$PREFIX" --disable-cap --disable-gdbm --disable-pcre >/tmp/zsh-configure.log 2>&1 \
        || { tail -30 /tmp/zsh-configure.log >&2; die "configure 失败（日志 /tmp/zsh-configure.log）"; }

    log "make -j$(nproc)"
    make -j"$(nproc)" >/tmp/zsh-make.log 2>&1 \
        || { tail -30 /tmp/zsh-make.log >&2; die "make 失败（日志 /tmp/zsh-make.log）"; }

    # ‼️ `make install` **不带 man / runhelp**，两个理由：
    #   ① `install.man` 要 yodl 生成 Doc/zsh*.1，容器里没装；硬跑会卡在
    #      `test -s zsh.1 || exit 1`（实测：整个 make install 失败，前面几步的成果白费）。
    #   ② man 会落在 $PREFIX/share/man —— 而 `$WTOOL_HOME/usr/share/` 是**所有项目共享**
    #      的：`<export_usr>` 会把 `share/man` 也当成一个条目导出去，于是
    #      `$WTOOL_HOME/usr/share/man` 整条变成我们这个项目的链，**盖住别人**。
    #      宁可不要 man（要 `man zsh` 就用系统装的那个 zsh 的 man，或者 `zsh -c 'help x'`）。
    log "make install.bin install.modules install.fns（不带 man —— 见脚本里的说明）"
    make install.bin install.modules install.fns >/tmp/zsh-install.log 2>&1 \
        || { tail -30 /tmp/zsh-install.log >&2; die "make install 失败（/tmp/zsh-install.log）"; }

    # 防御：`Doc/install.man` 失败前可能已经 mkdir 了空的 share/man/man1。
    # 空目录一样会被 <export_usr> 当成一个 part 条目导出去（上面第 ② 条）。
    rm -rf -- "$PREFIX/share/man"

    # 编出来的东西在这个容器里立刻验一次 —— 起不来要在这里就报，
    # 别等装到别人的机器上才发现。
    [ -x "$PREFIX/bin/zsh" ] || die "$PREFIX/bin/zsh 没生成"
    log "容器里自检：$("$PREFIX/bin/zsh" --version)"
    log "运行时依赖：$(ldd "$PREFIX/bin/zsh" | awk '{print $1}' | paste -sd' ' -)"
    log "glibc 门槛：$(objdump -p "$PREFIX/bin/zsh" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)"
    log "产物大小：$(du -sh "$PREFIX" | cut -f1)  （$(find "$PREFIX" -type f | wc -l) 个文件）"
    log "形状：$(cd "$PREFIX" && find . -maxdepth 2 -type d | sed 's|^\./||' | sort | paste -sd' ' -)"
    log "模块：$(find "$PREFIX" -name '*.so' | wc -l) 个 .so"
}

# ── 宿主上：引擎编层 → 每个发行版一条 usr 别名链 → 选本机那套 ─────────────
# 三条链都**相对**，落在 __output/ 里：
#   __output/ubuntu_22.04/usr -> main/payload/usr
#   __output/ubuntu_24.04/usr -> main/payload/usr
#   __output/ubuntu_26.04/usr -> main/payload/usr
#   __output/usr             -> ubuntu_24.04/usr      ← 本机这套（wtool.xml 认它）
on_host() {
    _t=$(host_target)
    if [ -z "$(target_image "$_t" 2>/dev/null || true)" ]; then
        die "本机是 $_t，但 build/targets.tsv 里没有这个 target。
  要么在有这个发行版的机器上编（或者在容器里编），要么往 targets.tsv 里加一行。
  现有的：$(cut -f1 "$(targets_file)" | grep -v '^#' | paste -sd' ' -)"
    fi

    # 引擎在哪：先 `$PATH`（登录 shell 里 wtool 就是一条命令），找不到就退回
    # **绝对路径** —— 引擎装在 $WTOOL_HOME/wtool/wtool-base-tools/bin/wtool，
    # 非登录 shell / 没 source 过 rc 的场合 `$PATH` 里没有它（实测踩过：
    # `sh scripts/build.sh` 直接报"找不到 wtool 命令"）。
    WT=${WTOOL:-wtool}
    if ! command -v "$WT" >/dev/null 2>&1; then
        _wt_abs="${WTOOL_HOME:-$HOME/.wtool}/wtool/wtool-base-tools/bin/wtool"
        [ -x "$_wt_abs" ] || die "找不到 wtool 命令：\$PATH 里没有，$_wt_abs 也不在。
  先把 wtool 装好（工作区根目录 ./install.sh），或者 WTOOL=<wtool 的绝对路径> sh $0"
        log "wtool 不在 \$PATH 里 → 用绝对路径 $_wt_abs"
        WT=$_wt_abs
    fi

    log "① $WT build（三个发行版各一层，容器里编）"
    "$WT" build "$PROJ"

    log "② 每个发行版一条 usr 别名链"
    for _tt in $(awk -F'\t' '!/^#/ && NF>=2 {print $1}' "$(targets_file)"); do
        _pay="__output/$_tt/main/payload/usr"
        [ -d "$PROJ/$_pay" ] || { log "   跳过 $_tt（__output/$_tt/main/payload/usr 不在）"; continue; }
        rm -f "$PROJ/__output/$_tt/usr"
        ln -s "main/payload/usr" "$PROJ/__output/$_tt/usr"
        log "   __output/$_tt/usr -> main/payload/usr"
    done

    log "③ 选本机这套：$_t"
    ln -sfn "$_t/usr" "$PROJ/__output/usr"
    log "   __output/usr -> $_t/usr"

    # 选完立刻验：链断没断、二进制是不是这个发行版的、它能不能起来。
    [ -x "$PROJ/__output/usr/bin/zsh" ] || die "__output/usr/bin/zsh 不是可执行文件 —— 选择链没接上"
    log "自检：$("$PROJ/__output/usr/bin/zsh" --version)"

    cat <<EOF

就绪。接着：
  wtool install   $PROJ
  wtool validate  $PROJ

⚠️ __output/usr 指的是**本机这个发行版**那一套（$_t），它不进 git。
   换台机器（别的发行版）要重新跑一次本脚本第 ②③ 步，
   或者 wtool download-release + unpack-release 之后按 README「三个发行版」那节选一次。
EOF
}

# ── 入口 ────────────────────────────────────────────────────────────────
MODE=host
TARGET=""
PROJ=$(cd -- "$(dirname -- "$0")/.." && pwd)

while [ $# -gt 0 ]; do
    case $1 in
        --in-docker) MODE=docker ;;
        --target=*)  TARGET=${1#--target=} ;;
        --list)      MODE=list ;;
        -h|--help)   usage; exit 0 ;;
        *)           usage >&2; exit 2 ;;
    esac
    shift
done

case $MODE in
    list)
        cat "$(targets_file)"
        ;;
    docker)
        [ -n "$TARGET" ] || die "--in-docker 要配 --target=<target>（容器里靠它知道自己在编哪个发行版）"
        in_docker "$TARGET"
        ;;
    host)
        on_host
        ;;
esac
