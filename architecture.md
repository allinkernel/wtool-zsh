# architecture —— shell/zsh（现状）

> 这份文件只写**代码现在长什么样**：有哪些文件、里面有什么、怎么装、怎么测。
> 为什么这么决策去 `docs/adr/`（本仓库没有 ADR），接下来做什么去 `BACKLOG.md`。

## 1. 这个项目是什么

一组和具体项目无关的 shell 别名 / 函数。项目身份 = 工作区里的路径 `shell/zsh`
（`wtool.xml` 里**没有** `id=`），加载优先级 `priority=20`。

**仓库里只有文本**：两个 rc 片段、一个测试、清单和文档，没有 `scripts/`，
没有构建产物（`ls`：`wtool.xml` `env.zsh` `env.bash` `tests/env_test.sh`
`README.md` `AGENTS.md` `architecture.md` `BACKLOG.md`）。

## 2. 装到哪、怎么被加载

`wtool.xml`：

```xml
<wtool schema="1" priority="20">
  <zshrc  src="env.zsh"/>
  <bashrc src="env.bash"/>
</wtool>
```

- 引擎在 `~/.zshrc` / `~/.bashrc` 里写 `# >>> wtool:shell/zsh` 块，块里 source
  `$HOME/.wtool/wtool-work-dir/links/shell/zsh/env.zsh`（bash 块对应 `env.bash`）；
- 块在 source 之前导出 `WTOOL_PROJECT_ID` / `WTOOL_PROJECT_DIR` / `WTOOL_PROJECT_ROOT`；
- 没有任何 `<link>`：`$HOME` 里不留本项目自己的软链。

## 3. 两个 shell 的等价约定

`env.zsh`（zsh）与 `env.bash`（bash）是**同一批别名 + 同一批函数**：同样的报错文字、
同样的退出码、同样的输出。差别只在语法：

| 地方 | env.zsh | env.bash |
|---|---|---|
| 测条件 | `[[ ... ]]` | `[ ... ]` |
| 取父目录（`_up_to_have_dir` / `cw`） | `${var:h}` | `${var%/*}` + `case` |
| 反向引用（本文件里没有用到） | `${match[1]}` | `BASH_REMATCH[1]` |
| `start` 补全 | `compdef _files start` / `compctl -f start` | `complete -o default -o filenames start` |

`tests/env_test.sh` 用**同一张用例表**跑两个 shell；已知的不等价点：**没有**。

## 4. env 文件里有什么

### 4.1 顶部固定动作（两份一样）

- `WTOOL_PROJECT_DIR` 没设时给默认值 `$HOME/.wtool/wtool-work-dir/links/shell/zsh`；
- `export PATH=~/bin:$PATH`；`export LD_LIBRARY_PATH=~/usr/lib64`（覆盖式）；
- `export TERM=xterm-256color`。

### 4.2 别名（10 个）

`gs` `gss` `gd` `gds` `gll` `gl` → `git status` / `--short` / `diff` / `diff --staged` /
`log` / `log`；`s` `sl` `lks` `kls` → `ls`。

### 4.3 函数

| 函数 | 做什么 | 退出码 |
|---|---|---|
| `_up_to_have_dir <名>` | 从 `$PWD` 往上找含 `<名>` 的目录，打印它 | 0 找到 / 1 到 `/` 也没有 |
| `cw` | 从 `$WTOOL_PROJECT_ROOT`（没设用 `$PWD`）往上找 `.repo` 并 `cd` | 0 / 1（打 `cw: 找不到 .repo（不在 repo 工作区内？）`） |
| `gba` | `git branch -a`，有 `batcat` 就过一遍 | 无显式 return |
| `pwd` | 覆盖 `pwd`：跑 `/usr/bin/pwd` 并用 `tee` 记进 `/tmp/wsw-temp-pwd-id-$(id -u)` | 同 `/usr/bin/pwd` |
| `pss` | 打印上面那个文件 | 同 `cat` |
| `pdd` | `cd` 回上面那个文件记的目录（`tr -d ' '`） | 同 `cd` |
| `this_is_wsl` | `[[ -e /usr/bin/wslpath ]]` | 0/1 |
| `this_is_not_wsl` | 与 `this_is_wsl` 相反 | 0/1 |
| `win` | WSL：`wslpath -w .`；非 WSL：走 `_win_server`（见 4.4） | 0 / 1 |
| `start <程序>` | 非 WSL 打 `only wsl support this` 返回 1；WSL 上 `powershell.exe -Command "Set-Location -Path \"$(win)\"; Start-Process $1"` | 0 / 1 |
| `wrg <名字>` / `wrg -i <片段>` | 见 4.5 | 0 / 1 / 2 |

内部辅助（不打算给人直接敲）：`_win_ip`、`_win_smb_shares`、`_win_server`、`_wrg_usage`。

### 4.4 `win` 的服务器分支

`win` 先看 `this_is_wsl`：

