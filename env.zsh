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
# 为什么必须：zsh 的 module_path/fpath 是**编译时前缀**（构建容器里的
# /root/.wtool/usr/…），换机器就加载不到动态模块（zsh/zle、zsh/parameter…）；
# MODULE_PATH 又不允许从环境导入 —— `.zshenv` 是**唯一**能修的位置（2026-10-21 VM 实测）。
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
# 构建时的绝对路径（容器里是 /root/.wtool/usr）。本机的 $WTOOL_HOME 十有八九
# 不是同一个串（默认 ~/.wtool = /home/<你>/.wtool），所以**必须现算**：
#   · 不设 fpath        → compinit 之类的 autoload 一个都找不到（静默失败，最难查）
#   · 不设 module_path  → `zmodload zsh/parameter` 之类去 /root/.wtool/usr/lib/zsh/… 找
#                          .so，一个都加载不上（症状是"补全和行编辑像个残废 zsh"）
# 两个都用 $WTOOL_HOME 拼，**绝不写死构建路径**；$ZSH_VERSION 是当前这份 zsh 的
# 版本目录名（5.9.2），目录不存在时 zsh 自己会忽略这一项。
#
# ⚠️ **改不了"从外面设"这条路，只能在这儿设**（实测 + 源码）：zsh 的 MODULE_PATH
#    **不从环境导入** —— Src/params.c 那条声明写着
#    `IPDEF8("MODULE_PATH", …, PM_DONTIMPORT|PM_RESTRICTED|PM_TIED)`，
#    注释是 "MODULE_PATH is not imported for security reasons"（防止用环境变量注入
#    恶意 .so）。实测 `MODULE_PATH=… zsh -c 'print -l $module_path'` 打印的仍然是
#    编译进去的那个路径。所以：
#      · **交互式 shell**（读 rc → 读到本文件）：一切正常 ✅
#      · `zsh -c` / 脚本（**不读 rc**）：`zmodload` 一个**动态**模块会失败
#        （`fpath` 那条已经用 `export FPATH` 补上了，模块这条补不了）。
#        这是已知限制，见 README「已知限制」与 BACKLOG Z-9 —— 那里也记了
#        "为什么不干脆 `--disable-dynamic`"（实测：会**丢掉 19 个只能动态构建的模块**，
#        包括 `zsh/stat`、`zsh/system`、`zsh/zselect`、`zsh/files`…）。
if [ -n "${ZSH_VERSION:-}" ]; then
    fpath=("$WTOOL_HOME/usr/share/zsh/site-functions"
           "$WTOOL_HOME/usr/share/zsh/$ZSH_VERSION/functions" $fpath)
    module_path=("$WTOOL_HOME/usr/lib/zsh/$ZSH_VERSION" $module_path)
    # FPATH **可以**从环境导入（Src/params.c: `IPDEF8("FPATH", &fpath, "fpath", PM_TIED)`，
    # 没有 PM_DONTIMPORT）—— 实测 `FPATH=… zsh -c 'print -l $fpath[1]'` 认。
    # 所以导出去：**子进程 / 不读 rc 的 `zsh -c` 脚本**也能 autoload 到这套 functions，
    # 否则它们用的是编译进去的 `/root/.wtool/usr/share/zsh/…`（不存在的路径）。
    # MODULE_PATH 就没这个待遇（见上面那段），所以只导 fpath。
    export FPATH
fi
