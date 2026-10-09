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
| `proxy_on [IP] [端口]` | 开代理：取值顺序 **参数 → `$PROXY_IP`/`$PROXY_PORT` → 交互式询问**（非交互终端且没值 → rc=2、不挂住）；导出 `http_proxy`/`https_proxy`/`all_proxy` 及其大写共 6 个；`no_proxy` 采取"存原值再追加"（见 4.6） | 0 / 2 |
| `proxy_off` | 关代理：unset 那 6 个；把 `no_proxy`/`NO_PROXY` **还原**成 `proxy_on` 之前的值；保留 `PROXY_IP`/`PROXY_PORT`（同 shell 再开不用重问） | 0 |
| `wrg [选项] <名字>` | 见 4.5（选项位置自由；`-i` / `-e` / `-t` / `-A` / `-B` / `-C` / `-l` / `-c` / `-m` / `--color`） | 0 / 1 / 2 |

### 4.6 代理开关（`proxy_on` / `proxy_off`）

从用户 `.zshrc` 里搬进来的一对命令（**原来是写死 `127.0.0.1:7897` 的别名**）。两条都在
`unalias proxy_on proxy_off 2>/dev/null || true` 之后定义 —— **别名优先于函数**，老 rc 里
若还留着那两条别名，不清掉的话新函数根本轮不到（`tools/dsh-remote` 的 `harness` 踩过同一个坑）。

**取值顺序**（`proxy_on [IP] [端口]`）：

1. **参数**：`proxy_on 10.1.2.3 8080`；
2. **环境变量**：`$PROXY_IP` / `$PROXY_PORT`（`proxy_on` 自己会导出，所以同一 shell 里第二次开不用再问）；
3. **交互式询问**：`PROXY_IP [127.0.0.1]:` / `PROXY_PORT [7897]:`（回车取默认值）。
   ⚠️ **只在 `[ -t 0 ]` 为真时才问**；在脚本/管道里没值就 **rc=2 + 两句提示**，绝不挂住。

**导出的变量**：`http_proxy` / `https_proxy` / `HTTP_PROXY` / `HTTPS_PROXY` = `http://<ip>:<端口>`，
`all_proxy` / `ALL_PROXY` = `socks5://<ip>:<端口>`。

**`no_proxy` 是"保存 + 追加"，不是覆盖**：第一次开时把原值存进 `_PROXY_NO_PROXY_SAVED`，
再追加 `localhost,127.0.0.1,::1,.local`；`proxy_off` 把原值**还原**（原来没有就 unset）。
这么做是因为这台机器的环境里本来就有内网 `no_proxy`（`172.x`/`10.x`…），覆盖掉会连带
把内网直连也塞进代理。

**端口校验**：非数字 → `proxy_on: 端口必须是数字：'xxx'`，rc=2（不导出任何变量）。

判据（两 shell 同一张表，`tests/env_test.sh` 有 9×2 条）：

```sh
R=~/self/wtool/shell/zsh
for sh in bash zsh; do
  $sh -c ". $R/env.$sh
    proxy_on 10.1.2.3 8080 >/dev/null; echo "\$http_proxy|\$all_proxy"      # http://10.1.2.3:8080|socks5://10.1.2.3:8080
    unset PROXY_IP PROXY_PORT; proxy_on </dev/null; echo rc=\$?               # rc=2（非交互不挂住）
    no_proxy=internal.example; proxy_on 1.1.1.1 1 >/dev/null; echo "\$no_proxy"  # internal.example,localhost,127.0.0.1,::1,.local
    proxy_off >/dev/null; echo "\${no_proxy:-空}"                              # internal.example（还原）"
done
```

内部辅助（不打算给人直接敲）：`_win_ip`、`_win_smb_shares`、`_win_server`、
`_wrg_usage`、`_wrg_version`、`_wrg_backend`、`_wrg_color`、`_wrg_re_escape`、`_wrg_re_us`、
`_wrg_norm`、`_wrg_type_names`、`_wrg_fd_glob`、`_wrg_prefix`。

### 4.4 `win` 的服务器分支

`win` 先看 `this_is_wsl`：

- 是 WSL → `wslpath -w . || return 1`，行为与加服务器分支之前逐字一致；
- 不是 WSL → `_win_server`：
  1. `target` = `realpath -m -- "$PWD"`（失败退回 `$PWD`）；
  2. `ip` = `_win_ip`：**只读 `$WIN_IP`**（2026-10-07 起不再 `ip -4 addr` 探测 —— 服务器上探到的
     是内网/VPC 地址，猜错比不猜更坏）。没设 → 返回 1，stderr 两行提示设 `WIN_IP`，**不打印任何一行**；
  3. `conf` = `${WTOOL_SMB_CONF:-/etc/samba/smb.conf}`；
  4. `_win_smb_shares` 用 awk 把 `[share]` 段与段内 `path =` 抽成 `share|path`
     （跳过 `#` / `;` 行，去首尾空白与首尾引号）；
  5. 每个 share 的 path 过 `realpath -m`，与 `target` 做**按路径分隔符对齐**的前缀比较
     （`case "$target" in "$spath")` / `"$spath"/*)`），命中就记相对路径，
     **最长前缀胜出**；
    6. stdout：命中 → **四行**（顺序固定）：`\\<ip>\<share><相对路径>`（Windows UNC：资源管理器/CMD/PowerShell）、`//<ip>/<share><相对路径>`（Linux：`mount -t cifs //srv/share` / `smbclient //srv/share`）、`smb://<ip>/<share><相对路径>`（浏览器 / macOS Finder / GNOME Files）、`<whoami>@<ip>:<绝对路径>`（scp/rsync）；
     `win: 读不到 samba 配置 <conf>`；没有命中 → stderr
     `win: <conf> 里没有 share 的 path 匹配 <target>`；后两种 `rc=1`；
  7. 最后 stdout 一定多一行 `<whoami>@<ip>:<target>`，`return $rc`。

