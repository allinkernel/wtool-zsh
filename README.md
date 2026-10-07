# shell/zsh —— 个人 shell 别名与函数集合

一组**和具体项目无关**的 shell 小工具：跳到 repo 工作区根、记路径再跳回来、WSL 的
`win` / `start`、当前目录树下找 `Android.mk` / `Android.bp` 目标名的 `wrg`
（优先用 `rg` / `fd`，都没有才回退 `find`，命中的那段标红加粗），
以及 `gs` / `gl` / `s` / `kls` 这类短别名。

- 项目路径（**路径就是它的身份**，没有单独的 `id`，见 ADR-0037）：`shell/zsh`
  —— 名字是历史遗留，里面**已经不是纯 zsh 了**
- 加载优先级：`priority=20`（在 `shell/oh-my-zsh`(10) 之后加载）
- 本仓库**没有 `scripts/`**（不需要构建/安装脚本）：装到 `$HOME` 里的只有
  `env.zsh` / `env.bash` 两个文件的 rc 块，外加一个测试

---

## 功能说明

### 1. 装的是哪两份文件、被谁加载

| 文件 | 给谁 | 被谁 source |
|---|---|---|
| `env.zsh` | zsh | `~/.zshrc` 里的 wtool 块 |
| `env.bash` | bash | `~/.bashrc` 里的 wtool 块 |

两份**内容等价**（同一批别名/函数、同样的报错、同样的退出码），区别只有语法：
zsh 版用 `${var:h}` 取父目录，bash 版用 `${var%/*}` + `case`。

> 受众里有人机器上**没有 zsh**（公司机器很常见），bash 版是必需品。
> **改一个就要在另一个里做等价修改**，`tests/env_test.sh` 会用同一张用例表把两个 shell 都跑一遍。

`wtool.xml` 里就是这么声明的（没有 `<link>`，全部靠注入 env 块提供；也**没有 `id=` 属性** ——
项目身份就是相对工作区的路径 `shell/zsh`，写了 `id=` 反而会被引擎硬报错，见 ADR-0037）：

```xml
<wtool schema="1" priority="20">
  <zshrc  src="env.zsh"/>
  <bashrc src="env.bash"/>
</wtool>
```

### 2. 别名（10 个，两份文件完全一样）

| 别名 | 展开成 | 说明 |
|---|---|---|
| `gs` | `git status` | |
| `gss` | `git status --short` | |
| `gd` | `git diff` | |
| `gds` | `git diff --staged` | |
| `gll` | `git log` | |
| `gl` | `git log` | `gll` 的同义词 |
| `s` | `ls` | |
| `sl` | `ls` | `s` 的同义词 |
| `lks` | `ls` | 代码里那句"这些都是简单的命令，根本不需要写个函数去实现"就是给这几个的 |
| `kls` | `ls` | |

> `s` / `sl` / `lks` / `kls` 四个名字指向同一个 `ls` —— 历史习惯，**本仓库不定义 `ls` 本身**。

### 3. 函数（公开 11 个 + 内部 4 个）

#### `_up_to_have_dir <目录名>` —— 往上找目录

从 `$PWD` 开始一层层往上找含 `<目录名>` 的那层，找到就 **打印**那个目录并返回 0；
一路找到 `/` 还是没有就返回 1（不打印）。

- 用 `$PWD` 而不是 `pwd` 命令：当前路径被删掉时不会陷入死循环（代码注释原话）。
- **`/` 那一格也要测**：往上走到 `/` 时先判"已经在 `/` 了"再往上走，所以挂在根下的
  目标找得到。判据（只依赖 `/etc` 存在）：

  ```sh
  R=~/self/wtool/shell/zsh
  bash -c "export WTOOL_PROJECT_DIR=/x; cd /var/log; . $R/env.bash; _up_to_have_dir usr; echo rc=\$?"
  zsh  -c "export WTOOL_PROJECT_DIR=/x; cd /var/log; . $R/env.zsh;  _up_to_have_dir usr; echo rc=\$?"
  #   两份都打印 / 、rc=0
  ```

  > 原来 `env.zsh` 是先 `${cur_dir:h}` 再判 `== /` 就直接 `return 1`，根下那一格永远
  > 测不到（`env.bash` 会测），两份因此不等价 —— 2026-10-04 改齐，`tests/env_test.sh`
  > 加了"最顶层那一格"一条用例；修复经过见 `BACKLOG.md`。
