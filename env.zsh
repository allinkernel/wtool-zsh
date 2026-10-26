# 由 $WTOOL_HOME/env.zsh 里的 wtool 块 source。与 env.bash 逐字等价
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
    echo "       请在你的 ~/.zshrc 最后加上这两行（bash 用 env.bash）：" >&2
    echo "         export WTOOL_HOME=~/.wtool" >&2
    echo "         source \${WTOOL_HOME}/env.zsh" >&2
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

# ⚠️ 本文件**不改你的 .zshrc / 不禁用系统 zsh**：$WTOOL_HOME/usr/bin 排在 PATH 最前，
#    所以 `zsh` 就是这一份；想临时回到系统那个用 `command -v zsh` 看路径、
#    或直接敲 /usr/bin/zsh。卸载 `wtool uninstall shell/zsh` 之后一切照旧。

# ---------------------------------------------------------------------------
# 下面这一段是**这个项目独有**的（env.bash 里没有对应物，见那边的说明）：
# zsh 把 `--prefix` 编进了二进制，`fpath` 与 `module_path` 的**初值**就是那个
# 构建时的占位前缀（install.sh 在安装时把它换成本机的 $WTOOL_HOME/usr，见 H38）。
# 所以正常情况下 `zsh -f` / 脚本也已经能加载模块；这里**仍然**再设一遍，是兜底：
#   · 升级前装好的旧二进制（还没有二进制补丁）；
#   · 从 bash 起的交互式 zsh（ZDOTDIR 路）—— 双保险。
# 两个都用 $WTOOL_HOME 拼，**绝不写死构建路径**；$ZSH_VERSION 是当前这份 zsh 的
# 版本目录名（5.9.2），目录不存在时 zsh 自己会忽略这一项。
#
# ⚠️ **为什么不能只靠环境变量**（实测 + 源码）：zsh 的 MODULE_PATH
#    **不从环境导入** —— Src/params.c 那条声明写着
#    `IPDEF8("MODULE_PATH", …, PM_DONTIMPORT|PM_RESTRICTED|PM_TIED)`，
#    注释是 "MODULE_PATH is not imported for security reasons"（防止用环境变量注入
#    恶意 .so）。实测 `MODULE_PATH=… zsh -c 'print -l $module_path'` 打印的仍然是
#    编译进去的路径。所以旧二进制只能靠 rc / .zshenv；**新二进制靠安装期补丁**。
#    这也是为什么 `zsh -f` 在**旧**产物上拿不到动态模块 —— 但新产物已经没有这个问题。
#
# ⚠️ 重复 prepend 不会坏事（zsh 会按顺序找，找到第一个就用）；别为了"去重"把这段删掉。
if [ -n "${ZSH_VERSION:-}" ]; then
    fpath=("$WTOOL_HOME/usr/share/zsh/site-functions"
           "$WTOOL_HOME/usr/share/zsh/$ZSH_VERSION/functions" $fpath)
    module_path=("$WTOOL_HOME/usr/lib/zsh/$ZSH_VERSION" $module_path)
    # FPATH **可以**从环境导入（Src/params.c: `IPDEF8("FPATH", &fpath, "fpath", PM_TIED)`，
    # 没有 PM_DONTIMPORT）—— 实测 `FPATH=… zsh -c 'print -l $fpath[1]'` 认。
    # 所以导出去：**子进程 / 不读 rc 的 `zsh -c` 脚本**也能 autoload 到这套 functions，
    # 否则它们用的是编译进去的**旧构建前缀**（目标机上不存在的路径）。
    # MODULE_PATH 就没这个待遇（见上面那段），所以只导 fpath。
    export FPATH
fi