### 4.5 `wrg`

`wrg` 在当前目录树下按**构建目标名**找三类文件（4.5.1）。默认**精确**匹配（`==`），
`-i` 切到模糊模式（4.5.3）。**选项位置自由**：`wrg x -A3` 与 `wrg -A3 x` 等价。

| 选项 | 语义 |
|---|---|
| `-i` / `--ignore-case` | 模糊匹配（4.5.3）；不写 = 精确 |
| `-e <名字>` / `--regexp <名字>` | 多名字查询，可重复；等价于多个精确匹配**取并集**（配 `-i` 时每个名字各做一次模糊）。与位置参数可以混用 |
| `-t <类型>` / `--type <类型>` | 只搜某一类文件：`bp` = Android.bp、`mk` = Android.mk、`make` = 其它 Makefile；可重复 / 逗号分隔（`-t bp,mk`）；不写 = 三类都搜 |
| `-A <n>` / `--after-context <n>` | 命中行**之后** n 行也打印（格式见 4.5.4） |
| `-B <n>` / `--before-context <n>` | 命中行**之前** n 行 |
| `-C <n>` / `--context <n>` | 前后各 n 行（= `-A n -B n`）；`-A/-B/-C` 谁后写谁算 |
| `-l` / `--files` | 只打印命中的**文件路径**（去重、排序、不着色）；压过 `-c`（同 `grep -lc`） |
| `-c` / `--count` | 每个文件的命中条数，形状 `路径:条数`；**只列有命中的文件**（`grep -rc` 会连 0 条的文件一起列，这里不列） |
| `-m <n>` / `--max-count <n>` | **全局**最多输出 n 条命中（排序后按输出顺序取前 n）；`-m 0` = 一条都不出（rc 1）。n 数的是**命中条数**，上下文行不算 |
| `--color[=WHEN]` | `auto`（默认）/ `always` / `never`，CLI 这一层的开关（优先级见 4.5.2） |
| `-h` / `--help` | 用法打 **stdout**，rc 0 |
| `-v` / `--version` | `wrg 1.0（后端 rg）`，rc 0（后端取不到就打成 `?`） |

**解析规则**（手写扫描，**不用 `getopts`**——POSIX 那套不认长选项，也做不到"选项写在查询串后面"）：

1. 逐个参数扫；`--` 之后一律当位置参数（`wrg -- -weird` 查的就是 `-weird`；`wrg -- --help`
   不会打用法，就是查 `--help`）；
2. 短选项簇里布尔项就地吃掉（`-il` = `-i -l`）；碰到要值的短选项（`A B C m e t`）时，
   **剩下的字符**就是值（`-ilA3` = `-i -l -A 3`），剩下的字符为空就吃掉下一个参数（`-A 3`）；
3. 长选项 `--x=v` 与 `--x v` 都认；只有那几个"要值"的（`--color` / `--type` / `--max-count` /
   `--context` / `--after-context` / `--before-context` / `--regexp`）允许带 `=`，
   别的带 `=` 是 rc 2（`wrg --files=1` 报错）；
4. 要值却没有 → stderr `wrg: 选项 -A 缺值` + 用法，rc 2；`-A/-B/-C/-m` 的值不是非负整数 →
   `wrg: -A/--after-context 需要一个非负整数（现在是 x）` + 用法，rc 2；`-t` / `--color` 取值不认、
   未知选项（`-Z` / `--zoo`）→ 都是 rc 2 + 用法；
5. 位置参数**最多一个**（第二个 → rc 2 + `wrg: 只认一个查询串（多出来的：x；多个名字请用 -e）`）；
   查询串总数为 0（`wrg`、`wrg -i`）→ rc 2 + 用法；查询串是空串 → rc 2。

三种搜索后端，**按顺序探测**，前一个没有才用下一个：

| 顺序 | 后端 | 怎么找到它 | 怎么搜 |
|---|---|---|---|
| 1 | rg | `command -v rg` | 按 `-t` 选中的类各跑一次 `rg --no-heading --line-number --with-filename --color=never …`，输出合并后交给 `WRG_PASS=recheck` 的 awk 判命中 |
| 2 | fd | `command -v fdfind` → `fd-find` → `fd`（第一个有的） | `<fd> -t f -g "<按 -t 拼出来的文件名 glob>" -X awk "${_WRG_AWK}"`（`-X` = 批量 exec，等价于 `find … {} +`） |
| 3 | find | 兜底，不用探 | `find . -type f \( -name Android.bp -o … -o -name '*.mak' \) -exec awk "${_WRG_AWK}" {} +`（**谓词不跟着 `-t` 变**：多认的文件由 awk 的 kinds 掩码丢掉，免得三条后端各有一套文件集合） |

- 后端选择：`WRG_SEARCH=auto`（默认，按上表探测）/ `rg` / `fd` / `find`。
  **指定了就一定用它**：`rg` / `fd` 找不到可执行文件 → stderr 报错、返回 **2**；
  取值不认 → 同样 2。`WRG_SEARCH` 只在 `wrg` 里读，不影响别的命令。
