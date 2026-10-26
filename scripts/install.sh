#!/bin/sh
# shell/zsh 的项目安装脚本（wtool 的契约：scripts/install.sh，ADR-021 / ADR-023）
#
# ‼️ 这个项目**没有实体要铺**（产物由引擎按 wtool.xml 的 <export_usr> 直接建成 L2 链）：
#       $WTOOL_HOME/usr/bin/zsh    → …/__output/usr/bin/zsh
#       $WTOOL_HOME/usr/lib/zsh    → …/__output/usr/lib/zsh
#       $WTOOL_HOME/usr/share/zsh  → …/__output/usr/share/zsh
#    它也不碰 $HOME、不写 rc（那是引擎的活，ADR-021）。
#    但安装时要**改产物里的二进制路径**（②，H38）并写 `$WTOOL_HOME/.zshenv`（兜底层）。
#
# 所以这个脚本的核心是两件事：**打路径补丁** + **验收**。
#
#   为什么非要在这里查：$WTOOL_HOME/usr/bin 排在 PATH 最前，所以 `$WTOOL_HOME/usr/bin/zsh`
#   就是用户**下一个登录 shell** 会起的那一个。装错发行版（在 22.04 上选中了 24.04 那套）
#   的症状是 `version 'GLIBC_2.38' not found` —— 敲 zsh 直接起不来。链是引擎在本脚本
#   **之前**建的（architecture.md §4.2 的执行顺序），所以"检查"没法更早，但"失败要响"
#   必须在这里响：宁可 `wtool install` 报错，也不要留一个起不来的登录 shell。
#
# 判据（六条，全部实测过）：
#   ① __output/usr 这条链在，而且指向**本机发行版**那一套（不是别的发行版的树）
#   ② 编译期的占位前缀已换成真实的 $WTOOL_HOME/usr（H38 的修法；不换 `zsh -f` 没有模块）
#   ③ zsh --version / zsh -c 真能跑
#   ④ `zsh -f`（不读任何 rc）能加载动态模块、fpath 也对 —— H38 的核心验收
#   ⑤ 没有"找不到的共享库"（ldd 的 not found）
#   ⑥ .zshenv + L2 链（兜底层/引擎建的那条链）也指向同一处
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

# ── 卸载：链是引擎按 journal 拆的；我们只把**二进制里的路径**还原成占位符 ──
# 还原之后产物又变成"可重定位"的：下一个人可以在别的 $WTOOL_HOME 装同一份产物，
# pack-release / pack-offline-release 也不会把本机的 $WTOOL_HOME 路径打进包。
if [ "${1:-}" = "--uninstall" ]; then
    _SEL="$PROJ/__output/usr"
    if [ -f "$_SEL/lib/zsh/.zsh-wtool-patch" ]; then
        command -v python3 >/dev/null 2>&1 || {
            bad "卸载要还原二进制里的占位前缀，但找不到 python3"; exit 1; }
        python3 "$PROJ/scripts/lib/patch-prefix.py" restore "$_SEL" || {
            bad "还原占位前缀失败 —— 产物现在绑定在本机的 $WTOOL_HOME 上"; exit 1; }
    else
        say "二进制里没有安装期补丁（没有 sidecar），不用还原。"
    fi
    say "没有实体要撤：本项目只由引擎建了 3 条 L2 链（usr/{bin,lib,share}/zsh…），"
    say "引擎会按账本逆着拆掉它们（architecture.md §4.2）。"
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

