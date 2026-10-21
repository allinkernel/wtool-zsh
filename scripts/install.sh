#!/bin/sh
# shell/zsh 的项目安装脚本（wtool 的契约：scripts/install.sh，ADR-021 / ADR-023）
#
# ‼️ 这个项目**没有实体要铺**。产物由引擎按 wtool.xml 的 <export_usr> 直接建成 L2 链：
#       $WTOOL_HOME/usr/bin/zsh    → …/__output/usr/bin/zsh
#       $WTOOL_HOME/usr/lib/zsh    → …/__output/usr/lib/zsh
#       $WTOOL_HOME/usr/share/zsh  → …/__output/usr/share/zsh
#    它也不碰 $HOME、不写 rc（那是引擎的活，ADR-021）。
#
# 所以这个脚本只剩一件**救命的**事：**验收**。
#
#   为什么非要在这里查：$WTOOL_HOME/usr/bin 排在 PATH 最前，所以 `$WTOOL_HOME/usr/bin/zsh`
#   就是用户**下一个登录 shell** 会起的那一个。装错发行版（在 22.04 上选中了 24.04 那套）
#   的症状是 `version 'GLIBC_2.38' not found` —— 敲 zsh 直接起不来。链是引擎在本脚本
#   **之前**建的（architecture.md §4.2 的执行顺序），所以"检查"没法更早，但"失败要响"
#   必须在这里响：宁可 `wtool install` 报错，也不要留一个起不来的登录 shell。
#
# 判据（四条，全部实测过）：
#   ① __output/usr 这条链在，而且指向**本机发行版**那一套（不是别的发行版的树）
#   ② zsh --version 有输出（动态加载失败/glibc 版本不够都会在这一步炸）
#   ③ zsh -c 真能跑（非交互；交互那条由人验，见 README「装完怎么验」）
#   ④ 没有"找不到的共享库"（ldd 的 not found）——这是换机器时最容易漏的一条
set -eu

PROJ=$(cd -- "$(dirname -- "$0")/.." && pwd)

say() { printf '  [shell/zsh] %s\n' "$*"; }
bad() { printf '错误: %s\n' "$*" >&2; }

host_target() {   # 宿主是哪个 target（照 /etc/os-release，不猜）
    _id=""; _ver=""
    if [ -r /etc/os-release ]; then
        _id=$(sed -n 's/^ID=["]*\([^"]*\)["]*$/\1/p' /etc/os-release | head -1)
        _ver=$(sed -n 's/^VERSION_ID=["]*\([^"]*\)["]*$/\1/p' /etc/os-release | head -1)
    fi
    [ -n "$_id" ] && [ -n "$_ver" ] || { bad "读不出 /etc/os-release 里的 ID / VERSION_ID"; exit 1; }
    printf '%s_%s\n' "$_id" "$_ver"
}

# ── 卸载：什么都不用撤（链是引擎按 journal 拆的）─────────────────────────
if [ "${1:-}" = "--uninstall" ]; then
    say "没有实体要撤：本项目只由引擎建了 3 条 L2 链（usr/{bin,lib,share}/zsh…），"
    say "引擎会按账本逆着拆掉它们（architecture.md §4.2）。项目脚本这一步无事可做。"
    exit 0
fi

say "项目目录：$PROJ"
[ -n "${WTOOL_HOME:-}" ] || { bad "WTOOL_HOME 没设（引擎应该把它导进来）"; exit 1; }
say "WTOOL_HOME：$WTOOL_HOME"

_t=$(host_target)

# ── ① 选中的那一套，必须是**本机发行版**的 ────────────────────────────────
_SEL="$PROJ/__output/usr"
[ -L "$_SEL" ] || [ -d "$_SEL" ] || {
    bad "$_SEL 不在 —— 产物还没做出来，或者三条发行版别名链还没建。"
    bad "修法（宿主上一条命令）：sh $PROJ/scripts/build.sh"
    exit 1
}
_WANT="$_t/usr"
_HAVE=$(readlink -- "$_SEL" 2>/dev/null || printf '%s' "(实体目录，不是链)")
if [ "$_HAVE" != "$_WANT" ]; then
    bad "__output/usr 指向 '$_HAVE'，但本机是 $_t（应该指向 $_WANT）。"
    bad "在别的发行版上编的产物装到这台机器上，zsh 起来会报 GLIBC 版本不够。"
    bad "修法：ln -sfn $_WANT $PROJ/__output/usr"
    exit 1
fi
say "选中：__output/usr -> $_HAVE（本机 $_t）"

_ZSH="$_SEL/bin/zsh"
[ -x "$_ZSH" ] || { bad "$_ZSH 不存在或不可执行"; exit 1; }