- 判命中、抠目标名、枚举目标名、着色、**上下文展开**都在**同一段 awk**（`_WRG_AWK`，
  两个 env 文件里各存一份、**逐字相同**）里，三条后端共用，输出因此逐字一致：
  - `WRG_PASS=search`：读文件，按 4.5.1 的规则取候选目标名；命中就
    `print 路径 ":" FNR ":" $0`；
  - `WRG_PASS=recheck`：读 stdin 上的 `路径:行号:原文`，用同一套规则**重新判一遍**
    ——rg 的几套正则只是"粗筛"，最终判命中一定回到这里，所以三条后端不会各说各话；
  - `WRG_PASS=paint`：读同样形状的行，把命中段包成红粗、目标名里其余部分包成绿（见 4.5.2）；
  - `WRG_PASS=ctx`：读同样形状的行（已排序），按 `-B/-A` 展开成带上下文的输出（见 4.5.4）；
  - `WRG_PASS=names`（读文件）/ `WRG_PASS=names3`（读 `路径:行号:原文`）：**只枚举**目标名
    （`take()` 进收集分支），`END` 里打印"实际匹配的前缀"（见 4.5.3）；
  - 路径归一化：`norm()` 给"既不是 `/` 开头、也不是 `./` 开头"的路径补 `./`
    （fd 直接打印时没有 `./`，加了 `-X` 才有；find 一直有 —— 归一化保证两条路形状一样）。
- 进 awk 的环境变量：`WRG_PAT`（查询串，**一行一个**，`-e` 给多个就是多行）、`WRG_FUZZY`、
  `WRG_KINDS`（认哪几类文件，`1`/`2`/`3` 拼成的串，来自 `-t`）、`WRG_BEFORE` / `WRG_AFTER`
  （上下文行数）、`WRG_COLOR_ON`、`WRG_PASS`。
- **先查有没有可搜文件**（这一步在枚举目标名之前，模糊/精确都一样），文件集合**跟着 `-t` 走**：
  rg 用 `rg --files` + 选中类的 `-g`；fd 用 `<fd> -t f -g "<选中的 glob>" | head -n 1`；
  find 用同样按 `-t` 拼出来的 `-name` 列表 + `-print -quit`。空 → stderr
  `wrg: 当前目录树下没有 <选中的那几类>`（三类都选时逐字就是老那句
  `wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile`），返回 1
  （`Makefile.am` / `Makefile.in` 不在集合里，只有它们的树算"没有可搜文件"）。
  ⚠️ `-t make` 那一类的文件名集合里有 `*.mk`，所以"树里只有 Android.mk"时预检算**有**文件
  （搜出来是 0 条，报"没有匹配"）—— 三条后端一致。
- **rg 那条路**：按 `-t` 选中的类各一次（没选中的类整个不跑），查询串先做正则转义
  （`_wrg_re_escape`：把 `\ ^ $ . * + ? ( ) [ ] { } |` 变字面量），模糊时用 `_wrg_re_us` 换一套
  （见 4.5.3）。**多个查询串合成一个 alternation**（`(a|b)`）粗筛一次，真判命中仍在 awk：
  - `Android.bp`：`-g Android.bp` + `^[[:space:]]*name[[:space:]]*:[[:space:]]*"(…)"`；
  - `Android.mk`：`-g Android.mk` + `^[[:space:]]*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)…`，
    精确模式值后面必须跟 `([[:space:]#]|$)`；
  - 其它 Makefile：`--type amake --type make -g '!Android.bp' -g '!Android.mk'`
    （`amake` = `*.bp` / `*.mk`，`make` = `Makefile` / `*.mk` / `*.mak` 那一族；两套类型都会捎上
    Android 那两个文件，用 `!` glob 排掉，免得被 Makefile 语义再算一遍），粗筛正则 =
    精确 `(^|[^[:alnum:]_])(…)([^[:alnum:]_]|$)`、模糊 `(?i:…)` 那套
    ——模糊那条**不能加词边界**（`-i system` 要能命中 `vbmetasystemimage`）；
  - 模糊模式只给"值"那段套 `(?i:...)`，关键词部分保持大小写敏感；rg 的退出码：
    **1 = 没命中**（不是错误），> 1 才是错（跑过的几次里任意一次 > 1 就整体按错报）。
- **fd 那条路**：fd 的 `-g` 是**开关**（不带参数），选中类的文件名合成**一个** glob
  （`_wrg_fd_glob`，三类都选时 = `{Android.bp,Android.mk,Makefile,makefile,GNUmakefile,*.mk,*.mak}`）；
  fd 没命中时的退出码各版本不一样（9.0.0 给 0，有的给 1），实现里"空输出 + 1"当没命中。
- **语义差异**（rg / fd 与 find 的）：rg / fd 默认**跳过隐藏目录和被 ignore 的目录**
  （`.repo/`、`out/` 这类），find 不跳 —— 所以整树更快，但那些目录里的目标搜不到。
  要连它们一起搜就用 `WRG_SEARCH=find`。模糊模式下这条差异还会影响**枚举**：
  隐藏目录里有个更长的匹配名字时，`find` 会选出更长（更贴）的前缀，
  rg / fd 看不到它 —— 树里没有隐藏目录时三者逐字一致。
- 结果先 `sort -t: -k1,1 -k2,2n`（**纯文本**，ANSI 不参与排序键），然后按这个顺序：
  `-l` / `-c`（只看命中，不着色、不看上下文）→ `-m` 截前 n 条 → 要上色就过一个
  `WRG_PASS=paint` 的 awk（**没有上下文时**，输出与加这些选项之前逐字一致）或
  `WRG_PASS=ctx` 的 awk（**有上下文时**：展开 + 上色一趟做完，见 4.5.4）。
- 输出非空就打印、返回 0；空 → stderr `wrg: 没有匹配 '<模式>' 的目标名`，返回 1
  （**消息里用的始终是用户输入的原串**，不是截断后的前缀；`-e` 给了多个时用**第一个**查询串；
  `-m 0` 也是这条）；后端非 0 → stderr `wrg: 搜索失败（<后端>/awk 退出码 <n>）`，返回 1
  （find 那条路是 `find/awk`，rg 那条路是 `rg`，fd 那条路是 `<fd>/awk`）；
- 用法错误（选项不认、缺值、位置参数不止一个、一个查询串都没有）→ 用法打 stderr，返回 2；
  `-h` / `--help` → 打 stdout，返回 0；`-v` / `--version` → 打 stdout，返回 0。