- 它是 `cw` 的基础；`tools/git-repo-sh-tools` 里另有一份自己的同名副本
  （`env.zsh` / `env.bash` 各一份）。

#### `cw` —— 跳到 repo 工作区根

```sh
cw          # cd 到最近的含 .repo 的目录（wtool 集合的根）
```

- 起点是 `$WTOOL_PROJECT_ROOT`（wtool 块导出的"本项目真实路径"），**没设才退回 `$PWD`**；
- 从起点一层层往上找 `.repo`，找到就 `cd` 过去；
- 找不到就打 `cw: 找不到 .repo（不在 repo 工作区内？）` 到 stderr 并返回 1。

#### `gba` —— 列所有分支（能上色就上色）

```sh
gba         # git branch -a，有 batcat 就 | batcat，否则 | cat
```

定义前先 `unset`/`unalias` 掉同名命令，避免和别处定义的 `gba` 打架。

#### `pwd` / `pdd` / `pss` —— 记路径、跳回来

这一组是**覆盖了 `pwd` 这个命令**换来的：

| 函数 | 做什么 |
|---|---|
| `pwd` | 跑 `/usr/bin/pwd`，同时把结果**写进** `/tmp/wsw-temp-pwd-id-$(id -u)`（用 `tee`，所以终端照样显示路径） |
| `pss` | 打印那个文件里记着的路径（"上次我在哪"） |
| `pdd` | `cd` 回那个文件里记着的路径（读出来时 `tr -d ' '` 去掉空白） |

典型用法：在很深的目录里敲一次 `pwd`，跳到别处干活，再 `pdd` 跳回来；
不确定记的是哪就 `pss` 看一眼。

> 记路径的文件名只带 **uid**，不带终端号（`/tmp/wsw-temp-pwd-id-$(id -u)`）——
> 同一用户的多个终端共用这一个文件，后敲的 `pwd` 会覆盖先敲的。
> 这是读代码就能确定的行为。

#### `this_is_wsl` / `this_is_not_wsl` —— WSL 探测

| 函数 | 行为 |
|---|---|
| `this_is_wsl` | `/usr/bin/wslpath` 存在 → 返回 0；否则返回 1 |
| `this_is_not_wsl` | 与 `this_is_wsl` 相反 |

> 判断依据是 `/usr/bin/wslpath` 这个路径（代码里写死的），不是 `$WSL_DISTRO_NAME` 之类。
> 测试按**本机实际情况**断言（在 WSL 上就按 WSL 断言，不写死）。

#### `win` —— 把当前目录翻译成"别的机器也能用"的路径

```sh
win        # 打路径，一行或两行
```

**WSL 上（有 `wslpath`）**：就是 `wslpath -w .`，打一行 Windows 路径。非 WSL 上
`win` 以前是 `return 1`，现在走服务器分支：

| 行 | 内容 | 怎么算出来的 |
|---|---|---|
| 1 | `//<ip>/<share><相对路径>` | 读 `/etc/samba/smb.conf` 的 `[share]` + `path = …`，取**最长前缀匹配**目标目录的那个 share（按路径分隔符对齐：share `path=/srv/share` 不会被 `/srv/share2` 命中），拼上目标目录相对 share 的那段 |
| 2 | `<whoami>@<ip>:<绝对路径>` | 目标目录的绝对路径（`realpath -m` 规范化过），可以直接拿去 `scp` |

- `<ip>`：优先环境变量 `WIN_IP`；没设就从 `ip -4 addr` 里取**第一个非 `lo`** 的地址。
- smb.conf 的路径可以用 `WTOOL_SMB_CONF` 覆盖（默认 `/etc/samba/smb.conf`）；
  段名后的 `path =` 认大小写、去首尾空白、去首尾引号，`#` / `;` 开头的行跳过。