# ── ②③ 真跑一次（不是看文件在不在）────────────────────────────────────────
_VER=$("$_ZSH" --version 2>&1) || {
    bad "$_ZSH --version 跑不起来：$_VER"
    bad "多半是 glibc 版本不够（换发行版编的）或者产物被截断了。"
    exit 1
}
case $_VER in
    zsh\ *) ;;
    *) bad "$_ZSH --version 的输出不像 zsh：$_VER"; exit 1 ;;
esac
say "$_VER"

_OUT=$("$_ZSH" -c 'echo NONINTERACTIVE_OK' 2>&1) || {
    bad "$_ZSH -c 起不来：$_OUT"; exit 1; }
[ "$_OUT" = NONINTERACTIVE_OK ] || { bad "$_ZSH -c 输出不对：$_OUT"; exit 1; }
say "非交互自检：$_OUT"

# ── ④ 共享库 ─────────────────────────────────────────────────────────────
# `ldd` 在缺库时打 "xxx => not found"，退出码仍然是 0 —— 必须自己看输出。
_MISSING=$(ldd "$_ZSH" 2>/dev/null | awk '/not found/{print $1}' | paste -sd' ' -)
[ -z "$_MISSING" ] || {
    bad "$_ZSH 缺共享库：$_MISSING"
    bad "这些库要在**目标机**上存在（基础镜像里有、别人机器上不一定有）。"
    exit 1
}
say "共享库：齐（$(ldd "$_ZSH" | awk '{print $1}' | paste -sd' ' -)）"

# ── 引擎建的那条 L2 链也得指向同一个东西 ─────────────────────────────────
_L2="$WTOOL_HOME/usr/bin/zsh"
if [ -e "$_L2" ] || [ -L "$_L2" ]; then
    say "L2 链：$_L2 -> $(readlink -- "$_L2" 2>/dev/null || printf '(实体)')"
else
    # 不算致命（--no-script / 手工跑本脚本时会没有），但要说出来。
    say "注意：$_L2 还不在 —— 正常 wtool install 会先建它，这里是手工跑吧？"
fi

# ── ⑤ $WTOOL_HOME/.zshenv：module_path / fpath ─────────────────────────────
#
# zsh 的 module_path/fpath **初值**是编译时前缀（构建容器里的 /root/.wtool/usr），
# 而 `MODULE_PATH` **不允许从环境导入**（Src/params.c 写着 PM_DONTIMPORT，
# "not imported for security reasons"）→ 只能靠 `.zshenv` 在
# "**任何 rc、任何模块加载之前**"改。
#
# 谁读这份：
#   · 从 bash 敲 `zsh` —— 项目的 env.* 导出了 ZDOTDIR=$WTOOL_HOME，zsh 就读这里；
#   · zsh 当登录 shell —— 引擎写进 ~/.zshenv 的那段（同样的内容）兜住。
# 读完立刻把 ZDOTDIR 还原成 $HOME，**保证随后仍然读用户的 ~/.zshrc**。
#
# 2026-10-21 VM 实测的症状（没有它）：`zsh: failed to load module 'zsh/zle':
# /root/.wtool/usr/lib/zsh/5.9.2/zsh/zle.so: ... Permission denied`，zsh 直接不能用。
_ZSENV="$WTOOL_HOME/.zshenv"
cat > "$_ZSENV" <<ZEOF
# 由 wtool 的 shell/zsh 项目 install.sh 生成 —— **别手改**，重装会覆盖。
# 读法：ZDOTDIR 指向这里时 zsh 会自动读它（在任何 rc、任何模块加载之前）。
if [ -n "\${ZSH_VERSION:-}" ] && [ -d "$WTOOL_HOME/usr/lib/zsh" ]; then
    module_path=("$WTOOL_HOME/usr/lib/zsh/\$ZSH_VERSION" \$module_path)
    fpath=("$WTOOL_HOME/usr/share/zsh/\$ZSH_VERSION/functions" "$WTOOL_HOME/usr/share/zsh/site-functions" \$fpath)
fi
# 读完立刻把 ZDOTDIR 还原成 HOME —— 这样随后仍然读你的 ~/.zshrc
ZDOTDIR="\$HOME"
export ZDOTDIR
ZEOF
say "⑤ .zshenv：$_ZSENV（module_path/fpath，读完还原 ZDOTDIR）"

cat <<EOF

⚠️ 最后一步请**自己**确认（别只信这句）：开一个**新的登录 shell** 敲
     zsh --version && zsh -ic 'echo LOGIN_OK'
   如果新 shell 起不来，立刻：wtool uninstall shell/zsh
EOF