- 模糊模式**不检查枚举那一步的退出码**（那一步的输出只用来定前缀；真出错时后面那次搜索
  照样会报）。`bash` / `zsh` 取管道退出码的写法不一样（`PIPESTATUS` vs `pipestatus`），
  为了两份逐字等价就不取了。

#### 4.5.1 认哪些文件、值是什么

文件按 **basename** 分类（`kind()`），三类之外的一律不看：

| 类别 | 文件（basename） | 值 = 目标名 | 行匹配 |
|---|---|---|---|
| 1 | `Android.bp` | `name: "X"` 引号里那段 | `^[[:space:]]*name[[:space:]]*:[[:space:]]*"[^"]*"` |
| 2 | `Android.mk` | `LOCAL_MODULE` / `LOCAL_PACKAGE_NAME` 等号右边第一个词 | `^[[:space:]]*(LOCAL_MODULE\|LOCAL_PACKAGE_NAME)[[:space:]]*:?=[[:space:]]*[^[:space:]#]+` |
| 3 | 其它 Makefile：`Makefile` / `makefile` / `GNUmakefile` / `*.mk`（`Android.mk` 除外）/ `*.mak` | 规则行冒号前那串**词**，外加 `.PHONY:` 声明的词 | 见下（`rule_prefix()` + `cand_make()`） |

`-t/--type` 就是按这张表挑类别：`bp` = 类别 1、`mk` = 类别 2、`make` = 类别 3
（`Android.mk` 属类别 2，`-t make` 时它**整个不参与**。判类别的 `kind()` 结果还要过
`WRG_KINDS` 掩码，所以三条后端的文件集合不会各说各话）。

**三类文件共用两条否决规则**（`cand_bp` / `cand_mk` / `rule_prefix` 里各有一份）：

1. **行首是 TAB** → 不是目标定义（Makefile 的 recipe 必须 TAB 缩进；`Android.bp` /
   `Android.mk` 也照这条办 —— 真 AOSP 实测没有 TAB 缩进的 `name:` / `LOCAL_MODULE`）；
2. 类别 3 另有：**冒号前那段里有 `"` 或 `'`** → 整行否决（`@echo "Target …: …"` 这种字符串）。

类别 3 的判定（一行可能给出**多个**候选，按顺序挨个试，**取第一个命中的**——
所以一行只输出一次、高亮也只落在第一个命中的那个词上，模糊时这个词还分红 / 绿两段，见 4.5.2）：

1. **规则行**：`^[[:space:]]*<目标>([[:space:]]+<目标>)*[[:space:]]*:` ——
   冒号是**扫到的第一个** `:`，且它后面不紧跟 `=`（`:=`）也不是 `::=`；
   扫到 `=`、`$`、`#`、`"`、`'` 里的任何一个就**否决整行**；
2. **`.PHONY:` 声明行**：第 1 步认出来的规则词里如果有 `.PHONY`，那么冒号之后、
   第一个 `#` 之前的那串词**也是**目标（词里含 `$`、`=`、`\`、`"`、`'` 的跳过）。

**正例**（都算目标名）：`mkrule:`、`mkrule2 mkrule3: $(deps)`（`mkrule2` 和 `mkrule3` 都算）、
`.PHONY: mkphony1 mkphony2`（两个都算；`.PHONY` 本身是规则词所以也算）、
`mkslash/out.bin: dep`、`target:: dep`。

**反例**（都不算目标名，这是最容易写错的地方，测试里逐条钉着）：

| 行 | 为什么不算 |
|---|---|
| `VAR := mkvarname` / `VAR ::= x` | 冒号紧跟 `=` / `::=`，是赋值不是规则 |
| `VAR ?= mkqname` / `VAR = x` / `export A := b` | 扫到 `=` 就否决整行 |
| `ifeq ($(strip $(MKTARGETS)),)`、`include $(CLEAR_VARS)` | 目标里不许有 `$` |
| `ifeq (nomkcolon,plain)` | 压根没有冒号 |
| `$(MKTARGET): dep` | 目标里有 `$` |
| `# mkcommented: x` | 扫到 `#`，注释行 |
| `.PHONY: $(TARGETS)` | 声明部分里含 `$` 的词跳过 |
| `Android.mk` 里的 `mkandroidrule:` | `Android.mk` 只走类别 2，规则行不算（不然会和类别 3 重复计入） |
| `\t@echo "Target system fs image: $(1)"`（TAB 开头） | 行首 TAB = recipe 行；引号那条也够否决它 |
| `  @echo "Install system fs image: $@"`（空格缩进、在 `define` 体内） | 冒号前有 `"`（TAB 那条管不着它，真 AOSP 的 3514 行就是这种） |
| `\tfpztabtarget: $(X)` | 行首 TAB（这条只有 TAB 规则能挡） |
| `$(info fpzinfo: $(FPZ_DEPS))` | 扫到 `$` |
| `define fpzdefine` / `endef` | 没有冒号 |

**已知残留**（2026-10-07 实测，**没修**）：`$(error ...)` / `$(warning ...)` 这种跨行字符串的
**续行**如果是一句散文，里面的词还是会被当成目标名。真 AOSP 上的例子：

```make
  $(if $(filter %.apk, $(2)),$(error \
     Prebuilt apk found in PRODUCT_COPY_FILES: $(1), use BUILD_PREBUILT instead!))) \
```

`wrg apk` 会命中第二行（`Prebuilt` / `apk` / `found` / `in` 都成了"目标"）。
要挡掉它得知道"上一行是不是续行"（或做括号配对），而 **rg 那条路是按行拿结果的**
（`recheck` 只看到 rg 筛出来的那些行），加上这条规则三条后端就对不齐了；
试过的替代规则又都会误伤真目标（见 `BACKLOG.md` 那一轮）。

#### 4.5.2 `wrg` 的高亮