# ── ② 把编译期的占位前缀换成真实的 $WTOOL_HOME/usr ────────────────────────
#
# 二进制里的 module_path/fpath 是 **configure --prefix 的值**（构建容器里是一个
# 够长的占位符，不是 /root/.wtool/usr）。`MODULE_PATH` 又不允许从环境导入
# （Src/params.c 的 PM_DONTIMPORT），所以 `zsh -f` / 脚本（不读任何 rc）只能靠
# **改二进制里的字符串**拿到正确路径 —— 这就是 H38 的根治。
#
# 补丁逻辑在 scripts/lib/patch-prefix.py：把「占位符 + 后缀」整体缩成「新前缀 + 后缀」，
# NUL 补在区域末尾（直接 replace 会把 /lib/zsh/5.9.2 截掉，实测踩过）。
# sidecar（lib/zsh/.zsh-wtool-patch）记着占位符/当前前缀/文件清单：
#   · 重复 install（同一路径）：认出来，不重复打；
#   · 换 $WTOOL_HOME 再 install：按 sidecar 再打一次；
#   · --uninstall：还原成占位符（产物回到可重定位状态）。
case ${WTOOL_HOME:-} in
    /*) ;;
    *) bad "WTOOL_HOME 必须是绝对路径（现在是：'${WTOOL_HOME:-}'）"; exit 1 ;;
esac
_PH_FILE="$PROJ/build/prefix-placeholder"
[ -f "$_PH_FILE" ] || { bad "缺占位前缀文件：$_PH_FILE（产物和源码版本对不上？）"; exit 1; }
command -v python3 >/dev/null 2>&1 || {
    bad "找不到 python3 —— 安装期要改二进制里的路径（引擎本身也依赖 python3）"; exit 1; }
python3 "$PROJ/scripts/lib/patch-prefix.py" patch "$_SEL" "$_PH_FILE" "$WTOOL_HOME/usr" || {
    bad "把占位前缀换成 $WTOOL_HOME/usr 失败 —— zsh -f 仍然拿不到动态模块，不能装。"
    bad "修法：删掉 __output 后重跑 wtool build shell/zsh（或重新 download-release + unpack-release）。"
    exit 1; }
say "② 二进制前缀：占位符 → $WTOOL_HOME/usr"

# ── ③ 真跑一次（不是看文件在不在）────────────────────────────────────────
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

# ── ④ `zsh -f`：不读任何 rc 也要能加载模块、fpath 要对（H38 的判据）──────
# 用 env -u 把调用者 shell 里的 FPATH / ZDOTDIR 摘掉，测的才是**编译期路径**。
_ZVER=$(env -u FPATH -u MODULE_PATH -u ZDOTDIR "$_ZSH" -f -c 'print -r -- $ZSH_VERSION' 2>&1) || {
    bad "$_ZSH -f 连 \$ZSH_VERSION 都取不到：$_ZVER"; exit 1; }
_MP=$(env -u FPATH -u MODULE_PATH -u ZDOTDIR "$_ZSH" -f -c 'print -r -- $module_path[1]' 2>&1) || {
    bad "$_ZSH -f 取 \$module_path 失败：$_MP"; exit 1; }
[ "$_MP" = "$WTOOL_HOME/usr/lib/zsh/$_ZVER" ] || {
    bad "zsh -f 的 module_path[1] 是 '$_MP'，不是 '$WTOOL_HOME/usr/lib/zsh/$_ZVER'"
    bad "说明二进制补丁没生效（sidecar 在 $_SEL/lib/zsh/.zsh-wtool-patch）"
    exit 1; }
_RE=$(env -u FPATH -u MODULE_PATH -u ZDOTDIR "$_ZSH" -f -c '[[ x =~ x ]] && echo REGEX_OK' 2>&1) || {
    bad "$_ZSH -f 跑正则匹配失败（动态模块拿不到）：$_RE"; exit 1; }
[ "$_RE" = REGEX_OK ] || { bad "$_ZSH -f 正则匹配输出不对：$_RE"; exit 1; }
_MOD=$(env -u FPATH -u MODULE_PATH -u ZDOTDIR "$_ZSH" -f -c 'zmodload zsh/parameter && echo MOD_OK' 2>&1) || {
    bad "$_ZSH -f zmodload zsh/parameter 失败：$_MOD"; exit 1; }
[ "$_MOD" = MOD_OK ] || { bad "$_ZSH -f zmodload 输出不对：$_MOD"; exit 1; }
_FP=$(env -u FPATH -u MODULE_PATH -u ZDOTDIR "$_ZSH" -f -c 'print -rl -- $fpath' 2>&1) || {
    bad "$_ZSH -f 取 \$fpath 失败：$_FP"; exit 1; }
printf '%s\n' "$_FP" | grep -Fxq -- "$WTOOL_HOME/usr/share/zsh/$_ZVER/functions" || {
    bad "zsh -f 的 fpath 里没有 '$WTOOL_HOME/usr/share/zsh/$_ZVER/functions'"
    bad "（fpath 的编译期路径也没换对）"
    exit 1; }
say "④ zsh -f：module_path / regex / zmodload / fpath 全对"

# ── ⑤ 共享库 ─────────────────────────────────────────────────────────────
# `ldd` 在缺库时打 "xxx => not found"，退出码仍然是 0 —— 必须自己看输出。
_MISSING=$(ldd "$_ZSH" 2>/dev/null | awk '/not found/{print $1}' | paste -sd' ' -)
[ -z "$_MISSING" ] || {
    bad "$_ZSH 缺共享库：$_MISSING"
    bad "这些库要在**目标机**上存在（基础镜像里有、别人机器上不一定有）。"
    exit 1
}
say "共享库：齐（$(ldd "$_ZSH" | awk '{print $1}' | paste -sd' ' -)）"

# ── ⑥a 引擎建的那条 L2 链也得指向同一个东西 ───────────────────────────────
_L2="$WTOOL_HOME/usr/bin/zsh"
if [ -e "$_L2" ] || [ -L "$_L2" ]; then
    say "L2 链：$_L2 -> $(readlink -- "$_L2" 2>/dev/null || printf '(实体)')"
else
    # 不算致命（--no-script / 手工跑本脚本时会没有），但要说出来。
    say "注意：$_L2 还不在 —— 正常 wtool install 会先建它，这里是手工跑吧？"
fi

# ── ⑥b $WTOOL_HOME/.zshenv：module_path / fpath（补丁之后的兜底层）────────
#
# ② 的二进制补丁已经让 `zsh -f` / 脚本拿到正确路径；这份 `.zshenv` 继续写，
# 是为了**老版本装出来的二进制**、以及从 bash 起的交互式 zsh（ZDOTDIR 路）：
#   · 从 bash 敲 `zsh` —— env.* 导出 ZDOTDIR=$WTOOL_HOME，zsh 读这里；
#   · 补丁生效前留下的旧 zsh（升级场景）靠这里仍能用交互式。
# 读完立刻把 ZDOTDIR 还原成 $HOME，**保证随后仍然读用户的 ~/.zshrc**。
#
# 2026-10-21 VM 实测的症状（当时没有它）：`zsh: failed to load module 'zsh/zle':
# /root/.wtool/usr/lib/zsh/5.9.2/zsh/zle.so: ... Permission denied`。
# 现在主修法是 ②（改二进制），这里按"双保险"保留，别删。
_ZSENV="$WTOOL_HOME/.zshenv"
cat > "$_ZSENV" <<ZEOF
# 由 wtool 生成 —— **别手改**，重装会覆盖。
# 读法：ZDOTDIR 指向这里时 zsh 会自动读它（在任何 rc、任何模块加载之前）。
# 路径一律用 ${WTOOL_HOME} 现算（**不许写死某台机器的绝对路径** —— 这份文件
# 会被打进整机包，装到别人的机器上；写死就会去不存在的目录找 .so）。
if [ -n "\${ZSH_VERSION:-}" ] && [ -d "\${WTOOL_HOME}/usr/lib/zsh" ]; then
    module_path=("\${WTOOL_HOME}/usr/lib/zsh/\$ZSH_VERSION" \$module_path)
    fpath=("\${WTOOL_HOME}/usr/share/zsh/\$ZSH_VERSION/functions" "\${WTOOL_HOME}/usr/share/zsh/site-functions" \$fpath)
fi
# 读完立刻把 ZDOTDIR 还原成 HOME —— 这样随后仍然读你的 ~/.zshrc
ZDOTDIR="\$HOME"
export ZDOTDIR
ZEOF
say "⑥ .zshenv：$_ZSENV（兜底层：module_path/fpath，读完还原 ZDOTDIR）"

cat <<EOF

⚠️ 最后一步请**自己**确认（别只信这句）：开一个**新的登录 shell** 敲
     zsh --version && zsh -ic 'echo LOGIN_OK'
   如果新 shell 起不来，立刻：wtool uninstall shell/zsh
EOF