- **算不出来不静默**：
  - 取不到 IP（`WIN_IP` 没设且 `ip addr` 里没有）→ stderr 打
    `win: 拿不到本机 IP（WIN_IP 没设，ip addr 里也没有）。` + `请在 .bashrc/.zshrc 里设 WIN_IP=<本机对外的地址>`，
    **只返回 1，不打印任何一行**；
  - 读不到 smb.conf → stderr 打 `win: 读不到 samba 配置 <路径>`；
  - 文件在但没有 share 匹配 → stderr 打 `win: <路径> 里没有 share 的 path 匹配 <目标>`；
  - 后两种情况**仍然打印 scp 那一行**（它不依赖 samba），退出码是 **1**。

```sh
WIN_IP=192.168.0.10 win
# //192.168.0.10/proj/sub
# mindul@192.168.0.10:/srv/proj/sub
```

> 判据（不需要真 samba、也不改系统文件）：

```sh
T=$(mktemp -d); mkdir -p "$T/src/proj/sub"; printf '[proj]\n  path = %s/src/proj\n' "$T" > "$T/smb.conf"
(cd "$T/src/proj/sub" && source ~/self/wtool/shell/zsh/env.zsh
 this_is_wsl () { return 1; }            # 把「非 WSL」这条分支压出来
 WIN_IP=10.1.2.3 WTOOL_SMB_CONF=$T/smb.conf win)
# //10.1.2.3/proj/sub
# <你>@10.1.2.3:<$T>/src/proj/sub
```

#### `start <程序>` —— 在 Windows 侧打开（只 WSL 有效）

用 `powershell.exe` 在**当前目录的 Windows 路径**下 `Start-Process <程序>`；
非 WSL 打印 `only wsl support this` 并返回 1。

```sh
start .            # 在 Windows 资源管理器里打开当前目录
start code         # 在 Windows 侧启动 VS Code
```

**路径补全**：`start <TAB>` 补当前目录的文件/目录名（以前只能先 `ls <TAB>` 再把
`ls` 改成 `start`）：

- bash：`complete -o default -o filenames start`；
- zsh：装了 `shell/oh-my-zsh`（`priority=10`）时 compinit 已经跑过，用
  `compdef _files start`；**只装本项目**（没有 compinit）时退回 `compctl -f start`。
  两条路都是补文件/目录名。

#### `wrg <名字>` / `wrg -i <片段>` —— 找 Android 构建目标名

在**当前目录树下**递归找 `Android.mk` / `Android.bp` 里的目标名，输出
`文件:行号:命中行`（按文件名、行号排序，可以直接喂给 `grep` / 编辑器跳转）：

| 文件 | 认的写法 |
|---|---|
| `Android.mk` | `LOCAL_MODULE := xxx` / `LOCAL_PACKAGE_NAME := xxx`（`:=` 或 `=`，行首可以有空白） |
| `Android.bp` | `name: "xxx"` |

| 用法 | 匹配方式 |
|---|---|
| `wrg libfoo` | **精确**：目标名和 `libfoo` 完全相同（区分大小写） |
| `wrg -i lib` | **模糊**：目标名里含 `lib`（子串、忽略大小写） |

**搜索后端**（按顺序探测，前一个没有才用下一个）：

| 顺序 | 后端 | 说明 |
|---|---|---|
| 1 | `rg`（ripgrep） | 最快；`Android.mk` / `Android.bp` 两种写法各搜一次再合并 |
| 2 | `fd`（`fdfind` → `fd-find` → `fd`，探到哪个用哪个） | `fd` 列文件、`awk` 判命中 |
| 3 | `find` | 兜底：没有 rg / fd 时就是它，行为与本项目以前的版本**逐字一致** |

- `WRG_SEARCH=auto`（默认）/ `rg` / `fd` / `find`：**指定了就一定用它** ——
  那个可执行文件不在 `PATH` 里就报错、返回 **2**，不会偷偷换成别的；
- ⚠️ **`rg` / `fd` 会跳过隐藏目录和被 ignore 的目录**（`.repo/`、`out/` 这类），`find` 不会 ——
  所以前两条快得多，但那两个目录里的目标搜不到；
  要"连 `.repo/` 一起搜"（找回 `find` 的老行为）就用 `WRG_SEARCH=find`。

