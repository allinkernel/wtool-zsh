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

`wrg` 只认两种文件：`Android.mk`、`Android.bp`（`find` 的 `-name` 就是这两个）。
`-i` 切到模糊模式（子串、忽略大小写），否则精确（`==`）。

- 先 `find . -type f \( -name Android.mk -o -name Android.bp \) -print -quit`：
  空 → stderr `wrg: 当前目录树下没有 Android.mk / Android.bp`，返回 1；
- 再 `find ... -exec awk ... {} +`：模式经环境变量 `WRG_PAT` / `WRG_FUZZY` 传进 awk
  （避免 `-v` 解释转义 / 避免把目标名当正则）；
  - `Android.mk`：行匹配 `^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*[^[:space:]#]+`，取 `=` 之后那段；
  - `Android.bp`：行匹配 `^[[:space:]]*name[[:space:]]*:[[:space:]]*"[^"]*"`，取引号里那段；
  - 名字命中 → `print FILENAME ":" FNR ":" $0`；
- 输出非空就 `sort -t: -k1,1 -k2,2n` 后打印；空 → stderr
  `wrg: 没有匹配 '<模式>' 的目标名`，返回 1；`find`/`awk` 非 0 → stderr
  `wrg: 搜索失败（find/awk 退出码 <n>）`，返回 1；
- 用法错误（选项不认、参数不是 1 个）→ 用法打 stderr，返回 2；`-h` / `--help` → 打 stdout，返回 0。

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
- `sh_eval <shell> <片段>` 在 `$T/ws/a/b` 里 `source` 对应 env 后执行片段，
  并清掉继承来的 `WTOOL_PROJECT_ROOT` / `WTOOL_PROJECT_ID`；
- `for sh in bash zsh` 同一张表跑两遍；没装某个 shell 就跳过那一段；
- 当前条数：**67 条**（bash 33 / zsh 34，以脚本最后一行输出为准）。