命中的**目标名**分两段上色；行内其它字符（`name: "` / `",` / `.PHONY: ` / `: $(…)` 这些）
一律不着色：

| 段 | 颜色 | 覆盖范围 |
|---|---|---|
| 输入匹配到的那一段 | **红 + 加粗** `\033[1;31m` … `\033[0m` | 精确 = 整个目标名；模糊 = 实际匹配的那个前缀在**原文**里覆盖的那一段（`hit()` 把归一化后的下标映射回原串，所以 `vbmeta_system_other` 里 `vbmetasyst` 会连中间的 `_` 一起包住） |
| 目标名里**其余**（没匹配到的）部分 | **绿、不加粗** `\033[32m` … `\033[0m` | 命中段之前一段、之后一段；某一段为空就不打那对绿码 |

- **绿段只在模糊模式出现**：精确模式命中的就是整个名字，两头都空 → 只有红段（老行为不变）；
  模糊但整名命中（`wrg -i <整个名字>`）同样没有绿段；
- **只标第一处**：`hit()` 找的是第一处命中，一个目标名里同一个子串出现多次时，
  只有第一处红粗，后面的（含第二次出现）都算"没匹配到" → 绿；
- 例：`wrg -i ystemim` 命中 `systemimage` → `\033[32ms\033[0m\033[1;31mystemim\033[0m\033[32mage\033[0m`；
  `vbmetasystemimage` 同理（`vbmetas` 绿 + `ystemim` 红粗 + `age` 绿）；
- 候选词在整行里的起始下标由 `words()` 记进 `WO[]`，着色按它定位
  （`Android.bp` 是"引号里那段"、`Android.mk` 是"等号后那段"、Makefile 是"命中的那个词"），
  命中段长度由 `hit()` 写进全局 `hlen`；`paint` pass 里用 `length(v)` 定目标名结尾，
  两段绿分别是 `substr(ft, vs, o)` 与 `substr(ft, vs + o + hlen, length(v) - o - hlen)`。

上色开关有两层：CLI 的 `--color=WHEN`（写了就以它为准）和 env 的 `WRG_COLOR`（默认 `auto`）。
两层的语义**故意不一样**（rg 的口径）：

| 情形 | 上色？ |
|---|---|
| `--color=always` | **是**，连 `NO_COLOR` 也压不过它（显式要求） |
| `--color=never` | 否（`WRG_COLOR=always` 也压不过） |
| `--color=auto`（或没写 `--color` 且 `WRG_COLOR=auto`） | 只有 stdout 是终端**且** `NO_COLOR` 为空才上色 |
| 没写 `--color`、`WRG_COLOR=always` | 是（不看终端）；但 **`NO_COLOR` 非空 → 否** |
| 没写 `--color`、`WRG_COLOR=never` | 否 |
| `WRG_COLOR` 取值不认 | stderr `wrg: WRG_COLOR 只认 auto / always / never（现在是 x）`，返回 2 |
| `--color=WHEN` 取值不认 | stderr `wrg: --color 只认 auto / always / never（现在是 x）` + 用法，返回 2 |

一句话：**`--color=always` 压过 `NO_COLOR`，env 里的 `WRG_COLOR=always` 压不过**（两条方向
相反的用例都钉在测试里）。命令行里的 `--color=always` 是"显式要求"，env 变量只是默认值。

内部变量（不是给人设的）：`WRG_PAT`（查询串，一行一个）/ `WRG_FUZZY` / `WRG_PASS`
（传给 awk 的模式、模式开关、pass 名）、`WRG_KINDS`（认哪几类，来自 `-t`）、
`WRG_BEFORE` / `WRG_AFTER`（上下文行数）、`WRG_COLOR_ON`、`_WRG_AWK`（那段 awk 的正文）、
`_WRG_RE_BP_NAME` / `_WRG_RE_MK_NAME` / `_WRG_RE_MAKE_NAME`（模糊枚举那一步的粗筛正则）。

#### 4.5.3 `wrg -i` 的模糊匹配（2026-10-07 改）

`wrg` 搜的是 **AOSP 目标名**，所以模糊匹配按"**先去 `_`，再从尾部逐级截断，用前缀去匹配**"：

1. **枚举目标名**（`_wrg_prefix` → awk 的 `WRG_PASS=names` / `names3`）：
   把三类文件里的**所有**目标名抠出来（4.5.1 的规则，一次扫完），用**和搜索同一个后端**
   （`auto` 下就是 rg），**每次都重扫当前目录、不缓存**；
   `find -exec … {} +` 和 `fd -X` 会按命令行长度**分批**，每批各打印一行，
   shell 侧再取最长的那行（`printf … | awk 'length($0) > length(m) { m = $0 } …'`）；
2. **归一化**：`key()` = 去掉 `_` + 转小写，查询串和候选名两边都过它；
3. **逐级截断**：`addname()` 对每个名字算"和 `npat` 的最长公共前缀"（在每个位置上比），
   取全局最大 `maxlen`；`END` 里只有 `maxlen >= min(4, length(npat))` 才打印
   `substr(npat, 1, maxlen)` —— 这就是**实际匹配用的前缀**。
   最短试到 **4 个字符**；查询去 `_` 后不足 4 个字符就整个试；
4. **输出**：`pfx` 与"用户输入去 `_` 后"**不同**时，stdout 先打三行表头
   （`用户输入<原样输入>` / `实际匹配<pfx>` / `匹配目标名如下：`），再打命中行；
   相同就不打表头（正常命中保持干净输出）。随后那次搜索用 `WRG_PAT=<pfx>`、
   `WRG_FUZZY=1`，也就是**子串匹配**（不锚定在目标名开头：`-i kphony1` 仍要能命中
   `mkphony1`），高亮把前缀在原文里覆盖的那一段标红粗、名字里其余部分标绿（见 4.5.2）。