**高亮**：命中的**那一段**（精确 = 整个目标名；模糊 = 名字里命中的子串）在终端里是
**加粗红**；管道 / 重定向里不含任何颜色码。

- `WRG_COLOR=auto`（默认：只在 stdout 是终端时上色）/ `always` / `never`；
- `NO_COLOR` **非空**时一律不上色（优先级最高，压过 `WRG_COLOR=always`）；
- `WRG_COLOR` 写错了 → 报错、返回 2。

- `-h` / `--help`：打用法并返回 0；
- 参数不对/选项不认识：用法打到 stderr，返回 **2**；
- 当前目录树下没有 `Android.mk` / `Android.bp`：stderr 打
  `wrg: 当前目录树下没有 Android.mk / Android.bp`，返回 1；
- 有这两种文件但没有命中：stderr 打 `wrg: 没有匹配 '<模式>' 的目标名`，返回 1。

```sh
wrg libfoo           # ./foo/Android.mk:3:LOCAL_MODULE := libfoo    ← libfoo 标红加粗
wrg -i app           # ./bar/Android.bp:7:    name: "BarApp",       ← App 标红加粗
                     # ./foo/Android.mk:8:LOCAL_PACKAGE_NAME := FooApp
```

> 注释里的目标名（`# LOCAL_MODULE := xxx`）不算；精确匹配不认前缀
> （`wrg lib` 不会命中 `libfoo`）；目标名里的 `.` `+` 这类符号按**字面量**算
> （`wrg 'liba+b'` 不会命中 `libaaab`）。

---

## 安装（由 wtool 统一管）