- 是 WSL → `wslpath -w . || return 1`，行为与加服务器分支之前逐字一致；
- 不是 WSL → `_win_server`：
  1. `target` = `realpath -m -- "$PWD"`（失败退回 `$PWD`）；
  2. `ip` = `_win_ip`：`$WIN_IP` 优先，否则 `ip -4 addr` 里第一个非 `lo` 的 `inet` 地址
     （`ip` 不在就返回 1）。取不到 → stderr 两行提示设 `WIN_IP`，返回 1，**不打印任何一行**；
  3. `conf` = `${WTOOL_SMB_CONF:-/etc/samba/smb.conf}`；
  4. `_win_smb_shares` 用 awk 把 `[share]` 段与段内 `path =` 抽成 `share|path`
     （跳过 `#` / `;` 行，去首尾空白与首尾引号）；
  5. 每个 share 的 path 过 `realpath -m`，与 `target` 做**按路径分隔符对齐**的前缀比较
     （`case "$target" in "$spath")` / `"$spath"/*)`），命中就记相对路径，
     **最长前缀胜出**；
  6. stdout：命中 → `//<ip>/<share><相对路径>`；读不到文件 → stderr
     `win: 读不到 samba 配置 <conf>`；没有命中 → stderr
     `win: <conf> 里没有 share 的 path 匹配 <target>`；后两种 `rc=1`；
  7. 最后 stdout 一定多一行 `<whoami>@<ip>:<target>`，`return $rc`。

### 4.5 `wrg`

`wrg` 只认两种文件：`Android.mk`、`Android.bp`。`-i` 切到模糊模式（子串、忽略大小写），
否则精确（`==`）。三种搜索后端，**按顺序探测**，前一个没有才用下一个：

| 顺序 | 后端 | 怎么找到它 | 怎么搜 |
|---|---|---|---|
| 1 | rg | `command -v rg` | 两种文件的写法不一样 → 跑两次 `rg --no-heading --line-number --with-filename --color=never -g <文件名> -e <正则> .`，输出合并 |
| 2 | fd | `command -v fdfind` → `fd-find` → `fd`（第一个有的） | `<fd> -t f -g "${_WRG_FD_GLOB}" -X awk "${_WRG_AWK}"`（`-X` = 批量 exec，等价于 `find … {} +`） |
| 3 | find | 兜底，不用探 | `find . -type f \( -name Android.mk -o -name Android.bp \) -exec awk "${_WRG_AWK}" {} +` |

- 后端选择：`WRG_SEARCH=auto`（默认，按上表探测）/ `rg` / `fd` / `find`。
  **指定了就一定用它**：`rg` / `fd` 找不到可执行文件 → stderr 报错、返回 **2**；
  取值不认 → 同样 2。`WRG_SEARCH` 只在 `wrg` 里读，不影响别的命令。
- 判命中、抠目标名、着色都在**同一段 awk**（`_WRG_AWK`，两处 `wrg` 的实现里各存一份、逐字相同）里，
  三条后端共用，输出因此逐字一致：
  - `WRG_PASS=search`：读文件，`Android.mk` 行匹配
    `^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*[^[:space:]#]+`、
    `Android.bp` 行匹配 `^[[:space:]]*name[[:space:]]*:[[:space:]]*"[^"]*"`，
    取等号后 / 引号里那段当目标名；命中（精确 `v == pat`，模糊 `index(tolower(v), tolower(pat)) > 0`）
    就 `print 路径 ":" FNR ":" $0`；
  - `WRG_PASS=paint`：读 stdin 上的 `路径:行号:原文`，把命中的那一段包上颜色（见下）；
  - 路径归一化：`norm()` 给"既不是 `/` 开头、也不是 `./` 开头"的路径补 `./`
    （fd 直接打印时没有 `./`，加了 `-X` 才有；find 一直有 —— 归一化保证两条路形状一样）。
- **rg 那条路**：rg 一个正则只能搜一种写法，所以两种文件各搜一次再合并；值先做正则转义
  （`_wrg_re_escape`：把 `\ ^ $ . * + ? ( ) [ ] { } |` 变字面量），精确模式值后面必须跟
  `([[:space:]#]|$)`、模糊模式只给值套 `(?i:...)`（关键词部分保持大小写敏感）。
  rg 的退出码：**1 = 没命中**（不是错误），> 1 才是错。
- **fd 那条路**：fd 的 `-g` 是**开关**（不带参数），所以两个文件名合成**一个** glob
  `Android.{mk,bp}`（`_WRG_FD_GLOB`）；fd 没命中时的退出码各版本不一样
  （9.0.0 给 0，有的给 1），实现里"空输出 + 1"当没命中。
- **语义差异**（rg / fd 与 find 的）：rg / fd 默认**跳过隐藏目录和被 ignore 的目录**
  （`.repo/`、`out/` 这类），find 不跳 —— 所以整树更快，但那些目录里的目标搜不到。
  要连它们一起搜就用 `WRG_SEARCH=find`。
- 先看树里有没有这两种文件（rg：`rg --files -g Android.mk -g Android.bp .`；
  fd：`<fd> -t f -g "${_WRG_FD_GLOB}" | head -n 1`；find：`-print -quit`）：
  空 → stderr `wrg: 当前目录树下没有 Android.mk / Android.bp`，返回 1；