模糊那条路的 rg 粗筛正则由 `_wrg_re_us` 生成：把 `pfx` 的每个字符转义后**逐字挂一个 `_*`**、
整段套 `(?i:…)` —— 归一化只做"去掉 `_`"，所以"归一化后含 `pfx`"⇔"原文匹配这条正则"，
粗筛既不漏（`vbmeta_system_mk` 能被 `vbmetasystem` 命中）也不误伤（`. ` 这类元字符仍按字面量）。

- 表头只在"截断过"时出现：`wrg -i vbmeta_system`（带 `_`）与 `wrg -i vbmetasystem` 等价、
  都不打表头；`wrg -i vbmeta_systmmm` 打表头（实际匹配 `vbmetasyst`）；
- 到最短长度仍无命中 → stderr `wrg: 没有匹配 '<用户输入>' 的目标名`，返回 1
  （不附"试到的最短前缀"那句，免得和既有报错文字分叉）；
- **多个查询串（`-e`）时每个名字各算一次前缀**：`_wrg_prefix` 一行一个查询地调，
  "取最长那行"的分批逻辑不动；算出来的前缀按顺序拼进 `WRG_PAT`（一行一个），
  awk 里 `hit()` 按顺序取第一个命中的。某个名字一个都没枚举到 →
  **只给它打一行 stderr 警告、跳过它**，其余名字照常搜（全都没枚举到才 rc 1，
  这时输出与上面单名字那条逐字一样）；
- 表头也是**每个名字三行**、按用户给的顺序打（截断过的才打）；
- `-i` 之外的行为（精确匹配、后端选择、`WRG_COLOR` / `NO_COLOR`、排序、退出码）不变。

#### 4.5.4 `wrg` 的上下文行（`-A` / `-B` / `-C`，2026-10-07 加）

`-A n` 打命中行之后 n 行、`-B n` 打之前 n 行、`-C n` = 前后各 n 行；`-A/-B/-C` 谁后写谁算，
`-C 0` 等于不写（走老那条 paint 路径，一行 `--` 都不打）。**它们只影响显示**：
命中判定、排序、退出码、`-l` / `-c` 都不受影响（`-A3` 没命中还是 rc 1 + 老提示）。

**输出格式照 grep / rg 的惯例**（字节形状）：

| 行 | 形状 | 着色 |
|---|---|---|
| 命中行 | `路径:行号:原文` | 老规矩（4.5.2 分两段） |
| 上下文行 | `路径-行号-原文`（两个冒号换成减号） | **不着色**（一个转义都不打） |
| 块分隔 | 单独一行 `--` | 无 |

- **块 = 合并后的窗口**：第 i 个命中的窗口是 `[行号-B, 行号+A]`（下界钳到 1），
  两个窗口**重叠或相邻**（`lo <= 上一块的 hi + 1`）就并成一块 —— 同一行只打一次、也不多打 `--`；
- `--` 只在**两块之间**打：一块里的行之间不打、**开头和结尾都不打**；跨文件也算两块
  （`grep -A1 x a.txt b.txt` 就是文件之间打 `--`，实测对齐）。

**实现层（关键约束）**：上下文**必须由共用那段 awk 算**，不能用 rg / grep 自带的
`-A/-B` —— 它们三家的窗口语义、`--` 规则都不一致，而且模糊那条路要先枚举名字再匹配
（自带上下文对不上"枚举出来的名字"）。做法是**单开一个 `ctx` pass**（`WRG_PASS=ctx`）：

1. shell 侧照旧把命中行 `sort -t: -k1,1 -k2,2n`（`-m` 截断也在这之后、展开之前）；
2. 排序过的命中行喂给 `ctx` pass；它按"路径相同"攒一批（排序保证同文件的命中连在一起）；
3. 一批攒满（或 `END`）就 `flush()`：先把命中行号并成窗口块（上面的规则），
   再 `getline < 路径` **逐行读回那个文件**，落在块里的行按"是不是命中行"分别打成
   冒号 / 减号形状；命中行顺带按 4.5.2 上色（`WRG_COLOR_ON=1` 时），上下文行永不上色；
   读完 `close()`（避免开一堆 fd），被删 / 读不到时退化成"只打命中行"；
4. 输出天然就是"按路径 + 行号"排序的（命中行本来就是排好序的，块内逐行递增）。

`WRG_PASS=paint`（没有上下文时）与 `ctx` pass 里的上色走的是同一套逻辑（都调 `cand()` +
`hit()` 分两段），所以**加不加 `-A/-B/-C` 的命中行着色逐字一样**。

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
- wrg 的 **Makefile 夹具**是第三棵树 `$T/src3`：`keep/` 下三类文件都有
  （`Makefile` 里 18 行钉着行号：注释、`LOCAL_PATH :=`、`VAR :=` / `VAR ?=`、两种 `ifeq`、
  `.PHONY: mkphony1 mkphony2`、单目标/多目标规则行、`$(MKTARGET):`、带 `/` 的目标、
  注释里的冒号、同名目标 `mkshared`；外加 `GNUmakefile` / `makefile` / `extra.mk` / `other.mak` /
  `Android.mk`（里面故意放一条只有 Makefile 语义才认的 `mkandroidrule:`）/ `Android.bp`），
  另加 `$T/mkonly`（只有 `Makefile`）和 `$T/amonly`（只有 `Makefile.am`）两棵小树；
- wrg 的**假阳性夹具**是第四棵树 `$T/src4`：`keep/Makefile` 15 行（行号钉着）——
  真目标 `.PHONY: fpzreal` / `fpzreal: $(FPZ_DEPS)` / `fpzmulti1 fpzmulti2: dep`，
  夹着 TAB 缩进的 `@echo "Target fpzreal fprec1 fs image: $(1)"`、空格缩进的
  `  @echo "Install fpzreal fprec2 fs image: $@"`、`define fpzdefine` /
  `  @echo "Uncompress fpzdeftarget $1"` / `endef`、`$(info fpzinfo: $(FPZ_DEPS))`、
  `# fpzcommented: comment`、`VAR := fpzvar`、`export A := fpzexport`、`ifeq (...)`、
  TAB 缩进的 `	fpztabtarget: $(X)`（前两条照抄真 AOSP `build/make/core/Makefile`）；