安装这件事不由本仓库负责：**统一走 wtool** ——
见 [wtool 的 README（GitHub：allinkernel/wtool）](https://github.com/allinkernel/wtool/blob/main/README.md)。
本仓库只是源码/配置；装完之后 `~/.zshrc` / `~/.bashrc` 里会出现 wtool 写的块，
块会 source 本项目的 `env.zsh` / `env.bash`，并在此之前导出
`WTOOL_PROJECT_ID` / `WTOOL_PROJECT_DIR` / `WTOOL_PROJECT_ROOT`。

> ⚠️ **wtool 的项目只在容器里装 / 测**（用户级规矩，2026-10-04）：本机（WSL）
> 是临时的手工环境，wtool 彻底调通之前**不在本地落地**。要在容器里验证就用
> `--network=host` 挂工作区；**真机上装本项目必须由用户明确同意**，
> 助手不得自行 `wtool install`。

## 配置项

本仓库**不读任何配置文件**，全部行为由这几个环境变量决定：

| 变量 | 本仓库做什么 | 说明 |
|---|---|---|
| `WTOOL_PROJECT_DIR` | 没设时给默认值 `$HOME/.wtool/wtool-work-dir/links/shell/zsh` | 单独 source 本项目时也能用；正常由 wtool 块导出 |
| `WTOOL_PROJECT_ROOT` | `cw` 拿它当向上查找的起点 | 由 wtool 块导出（`readlink -f` 解析过中转链接的真实路径）；不设则 `cw` 用 `$PWD` |
| `PATH` | 前面插一个 `~/bin` | `export PATH=~/bin:$PATH` |
| `LD_LIBRARY_PATH` | **直接赋值**成 `~/usr/lib64` | 注意是覆盖不是追加：上层传进来的值会被顶掉 |
| `TERM` | **直接赋值**成 `xterm-256color` | 代码注释：不设成 256 色，vim 等主题显示会受影响 |
| `WIN_IP` | 非 WSL 上 `win` 的地址来源 | 设了就用它；没设才去 `ip -4 addr` 里找。取不到就报错让你去 `.bashrc` / `.zshrc` 里设它 |
| `WTOOL_SMB_CONF` | 非 WSL 上 `win` 读哪个 samba 配置 | 默认 `/etc/samba/smb.conf`；测试用它注入假配置，不碰系统文件 |
| `WRG_SEARCH` | `wrg` 用哪个搜索后端 | `auto`（默认：按 rg → fdfind/fd-find/fd → find 探测）/ `rg` / `fd` / `find`。指定了就必须存在，否则报错返回 2 |
| `WRG_COLOR` | `wrg` 高亮开关 | `auto`（默认：只有 stdout 是终端才上色）/ `always` / `never`。写错返回 2 |
| `NO_COLOR` | 通用约定，非空就关色 | 优先级最高：设了它，`WRG_COLOR=always` 也压不过 |
| `WRG_PAT` / `WRG_FUZZY` / `WRG_PASS` | `wrg` 内部传给 awk 的模式、模式开关、pass 名 | 不是给人设的，别在 rc 里写 |

## 快捷键

本仓库**不定义任何快捷键 / key binding**（不设 `bindkey`、不设 `zle`）。

- 唯一和补全有关的是 `start`：bash 用 `complete -o default -o filenames start`，
  zsh 用 `compdef _files start`（没有 compinit 时 `compctl -f start`）—— 都是"补文件名"，
  不是新的按键；
- zsh 侧的补全、历史搜索等快捷键来自 `shell/oh-my-zsh`（`priority=10`，先加载）；
- fzf 的 `Ctrl-T` / `Ctrl-R` / `Alt-C` 来自 `terminal/fzf`。

## 排错

| 现象 | 原因 / 怎么办 |
|---|---|
| `cw: 找不到 .repo（不在 repo 工作区内？）`（返回码 1） | 从 `$WTOOL_PROJECT_ROOT`（没设时 `$PWD`）一路往上都没有 `.repo`。确认自己在一个 wtool 工作区的子目录里；`echo $WTOOL_PROJECT_ROOT` 看它指哪 |
| `pdd` 跳到的不是我以为的目录 | 先 `pss` 看记着什么；`pdd` 读的就是 `/tmp/wsw-temp-pwd-id-$(id -u)`，同一用户其它终端敲过的 `pwd` 会把它覆盖 |
| `pdd` 报 `cd: ... No such file` | 记下的那个目录已经被删了；`pss` 确认，然后重新 `pwd` 记一次 |
| `start` 打印 `only wsl support this` 并返回 1 | 不在 WSL 上（没有 `/usr/bin/wslpath`）；`start` 本来就是给 WSL 用的 |
| `start <TAB>` 不补路径 | 看 shell 里有没有注册：bash `complete -p start`、zsh `print ${_comps[start]}`（应打 `_files`）/ `compctl -L start`（应打 `compctl -f start`）；都没有就是项目没装或没重开 shell |
| `win: 拿不到本机 IP（WIN_IP 没设，ip addr 里也没有）。` | 非 WSL 上取不到地址。按提示在 `.bashrc` / `.zshrc` 里 `export WIN_IP=<本机对外的地址>` |
| `win: 读不到 samba 配置 /etc/samba/smb.conf` | 这台机器没装/没配 samba。要么装上并配 `[share]` + `path =`，要么临时 `WTOOL_SMB_CONF=<别的文件>`；scp 那一行照样会给 |
| `win: /etc/samba/smb.conf 里没有 share 的 path 匹配 <目标>` | 当前目录不在任何 share 的 `path` 下面（或 share 的 path 写的是软链/相对路径）。`testparm` 看一眼 samba 实际认的 path；scp 那一行照样会给 |
| `win` 在非 WSL 上只打了 scp 一行、返回 1 | 这就是"samba 那半没算出来"，看上面两条的 stderr；scp 行是可以直接用的 |
| `wrg: 当前目录树下没有 Android.mk / Android.bp`（返回码 1） | 站错目录了（`wrg` 只看当前目录往下）；`cd` 到源码树根部再跑。用 rg / fd 时它们跳过的目录（`.repo/`、`out/`）里即使有也不算 |
| `wrg: 没有匹配 'xxx' 的目标名`（返回码 1） | 精确模式要求名字完全一样（区分大小写）；想按片段找就 `wrg -i 片段` |
| `wrg` 搜不到 `.repo/` 或 `out/` 里的目标 | 默认后端是 rg / fd，它们跳过隐藏目录与被 ignore 的目录。要连这些一起搜：`WRG_SEARCH=find wrg 名字` |
| `wrg: WRG_SEARCH=rg 但 PATH 里没有 rg`（返回码 2） | 强制指定了 `rg` 却装没装/不在 PATH 里。装 ripgrep，或者 `WRG_SEARCH=auto` 让它自己挑 |
| `wrg: WRG_SEARCH=fd 但 PATH 里没有 fdfind / fd-find / fd`（返回码 2） | 同上：装 `fd-find`（Ubuntu 里可执行名是 `fdfind`），或改回 `auto` |
| `wrg: WRG_SEARCH 只认 auto / rg / fd / find（现在是 xxx）`（返回码 2） | 变量值拼错了（打错不会静默退回默认） |
| `wrg: WRG_COLOR 只认 auto / always / never（现在是 xxx）`（返回码 2） | 同上 |
| `wrg` 在管道 / 重定向里没有颜色 | 这是有意的：`WRG_COLOR=auto` 只在终端上色。要强制就 `WRG_COLOR=always` |
| `wrg` 在终端里也没有颜色 | 看 `echo $NO_COLOR` —— 非空就一律不上色（它优先级最高） |
| 敲 `gs` 说 command not found | 这个 shell 的 rc 里没有 wtool 块 —— 项目没装，或者装完没重开 shell（`exec $SHELL`） |

## 测试

```sh
bash tests/env_test.sh     # rg + fd 都装了：129 条；只有 rg：121；只有 fd：115；
                           # 两个都没有（纯 find 兜底）：105 —— 以输出为准
                           # 没装 zsh 就只测 bash（会打印跳过）
```

它把**同一张用例表**喂给两个 shell：别名在不在、`_up_to_have_dir` / `cw` 能不能找到
`.repo`、`pdd`/`pss` 能不能跳回来、`start` 的补全注册、`win` 的 WSL 分支**逐字等于**
`wslpath -w .`、`win` 的服务器分支（用假 `smb.conf` + `WIN_IP` 注入，最长前缀/路径边界/
三种报错各一条）、以及 WSL 探测函数在**当前这台机器**上给不给对的返回码
（本机是 WSL 就按 WSL 断言，不写死）。

`wrg` 那一段是重点：老行为（精确/模糊/注释/空目录/用法）之外，还比
**三条后端在同一个夹具上的输出逐字一致**（`WRG_SEARCH=auto|fd|rg` vs `find`，`cmp` 比对，
模糊 + 精确两种模式）、元字符当字面量（`liba+b` 不命中 `libaaab`）、每条后端的
"没有命中 / 树下没有这两种文件"、后端探测顺序（用只有一个可执行名的假 `PATH`）、
强制指定但可执行不存在（rc=2）、高亮（管道里 `grep -c ESC` = 0、`WRG_COLOR=always` 的
精确字节、`NO_COLOR` 压过 `always`、pty 下自动上色）、以及"隐藏目录里 rg/fd 搜不到、
find 搜得到"这条语义差异。

> 用例表是共用的，**每加一条两个 shell 都会跑**；后端相关的用例按"本机有没有那个
> 可执行文件"跳过，所以数字会随环境变 —— 以脚本最后打印的那一行为准
> （改造前是 67 条）。

## 文件

| 文件 | 作用 |
|---|---|
| `wtool.xml` | 清单：1 个 `<zshrc>` + 1 个 `<bashrc>`，无 link |
| `env.zsh` | zsh 版：别名 + 函数（见上） |
| `env.bash` | bash 版：与 `env.zsh` 等价（同一张用例表跑两个 shell） |
| `tests/env_test.sh` | 行为测试：同一张用例表跑两个 shell（条数以输出为准） |
| `architecture.md` | 代码现在长什么样（现状，只写现状） |
| `BACKLOG.md` | 这个项目"接下来做什么、哪条待拍板" |

> 历史：这里原来只有 `env.zsh`，配置是从 `mytool` 的 `source_all_env.sh` 链上来的；
> 现在由 wtool 的块加载，不再需要那个链条。
