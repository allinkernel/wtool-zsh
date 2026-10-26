# 由 $WTOOL_HOME/env.bash 里的 wtool 块 source。与 env.zsh 逐字等价
# （只有本条注释、报错里那句提示、和下半段那段 shell 专有的东西不同）。
#
# shell/zsh 是**③ 类 docker 跨发行版构建项目**（ADR-0045 §1.4）：源码就是 zsh 本身，
# 在容器里按发行版各编一份，产物由 <export_usr> 导出成 L2 链
#   $WTOOL_HOME/usr/bin/zsh → …/__output/usr/bin/zsh
# 加载器保证以下变量已存在，所以这里不需要任何 get_this_dir 之类的路径魔法：
#   WTOOL_HOME          .wtool 根目录（**由 rc 里那行 export 声明**，ADR-0045 / D48）
#   WTOOL_PROJECT_ID    例如 shell/zsh
#   WTOOL_PROJECT_DIR   $WTOOL_HOME/wtool/shell/zsh（L1 链，ADR-0045 §1.3）
#   WTOOL_PROJECT_ROOT  仓库的真实路径
#
# WTOOL_HOME 不再自定位，所以这里只**校验**：空 / 目录不在 → 打印"请加哪两行"并报错，
# 绝不静默半装（D48 的判据；措辞与 pre_architecture.md §10.4 一致）。
if [ -z "${WTOOL_HOME:-}" ] || [ ! -d "$WTOOL_HOME" ]; then
    echo "wtool: WTOOL_HOME 未设置或不存在（当前值：'${WTOOL_HOME:-}'）。" >&2
    echo "       zsh 在 $WTOOL_HOME/usr/bin/zsh —— 没有 WTOOL_HOME 就找不到它。" >&2
    echo "       请在你的 ~/.bashrc 最后加上这两行（zsh 用 env.zsh）：" >&2
    echo "         export WTOOL_HOME=~/.wtool" >&2
    echo "         source \${WTOOL_HOME}/env.bash" >&2
    return 1 2>/dev/null || exit 1
fi

# 单独 source（不经 wtool 块）时的兜底：L1 路径就是项目在 $WTOOL_HOME 里的稳定地址
[ -n "${WTOOL_PROJECT_DIR:-}" ] || WTOOL_PROJECT_DIR="$WTOOL_HOME/wtool/shell/zsh"
export WTOOL_ZSH_DIR="$WTOOL_PROJECT_DIR"

# 让 `zsh` 去读 `$WTOOL_HOME/.zshenv`（那里按 $WTOOL_HOME 现算 module_path/fpath）。
#
# 这条是**兜底层**：安装时 scripts/install.sh 已经把二进制里的编译期占位前缀换成
# $WTOOL_HOME/usr（H38），所以 `zsh -f` / 脚本直接用编译进去的路径就能加载模块。
# .zshenv 仍然有用：升级前装好的旧二进制、以及从 bash 起的交互式 zsh（ZDOTDIR 路）。
# MODULE_PATH 不允许从环境导入，所以旧二进制只能靠它；新二进制不靠它也能工作。
# 那份 .zshenv 读完会把 ZDOTDIR 还原成 $HOME，所以你的 ~/.zshrc 照旧生效。
export ZDOTDIR="${ZDOTDIR:-$WTOOL_HOME}"

# ⚠️ 本文件**不往 PATH 里塞东西**：$WTOOL_HOME/usr/bin 由引擎统一放最前
#    （ADR-0045 §1.2 / D48），每个项目再插一次只会插出重复项。
#    这一段留下来是因为**装错了要能立刻看出来**：缺了它，症状是"wtool install
#    说装好了，可敲 zsh 还是系统那个 / command not found" —— 那种半装状态最难查。

# ⚠️ 本文件**不改你的 .bashrc / 不禁用系统 zsh**：$WTOOL_HOME/usr/bin 排在 PATH 最前，
#    所以 `zsh` 就是这一份；想临时回到系统那个用 `command -v zsh` 看路径、
#    或直接敲 /usr/bin/zsh。卸载 `wtool uninstall shell/zsh` 之后一切照旧。

# ---------------------------------------------------------------------------
# ⚠️ **bash 这一段没有对应物，是有意的，不是漏了**
# env.zsh 在这里设 `fpath` / `module_path` —— 那是 **zsh 自己的**两个特殊参数。
# zsh 把 `--prefix`（构建时的占位前缀）编进了二进制；`scripts/install.sh` 在安装时
# 会把它换成本机的 $WTOOL_HOME/usr（H38），env.zsh 里那段是给旧二进制/交互式兜底。
# bash 里根本没有这两个变量（也不加载 zsh 的 .so 模块），所以这里无事可做：
# **这个项目对 bash 唯一的贡献，就是让 $WTOOL_HOME/usr/bin 里出现一条 `zsh` 命令**
# （L2 链），而 PATH 是引擎统一管的。
#
# 别为了"两份看起来一样"往这里塞一段跟 zsh 无关的东西 —— 那只会让下一个人
# 以为 bash 也需要 fpath。
# ---------------------------------------------------------------------------