- wrg 的**模糊算法夹具**是第五棵树 `$T/src5`：`keep/Android.bp` 三个 `name:`
  （`vbmetasystem` / `vbmetasystem_ext` / `vbmeta_system_other`）+
  `keep/Makefile`（`.PHONY: vbmeta_system_mk` + `vbmeta_system_mk: dep` + 一条 TAB recipe）；
- wrg 的**上下文夹具**是第七棵树 `$T/src7`：`keep/Android.bp` 22 行（行号钉着）——
  `ctxa@2` / `ctxb@7` / `ctxc@20`，1..9 里第 4、5 行相邻（`-C2` 时前两块必须合并），
  另有 `keep/Android.mk`（`othertgt@1`）用来验"跨文件也打 `--`"和 `-l` / `-c` 的多文件输出；
- wrg 的**分两段着色夹具**是第六棵树 `$T/src6`：`keep/Android.bp` 四个 `name:`
  （`systemimage` / `vbmetasystemimage` / `systemimagesystemim` / `vbmetasystemim`，
  行号 2 / 6 / 10 / 14 钉着）—— 依次钉住"匹配段在中间（前 + 后都绿）"、
  "长名字里同一段仍在中间"、"同一子串出现两次（第二次连同尾巴一起绿）"、
  "匹配段正好在结尾（没有后段绿码）"四种边界；
- `sh_eval <shell> <片段>` 在 `$T/ws/a/b` 里 `source` 对应 env 后执行片段，
  并清掉继承来的 `WTOOL_PROJECT_ROOT` / `WTOOL_PROJECT_ID`；
- `for sh in bash zsh` 同一张表跑两遍；没装某个 shell 就跳过那一段；
- wrg 部分覆盖：老的精确/模糊/注释/空目录/用法，加
  ① `WRG_SEARCH=auto|fd|rg` 与 `find` 的输出用 `cmp` 逐字比对（`$T/src2` 上模糊 `-i libc` +
  精确 `liba+b`，`$T/src3` 上模糊 `-i mkrule` + 精确 `mkshared`，也就是三类文件都过一遍）、
  ② 元字符当字面量（`liba+b` 不命中 `libaaab`、`libc.d` 不命中 `libcxd`）、
  ③ 每条后端的"没有命中"/"树下没有这三类文件"/"只有 `Makefile.am` 也算没有"/
  "只有 `Makefile` 也搜得到"（rc + 报错文字）、
  ④ 探测顺序（只有 rg / 只有 fdfind / 只有 fd-find / 只有 fd / 都没有 → `find`）+ `auto` 走 rg 的 wrapper 记号、
  ⑤ 强制指定但可执行不存在、`WRG_SEARCH` 取值不认（rc=2 + 报错文字）、
  ⑥ 高亮：管道里 `grep -c ESC` = 0、`WRG_COLOR=always` 的精确/模糊字节（含 Makefile 规则行、
  `.PHONY` 声明、`Android.mk` 的值边界）、`NO_COLOR` 压过 `always`、
  `WRG_COLOR` 取值不认、auto 与 find 的着色输出一致、`script`(pty) 下自动上色、
  ⑦ 隐藏目录差异：rg / fd 搜不到、find 搜得到、
  ⑧ **Makefile 目标的判定**：`mkrule:` / 多目标行 `mkrule2 mkrule3:` 两边都算 / `.PHONY` 声明的词 /
  `.PHONY` 本身 / 带 `/` 的目标 / 三类文件混在一棵树里同名目标都命中且按路径排序 /
  `GNUmakefile`·`makefile`·`*.mk`·`*.mak` 都认 / `Android.mk` 的规则行不算、同名目标不重复出现，
  以及**反例**逐条：`VAR :=`、`VAR ?=`、`# 注释里的冒号`、`$(MKTARGET):`、两种 `ifeq` 都不命中；
  ⑨ **分两段着色**（`$T/src6`，2026-10-07 加）：`wrg -i ystemim` 四行的**完整 ANSI 字节**
  （绿段覆盖命中段之前 / 之后、行内其它字符不着色）、一个名字里命中两次时红段计数 = 1、
  精确模式整名红粗且绿码计数 = 0、模糊但整名命中也没有绿段、管道里 `grep -c ESC` = 0、
  `NO_COLOR` 压过 `WRG_COLOR=always`、auto / rg / fd 与 find 的着色输出逐字一致；
- **假阳性**（`$T/src4`，2026-10-07 加）：夹具里真目标 `fpzreal`（`.PHONY:` + 规则行）
  旁边埋着 8 种"看着像目标其实不是"的行（TAB 缩进的 `@echo "…: …"`、空格缩进的同形状、
  `define` 体内的 recipe、`$(info …)`、`# 注释:`、`VAR :=`、`export A :=`、
  TAB 缩进的 `fpztabtarget: $(X)`），每行都带一个只属于它的探针名。断言：
  `wrg fpzreal` / `wrg -i fpzreal` 的输出**只有那两行真目标**、
  `| grep -c '@echo'` = 0、多目标行 `fpzmulti2` 照旧命中，
  8 个探针名**精确 + 模糊各一条**都是 `没有匹配 … rc=1`（共 17 条/每个 shell）；