- 结果先 `sort -t: -k1,1 -k2,2n`（**纯文本**，ANSI 不参与排序键），
  要上色时再过一个 `WRG_PASS=paint` 的 awk；
- 输出非空就打印、返回 0；空 → stderr `wrg: 没有匹配 '<模式>' 的目标名`，返回 1；
  后端非 0 → stderr `wrg: 搜索失败（<后端>/awk 退出码 <n>）`，返回 1
  （find 那条路是 `find/awk`，与改动前逐字一样；rg 那条路是 `rg`）；
- 用法错误（选项不认、参数不是 1 个）→ 用法打 stderr，返回 2；`-h` / `--help` → 打 stdout，返回 0。

#### 4.5.1 `wrg` 的高亮

命中的**那一段**（不是整行）用 `\033[1;31m` … `\033[0m` 包住：精确 = 整个目标名；
模糊 = 目标名里命中的那个子串（`index()` 定位 + `length(pat)` 定长）。

| 变量 | 作用 |
|---|---|
| `WRG_COLOR=auto`（默认） | 只有 stdout 是终端（`[ -t 1 ]`）才上色；管道 / 重定向是纯文本 |
| `WRG_COLOR=always` / `never` | 强开 / 强关 |
| `NO_COLOR` | **非空就永不上色** —— 优先级最高，压过 `WRG_COLOR=always` |
| `WRG_COLOR` 取值不认 | stderr 报错，返回 2（和 `WRG_SEARCH` 一样，拼错不静默） |

内部变量（不是给人设的）：`WRG_PAT` / `WRG_FUZZY` / `WRG_PASS`（传给 awk 的模式、模式开关、
pass 名）、`_WRG_AWK`（那段 awk 的正文）、`_WRG_FD_GLOB`（fd 的 glob）。

### 4.6 `start` 的补全

文件末尾按 shell 注册（不是按键绑定）：

- `env.zsh`：`(( $+functions[compdef] ))` 为真 → `compdef _files start`；
  否则 `compctl -f start`；
- `env.bash`：`complete -o default -o filenames start`。

## 5. 测试

`tests/env_test.sh`（bash 脚本，`set -u`）：

- 自己 `mktemp -d` 造夹具：假 repo 工作区（`$T/ws/.repo`、`$T/ws/a/b`、`$T/ws/ab`）、
  wrg 用的 `$T/src/{foo,bar}/Android.mk|Android.bp`、`$T/empty`、
  win 用的假 `$T/smb.conf` / `$T/smb-nomatch.conf`；**不碰真 `$HOME`、不碰 `/etc/samba`**；
- wrg 三后端的夹具单独一棵树 `$T/src2`（`keep/Android.mk` 里放着 `liba+b` / `libaaab` 这种
  正则元字符陷阱、`keep/Android.bp`、以及只有 find 看得到的 `.hidden/Android.bp`），
  外加一组"只有一个可执行名的假 PATH"`$T/bin-{rg,fdfind,fd-find,fd,none}`（用来逼出探测顺序）；
  PATH 里有真 `rg` 时还往 `$T/bin-rg/rg` 放一个"记一笔再 exec 真 rg"的 wrapper，
  用它证明 `auto` 真的走了 rg；
- `sh_eval <shell> <片段>` 在 `$T/ws/a/b` 里 `source` 对应 env 后执行片段，
  并清掉继承来的 `WTOOL_PROJECT_ROOT` / `WTOOL_PROJECT_ID`；
- `for sh in bash zsh` 同一张表跑两遍；没装某个 shell 就跳过那一段；
- wrg 部分覆盖：老的精确/模糊/注释/空目录/用法，加
  ① `WRG_SEARCH=auto|fd|rg` 与 `find` 的输出用 `cmp` 逐字比对（模糊 `-i libc` + 精确 `liba+b` 两种模式）、
  ② 元字符当字面量（`liba+b` 不命中 `libaaab`、`libc.d` 不命中 `libcxd`）、
  ③ 每条后端的"没有命中"和"树下没有这两种文件"（rc + 报错文字）、
  ④ 探测顺序（只有 rg / 只有 fdfind / 只有 fd-find / 只有 fd / 都没有 → `find`）+ `auto` 走 rg 的 wrapper 记号、
  ⑤ 强制指定但可执行不存在、`WRG_SEARCH` 取值不认（rc=2 + 报错文字）、
  ⑥ 高亮：管道里 `grep -c ESC` = 0、`WRG_COLOR=always` 的精确/模糊字节、`NO_COLOR` 压过 `always`、
  `WRG_COLOR` 取值不认、auto 与 find 的着色输出一致、`script`(pty) 下自动上色、
  ⑦ 隐藏目录差异：rg / fd 搜不到、find 搜得到；
- 后端相关的用例按"本机有没有那个可执行文件"跳过，所以条数随环境变：
  同一个夹具下实测 **rg+fd 都在 = 129 条**、只有 rg = 121、只有 fd = 115、都没有（纯 find）= 105，
  失败都是 0（**以脚本最后一行输出为准**）。
