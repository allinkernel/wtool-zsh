# shell/zsh —— 个人 shell 别名与函数集合

一组**和具体项目无关**的 shell 小工具：跳到 repo 工作区根、记路径再跳回来、WSL 的
`win` / `start`，以及 `gs` / `gl` / `s` / `kls` 这类短别名。

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

### 3. 函数（10 个）

#### `_up_to_have_dir <目录名>` —— 往上找目录

从 `$PWD` 开始一层层往上找含 `<目录名>` 的那层，找到就 **打印**那个目录并返回 0；
一路找到 `/` 还是没有就返回 1（不打印）。

- 用 `$PWD` 而不是 `pwd` 命令：当前路径被删掉时不会陷入死循环（代码注释原话）。
- **两份实现在最顶层那一格上不一致**（`env.bash` 会测 `/` 本身，`env.zsh` 走到 `/` 就直接
  返回 1）。判据（只依赖 `/usr` 存在）：

  ```sh
  R=~/self/wtool/shell/zsh
  bash -c "export WTOOL_PROJECT_DIR=/x; cd /var/log; . $R/env.bash; _up_to_have_dir usr; echo rc=\$?"
  #   /        rc=0
  zsh  -c "export WTOOL_PROJECT_DIR=/x; cd /var/log; . $R/env.zsh;  _up_to_have_dir usr; echo rc=\$?"
  #   （空）   rc=1
  ```

  实际用途（找 `.repo` / `.git`）碰不到这种情况；要不要把两边改齐由人拍，
  见 `BACKLOG.md`「待拍板」。
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

#### `this_is_wsl` / `this_is_not_wsl` / `win` / `start` —— WSL 相关

| 函数 | 行为 |
|---|---|
| `this_is_wsl` | `/usr/bin/wslpath` 存在 → 返回 0；否则返回 1 |
| `this_is_not_wsl` | 与 `this_is_wsl` 相反 |
| `win` | 只在 WSL 上有效：`wslpath -w .` 打出当前目录的 Windows 路径；非 WSL 返回 1 |
| `start <程序>` | 只在 WSL 上有效：用 `powershell.exe` 在**当前目录的 Windows 路径**下 `Start-Process <程序>`；非 WSL 打印 `only wsl support this` 并返回 1 |

```sh
start .            # 在 Windows 资源管理器里打开当前目录
start code         # 在 Windows 侧启动 VS Code
```

> 判断依据是 `/usr/bin/wslpath` 这个路径（代码里写死的），不是 `$WSL_DISTRO_NAME` 之类。
> 测试按**本机实际情况**断言（本机是 WSL）。

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

## 快捷键

本仓库**不定义任何快捷键 / key binding**（不设 `bindkey`、不设 `zle`）。

- zsh 侧的补全、历史搜索等快捷键来自 `shell/oh-my-zsh`（`priority=10`，先加载）；
- fzf 的 `Ctrl-T` / `Ctrl-R` / `Alt-C` 来自 `terminal/fzf`。

## 排错

| 现象 | 原因 / 怎么办 |
|---|---|
| `cw: 找不到 .repo（不在 repo 工作区内？）`（返回码 1） | 从 `$WTOOL_PROJECT_ROOT`（没设时 `$PWD`）一路往上都没有 `.repo`。确认自己在一个 wtool 工作区的子目录里；`echo $WTOOL_PROJECT_ROOT` 看它指哪 |
| `pdd` 跳到的不是我以为的目录 | 先 `pss` 看记着什么；`pdd` 读的就是 `/tmp/wsw-temp-pwd-id-$(id -u)`，同一用户其它终端敲过的 `pwd` 会把它覆盖 |
| `pdd` 报 `cd: ... No such file` | 记下的那个目录已经被删了；`pss` 确认，然后重新 `pwd` 记一次 |
| `start` 打印 `only wsl support this` 并返回 1 | 不在 WSL 上（没有 `/usr/bin/wslpath`）；这两个函数本来就是给 WSL 用的 |
| `win` 返回 1 但什么都不打印 | 同上；非 WSL 时 `win` 只是 `return 1` |
| 敲 `gs` 说 command not found | 这个 shell 的 rc 里没有 wtool 块 —— 项目没装，或者装完没重开 shell（`exec $SHELL`） |

## 测试

```sh
bash tests/env_test.sh     # 两个 shell 各 10 条、共 20 条（条数以输出为准）
                           # 没装 zsh 就只测 bash（会打印跳过）
```

它把**同一张用例表**喂给两个 shell：别名在不在、`_up_to_have_dir` / `cw` 能不能找到
`.repo`、`pdd`/`pss` 能不能跳回来、WSL 探测函数在**当前这台机器**上给不给对的返回码
（本机是 WSL 就按 WSL 断言，不写死）。

> 用例表是共用的，**每加一条两个 shell 都会跑**；所以清单里的"20 条"是
> `10 × 2`，数字会随用例增删变化 —— 以脚本最后打印的那一行为准。

## 文件

| 文件 | 作用 |
|---|---|
| `wtool.xml` | 清单：1 个 `<zshrc>` + 1 个 `<bashrc>`，无 link |
| `env.zsh` | zsh 版：别名 + 函数（见上） |
| `env.bash` | bash 版：与 `env.zsh` 等价（唯一已知例外：`_up_to_have_dir` 的最顶层那一格，见上） |
| `tests/env_test.sh` | 行为测试：同一张用例表跑两个 shell（条数以输出为准） |
| `BACKLOG.md` | 这个项目"接下来做什么、哪条待拍板" |

> 历史：这里原来只有 `env.zsh`，配置是从 `mytool` 的 `source_all_env.sh` 链上来的；
> 现在由 wtool 的块加载，不再需要那个链条。