- **新模糊算法**（`$T/src5`，2026-10-07 加）：三类文件混着有 `_` / 没 `_` 的目标名
  （`vbmetasystem` / `vbmetasystem_ext` / `vbmeta_system_other` / `vbmeta_system_mk`）。断言：
  `wrg -i vbmeta_systmmm` 的三行表头 + 5 行命中**逐字**（含"实际匹配 `vbmetasyst`"）、
  表头第一行保留用户写的 `_`、`_` 归一等价（`-i vbmeta_system` 与 `-i vbmetasystem`
  同一批、都不打表头）、正常命中 `grep -c 用户输入` = 0 而截断命中 = 1、
  下界 4（`vbmzzzzzz` 不命中 rc=1；`vbme` 命中；不足 4 个字符的 `vbm` 整个试也命中）、
  `-i 'libc.d'` 的 `.` 是字面量、**子串不锚定**（`-i metasystemim` 截成 `metasystem` 后命中
  `vbmetasystem`，表头逐字）、`WRG_COLOR=always` 只包住实际匹配那一段（含 `_` 的原文按原串下标）、`$T/src5` 上三后端 `cmp` 一致（截断带表头 + 归一 + 精确各一条）、
  管道零 ANSI、`rg` / `fd` 那条路能命中带 `_` 的名字；
- **选项位置自由 + 新选项**（2026-10-07 加）：
  ① 位置自由 —— `wrg -A1 -i ctx` / `wrg ctxa -i` / `wrg -B 2 -i ctx` / `wrg -A 2 ctx -i`
  都对着**字面量期望值**比（不是"两条命令互相相等"，免得两条都报错也算过）、
  `-il` / `-ilA1` 捆绑、`-tbp` 贴值、`--type=bp` 等号写法；
  ② `--` 结束符 —— `wrg -- -weird` 与 `wrg -- --help` 都当查询串（rc 1 + 老提示，
  **不打用法**）、`wrg -- ctxa` 照常命中；
  ③ 缺值（`-A` / `-m` / `-e` / `-t` / `--color` / `--max-count`）rc 2 + 报"缺值"、
  未知选项（`-Z` / `--zoo`）rc 2 + 报"不认识的选项" + 打用法、
  多个位置参数（`wrg a b`）rc 2 + `只认一个查询串`；
  ④ `-t`/`--type`：`bp` / `mk` / `make` 三类各只剩自己那一行（用 `$T/src3` 里
  **三类文件同名的 `mkshared`** 钉）、`bp,mk` 逗号、重复 `--type`、
  `-t make` 不认 Android.mk 的目标、`-t bp` 不认 Makefile 规则行、取值不认 rc 2、
  "树里没有这一类"的提示语跟着类型走；
  ⑤ `-l` / `-c`：同文件 3 个命中只出一行 / `路径:条数`、多文件按路径排序、
  `-lc` 里 `-l` 压过 `-c`；
  ⑥ `-m`：`-m2` 出前 2 条、`--max-count=1`、`-m1 -A1` 上下文只跟着留下的那条、
  `-c -m1` 计数只看留下的那条、`-m0` → rc 1 + 老提示；
  ⑦ `-e`：并集、`--regexp` 长选项、其中一个没命中不影响另一个（rc 0）、
  全都没命中 rc 1、`-i -e` 每个名字各做一次模糊（截断过的那个打表头）；
  ⑧ `--color`：`always` 在管道里上色、**`NO_COLOR` 压不过 `--color=always`**、
  **`NO_COLOR` 压得过 env 的 `WRG_COLOR=always`**（方向相反的两条都钉着）、
  `never` 压过 `WRG_COLOR=always`、`--color never` 分开写、`auto` 管道里不上色、
  取值不认 rc 2 + 报错文字；
  ⑨ `-h`（rc 0 + 第一行 `Usage: wrg [选项] <名字>`）、`-v`（rc 0 + `wrg 1.0（后端 …）`）、
  `-h` 写在查询串后面也认；
- **上下文行 `-A` / `-B` / `-C`**（`$T/src7`，2026-10-07 加）：
  ① `-A1` / `-B1` / `-C2` 三份**逐字节**期望值（命中行冒号、上下文行减号、块之间 `--`）、
  `-C2` 合并后 `sort | uniq -d` 为空且总行数 = 15（第 5、6 行只出现一次、只一个 `--`）、
  `--` 条数 = 块数-1（不写 = 0 / `-A1` = 2 / `-C2` = 1）、
  ② `-A 1` / `-C 2` 分开写等价、`-C2 -A0` 后写覆盖（等于 `-B2`，锚定到字面量）、
  `-A2 -B1` = `-C1 -A2`（另有行数 = 14 锚定）、`-C0` 等于不写、
  ③ 只影响显示：`-A3` 没命中还是 rc 1 + 老提示；滤掉上下文行后与不带 `-A` 逐字一致、
  ④ 跨文件也打 `--`、带 `-A1` 的管道输出零 ANSI、`--color=always` 时命中行红粗而
  上下文行一个转义都没有（逐字节）、
  ⑤ `$T/src7` 上三后端 `cmp`（`-A1 -B1` / 跨文件 `-A1` / `-t bp -C2` 各一条）+
  着色版本 auto / rg / fd 与 find 逐字一致；
- **反向验证**（2026-10-07 实测）：这一批新用例拿 `git show HEAD:env.zsh|env.bash`
  （改动前那份）跑，**150 条 FAIL**（新实现 499 通过 / 2 失败，那 2 条是本机
  `win | head -1` 的破管道老毛病）；
- 后端相关的用例按"本机有没有那个可执行文件"跳过，所以条数随环境变：
  同一个夹具下实测 2026-10-07（加完上下文与新选项之后）**rg+fd 都在 = 499 通过**
  （另有 2 条本机 `win | head -1` 的破管道老毛病，与 wrg 无关）；
  加这批之前是 299 通过 / 同样那 2 条失败；容器 `wrg-test` 里（非 WSL、没有 `ip`、mawk、
  rg + fdfind）是 **497 通过 / 0 失败**（**以脚本最后一行输出为准**）。
