# shell/zsh —— 个人 shell 别名与函数集合

一组**和具体项目无关**的 shell 小工具：跳到 repo 工作区根、记路径再跳回来、WSL 的
`win` / `start`、当前目录树下找 `Android.bp` / `Android.mk` / **Makefile** 目标名的 `wrg`
（带 rg / grep 风格的选项：`-i` / `-e` / `-t` / `-A -B -C` 上下文行 / `-l` / `-c` / `-m` / `--color`，
选项位置自由）
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

### 3. 函数（公开 13 个 + 内部若个，见 architecture §4.3）

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

#### `proxy_on [IP] [端口]` / `proxy_off` —— 代理开关

原来在你 `.zshrc` 里写死 `127.0.0.1:7897` 的两条别名，搬进项目后**不再写死**：

```sh
proxy_on                    # 没给值就问你要：PROXY_IP [127.0.0.1]: / PROXY_PORT [7897]:
proxy_on 10.1.2.3 8080      # 也可以直接给
PROXY_IP=… PROXY_PORT=… proxy_on   # 或者先 export（同一 shell 第二次开就不用再问）
proxy_off                   # 清掉 6 个代理变量
```

- **取值顺序**：参数 → `$PROXY_IP`/`$PROXY_PORT` → **交互式询问**。
  脚本/管道里没值就报错退出（rc=2），**不会挂住**。
- 导出 `http_proxy` / `https_proxy` / `all_proxy` 与对应大写共 6 个；
  `all_proxy` 用 `socks5://`。
- **`no_proxy` 只追加、不覆盖**：开之前的值会记下来，`proxy_off` 时**还原** ——
  你环境里那些内网段（`172.x`/`10.x`）不会被吃掉。
- `proxy_off` 保留 `PROXY_IP`/`PROXY_PORT`，所以开关来回切不会每次都被问。
- ⚠️ 老 `.zshrc` 里那两条 `alias proxy_on=…` / `alias proxy_off=…` 可以删了：
  本文件在定义前会 `unalias` 一次，留着也不会生效（但看着乱）。

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
| 1 | `\\<ip>\<share><相对路径>` | **Windows**：资源管理器地址栏 / CMD / PowerShell 直接能用（UNC，路径分隔符也换成 `\`） |
| 2 | `//<ip>/<share><相对路径>` | **Linux**：`mount -t cifs //srv/share /mnt/x`、`smbclient //srv/share` |
| 3 | `smb://<ip>/<share><相对路径>` | **浏览器 / macOS Finder / GNOME Files**：粘进地址栏就能开 |
| 4 | `<whoami>@<ip>:<绝对路径>` | 直接 `scp`/`rsync` 用 |
| ~~1~~ | ~~`//<ip>/<share><相对路径>`~~ | ~~旧版只有这一行~~ | 读 `/etc/samba/smb.conf` 的 `[share]` + `path = …`，取**最长前缀匹配**目标目录的那个 share（按路径分隔符对齐：share `path=/srv/share` 不会被 `/srv/share2` 命中），拼上目标目录相对 share 的那段 |

- `<ip>`：**必须来自环境变量 `WIN_IP`** —— 本命令**不做 `ip addr` 探测**（服务器上探到的
  常常是内网/VPC 地址，猜错比不猜更坏）。没设就报错、不打印任何一行。
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

#### `wrg [选项] <名字>` —— 找 Android.bp / Android.mk / Makefile 的目标名

在**当前目录树下**递归找三类文件里的目标名，输出
`文件:行号:命中行`（按文件名、行号排序，可以直接喂给 `grep` / 编辑器跳转）：

**选项**（全部可以写在查询串前面或后面，见下面"选项位置自由"）：

| 选项 | 作用 |
|---|---|
| `-i` / `--ignore-case` | 模糊匹配（见下面「模糊匹配怎么算」）；不写 = 精确 |
| `-e <名字>` / `--regexp <名字>` | 多名字查询，可重复；多个名字取**并集**（配 `-i` 就是每个名字各模糊一次） |
| `-t bp` / `-t mk` / `-t make` | 只搜某一类文件：`bp` = Android.bp、`mk` = Android.mk、`make` = 其它 Makefile；可以写多次或用逗号（`-t bp,mk`）；不写 = 三类都搜 |
| `-A <n>` / `-B <n>` / `-C <n>` | 命中行**之后 / 之前 / 前后各** n 行也打出来（`-C n` = `-A n -B n`；格式见下） |
| `-l` / `--files` | 只打印**命中的文件路径**（去重、排序） |
| `-c` / `--count` | 打印**每个文件的命中条数**（`路径:条数`） |
| `-m <n>` / `--max-count <n>` | 全局最多输出 n 条命中（按排序后的顺序取前 n） |
| `--color=auto|always|never` | 这一次运行的颜色开关（见下面「高亮」） |
| `-h` / `--help` | 打用法，返回 0 |
| `-v` / `--version` | 打版本和当前后端（例：`wrg 1.0（后端 rg）`），返回 0 |

**选项位置自由** —— 下面三行完全等价（查询串在前在后都行，值可以贴着写也可以分开写）：

```sh
wrg system_image_defaults -A3
wrg -A3 system_image_defaults
wrg -A 3 system_image_defaults
```

- 布尔短选项可以**捆**在一起：`-il` = `-i -l`、`-ilA3` = `-i -l -A 3`；
- 长选项 `--type=bp` 与 `--type bp` 都认；
- `--` 之后一律当查询串：`wrg -- -weird` 就是查 `-weird`（`wrg -- --help` 不会弹用法）；
- **位置参数只能有一个查询串**（`wrg a b` 报错、返回 **2**）；多个名字请用 `-e`；
- 选项不认识（`wrg -Z x`）、要值没给（`wrg -A`）、`-A/-B/-C/-m` 的值不是非负整数：
  用法打到 stderr，返回 **2**。

| 文件 | 认的写法 |
|---|---|
| `Android.bp` | `name: "xxx"` |
| `Android.mk` | `LOCAL_MODULE := xxx` / `LOCAL_PACKAGE_NAME := xxx`（`:=` 或 `=`，行首可以有空白） |
| 其它 Makefile：`Makefile` / `makefile` / `GNUmakefile` / `*.mk`（`Android.mk` 除外）/ `*.mak` | **构建目标名**：规则行 `目标 目标: 依赖` 冒号前那串词（不含 `=` `$` `#` `"` `'`），外加 `.PHONY: 目标 …` 声明的那些词 —— 一行里有多个目标就逐个算；**以 TAB 开头的行不算**（Makefile 的 recipe 必须 TAB 缩进，那是命令行不是目标定义） |

| 用法 | 匹配方式 |
|---|---|
| `wrg libfoo` | **精确**：目标名和 `libfoo` 完全相同（区分大小写） |
| `wrg -i vbmetasystmmm` | **模糊**：目标名与查询串**都去掉 `_`**、忽略大小写地比；查询串**从尾部逐级截断**，用实际能命中的最长前缀去**子串匹配**（最短试到 4 个字符） |

> ⚠️ "子串匹配"= 目标名里**含**这个前缀就行，**不要求出现在名字开头**：
> 前缀 `metasystem` 能命中 `vbmetasystem`。要"名字必须以它开头"得自己看输出。

**模糊匹配（`-i`）到底怎么算**（四步，每次运行都重扫当前目录，不缓存）：

1. **枚举目标名**：先把三类文件里的**所有目标名**取出来（用和搜索同一个后端）；
2. **归一化**：查询串和候选目标名**都去掉 `_`**、都转小写；
3. **逐级截断**：先拿整个查询串去比，没有命中就去掉最后一个字符再比，
   一直试到命中或只剩 **4 个字符**（查询本身不足 4 个字符就整个试）——
   记下**实际匹配用的那个前缀**；
4. **输出**：实际匹配的前缀和"用户输入去掉 `_` 之后"**不一样**时，先打三行表头
   （措辞固定，第一行照抄用户输入、带原来的 `_`），再打命中行；正常命中不加表头。

```sh
wrg -i vbmeta_systmmm
# 用户输入vbmeta_systmmm
# 实际匹配vbmetasyst
# 匹配目标名如下：
# ./build/make/core/main.mk:1383:.PHONY: vbmetasystemimage
# ./build/make/core/main.mk:1384:vbmetasystemimage: $(INSTALLED_VBMETA_SYSTEMIMAGE_TARGET)
```

> 逐级截断只从**尾部**去掉字符：`vbmeta_systmmm`（故意写错尾巴）能命中 `vbmetasystemimage`，
> 但开头写错就没办法了。`_` 不算数：`wrg -i vbmeta_system` 和 `wrg -i vbmetasystem`
> 是同一个键，`system_image_defaults` 这种带 `_` 的名字也照样命中。

**上下文行（`-A` / `-B` / `-C`）**：照 grep / rg 的惯例 ——

- 命中行还是 `文件:行号:原文`（照样高亮）；
- 上下文行是 **`文件-行号-原文`**（两个冒号变减号），**不上色**；
- 不相邻的两块之间打一行 `--`；重叠 / 相邻的块会**合并**（同一行只打一次、也不多打 `--`）；
- 只影响显示：**命中判定、排序、退出码都不变**（`-C 0` 等于不写）。

```sh
wrg system_image_defaults -A3
# ./build/make/target/product/generic/Android.bp:463:    name: "system_image_defaults",
# ./build/make/target/product/generic/Android.bp-464-    module_type: "android_filesystem_defaults",
# ./build/make/target/product/generic/Android.bp-465-    config_namespace: "ANDROID",
# ./build/make/target/product/generic/Android.bp-466-    bool_variables: ["TARGET_ADD_ROOT_EXTRA_VENDOR_SYMLINKS"],
# --
# ./build/make/target/product/generic/Android.bp:481:    name: "system_image_defaults",
# ./build/make/target/product/generic/Android.bp-482-    partition_name: "system",
# ...
```

**只出文件 / 只数条数 / 限量 / 多名字**：

```sh
wrg -l systemimage             # ./build/make/core/Makefile
wrg -c systemimage             # ./build/make/core/Makefile:5
wrg -t bp -i image_defaults    # 只在 Android.bp 里模糊找
wrg -e systemimage -e vbmeta -m 3   # 两个名字取并集，全局最多 3 条命中
wrg -- -weird                  # -- 之后一律当查询串
```

**搜索后端**（按顺序探测，前一个没有才用下一个）：

| 顺序 | 后端 | 说明 |
|---|---|---|
| 1 | `rg`（ripgrep） | 最快；三类文件各搜一次（Makefile 那类用 `--type amake --type make`）再合并，最后统一判命中 |
| 2 | `fd`（`fdfind` → `fd-find` → `fd`，探到哪个用哪个） | `fd` 列文件、`awk` 判命中 |
| 3 | `find` | 兜底：没有 rg / fd 时就是它，行为与本项目以前的版本**逐字一致** |

- `WRG_SEARCH=auto`（默认）/ `rg` / `fd` / `find`：**指定了就一定用它** ——
  那个可执行文件不在 `PATH` 里就报错、返回 **2**，不会偷偷换成别的；
- ⚠️ **`rg` / `fd` 会跳过隐藏目录和被 ignore 的目录**（`.repo/`、`out/` 这类），`find` 不会 ——
  所以前两条快得多，但那两个目录里的目标搜不到；
  要"连 `.repo/` 一起搜"（找回 `find` 的老行为）就用 `WRG_SEARCH=find`。
- 三条后端 + 两个 shell 的输出**逐字一致**（测试里用 `cmp` 钉着）。

**高亮**：命中的**目标名**分两段上色，行内其它字符（`name: "` / `",` / `.PHONY: ` 这些）不着色：

- **输入匹配到的那一段** → **加粗红**（精确 = 整个目标名；模糊 = 名字里命中的那一段）；
- **目标名里其余（没匹配到的）部分** → **绿、不加粗** —— `wrg -i ystemim` 命中
  `systemimage` 就是 `s`（绿）+ `ystemim`（加粗红）+ `age`（绿）；
- 绿段**只在模糊模式**里有：精确匹配命中的就是整个名字，没有"其余部分"；
  模糊下同一个子串在一个名字里出现多次时，**只有第一处**是红粗，后面的算"没匹配到"（绿）；
- 管道 / 重定向里不含任何颜色码。

- `--color=auto` / `always` / `never`：**这一次运行**的开关（写命令行上）；不写就看 `WRG_COLOR`；
- `WRG_COLOR=auto`（默认：只在 stdout 是终端时上色）/ `always` / `never`；
- `NO_COLOR` **非空**时不上色 —— 它压得过 env 里的 `WRG_COLOR=always`，
  但**压不过命令行里显式写的 `--color=always`**（和 ripgrep 的语义一样）；
- `WRG_COLOR` / `--color` 写错了 → 报错、返回 2。

- `-h` / `--help` / `-v` / `--version`：打 stdout 并返回 0；
- 参数不对 / 选项不认识 / 缺值 / 位置参数不止一个：用法打到 stderr，返回 **2**；
- 当前目录树下没有（选中的那几类）文件：stderr 打
  `wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile`，返回 1
  （`-t bp` 时就只说 `Android.bp`；`Makefile.am` / `Makefile.in` 不算这三类）；
- 有这些文件但没有命中：stderr 打 `wrg: 没有匹配 '<模式>' 的目标名`，返回 1。

```sh
wrg libfoo           # ./foo/Android.mk:3:LOCAL_MODULE := libfoo    ← libfoo 标红加粗
wrg -i app           # ./bar/Android.bp:7:    name: "BarApp",       ← App 标红加粗、Bar 绿
                     # ./foo/Android.mk:8:LOCAL_PACKAGE_NAME := FooApp
                     #                                          ↑ Foo 绿
wrg systemimage      # ./build/make/core/Makefile:924:.PHONY: systemimage
                     # ./build/make/core/Makefile:925:systemimage:  ← systemimage 标红加粗（精确：没有绿段）
wrg -i ystemim
                     # ./build/make/core/Makefile:924:.PHONY: systemimage
                     #                          ↑ s 绿、ystemim 标红加粗、age 绿
                     # ./build/make/core/main.mk:1383:.PHONY: vbmetasystemimage
                     #                                  ↑ vbmetas 绿、ystemim 标红加粗、age 绿
wrg -i vbmeta_systmmm
                     # 用户输入vbmeta_systmmm
                     # 实际匹配vbmetasyst
                     # 匹配目标名如下：
                     # ./build/make/core/main.mk:1383:.PHONY: vbmetasystemimage
                     # ./build/make/core/main.mk:1384:vbmetasystemimage: …
                     #                          ↑ vbmetasyst 标红加粗、后面的 emimage 绿
wrg systemimage -A3
                     # ./build/make/core/Makefile:924:.PHONY: systemimage
                     # ./build/make/core/Makefile:925:systemimage:      ← 相邻的两个命中并成一块
                     # ./build/make/core/Makefile-926-                  ← 上下文行：减号、不上色
                     # ./build/make/core/Makefile-927-# ------------------------------
                     # --
                     # ./build/make/core/Makefile:3623:systemimage: $(INSTALLED_SYSTEMIMAGE_TARGET)
                     # ...
```

> 注释里的目标名（`# LOCAL_MODULE := xxx`）不算；精确匹配不认前缀
> （`wrg lib` 不会命中 `libfoo`）；目标名里的 `.` `+` 这类符号按**字面量**算
> （`wrg 'liba+b'` 不会命中 `libaaab`）。
>
> Makefile 里这几类**不算**目标名：赋值（`VAR := x`、`VAR ?= x`、`export A := b`）、
> `ifeq (...)` / `include $(...)` 这种带 `$` 的行、`$(MKTARGET): dep` 这种目标里带 `$` 的规则行、
> `# 注释: 里的冒号`。`Android.mk` 只按 `LOCAL_MODULE` / `LOCAL_PACKAGE_NAME` 认，
> 它里面的规则行**不算**（否则同一个目标会被两套语义各算一遍）。
>
> **recipe 行与字符串也不算**（这条是 2026-10-07 修的假阳性，真 AOSP 上撞到过）：
> 以 **TAB 开头**的行一律不算（Makefile 的 recipe 必须 TAB 缩进），
> 目标列表（冒号前那段）里出现 **`"` / `'`** 的也不算 ——
> 所以 `	@echo "Target system fs image: $(1)"` 和空格缩进的
> `  @echo "Install system fs image: $@"` 都不会再被当成定义了 `system` 这个目标
> （前者靠 TAB、后者靠引号；两行都照抄自 `build/make/core/Makefile`）。
> **已知残留**：`$(error ...)` / `$(warning ...)` 这种跨行字符串的**续行**里如果是一句
> 散文（例：`     Prebuilt apk found in PRODUCT_COPY_FILES: $(1), …`），
> 里面的 `apk` / `found` 这类词仍会被当成目标名 —— 要挡掉它得知道"上一行是不是续行"，
> 而 `rg` 那条路是**按行**拿结果的、看不到上一行，加了这条规则三条后端就对不齐了
> （真 AOSP 实测：`wrg apk` 会命中那一行；`reportmissinglicenses` 这种真目标不受影响）。

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
| `WIN_IP` | 非 WSL 上 `win` 的地址来源 | **必须自己设**（`export WIN_IP=<本机对外的地址>`）。本命令**不做 `ip addr` 探测**：阿里云那种机器探到的是内网地址 |
| `WTOOL_SMB_CONF` | 非 WSL 上 `win` 读哪个 samba 配置 | 默认 `/etc/samba/smb.conf`；测试用它注入假配置，不碰系统文件 |
| `WRG_SEARCH` | `wrg` 用哪个搜索后端 | `auto`（默认：按 rg → fdfind/fd-find/fd → find 探测）/ `rg` / `fd` / `find`。指定了就必须存在，否则报错返回 2 |
| `WRG_COLOR` | `wrg` 高亮开关的**默认值** | `auto`（默认：只有 stdout 是终端才上色）/ `always` / `never`。命令行上的 `--color=…` 优先于它；写错返回 2 |
| `NO_COLOR` | 通用约定，非空就关色 | 压得过 `WRG_COLOR=always`，但压不过命令行上显式的 `--color=always` |
| `WRG_PAT` / `WRG_FUZZY` / `WRG_PASS` / `WRG_KINDS` / `WRG_BEFORE` / `WRG_AFTER` / `WRG_COLOR_ON` | `wrg` 内部传给 awk 的查询串、模式开关、pass 名、认哪几类文件、上下文行数、上色开关 | 不是给人设的，别在 rc 里写 |

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
| `win: 没设 WIN_IP（本命令不自动探测 IP …）。` | 非 WSL 上没配地址。在 `.bashrc` / `.zshrc` 里 `export WIN_IP=<本机对外的地址>`（不探测是有意的：服务器上 `ip addr` 给的多半是内网地址） |
| `win: 读不到 samba 配置 /etc/samba/smb.conf` | 这台机器没装/没配 samba。要么装上并配 `[share]` + `path =`，要么临时 `WTOOL_SMB_CONF=<别的文件>`；scp 那一行照样会给 |
| `win: /etc/samba/smb.conf 里没有 share 的 path 匹配 <目标>` | 当前目录不在任何 share 的 `path` 下面（或 share 的 path 写的是软链/相对路径）。`testparm` 看一眼 samba 实际认的 path；scp 那一行照样会给 |
| `win` 在非 WSL 上只打了 scp 一行、返回 1 | 这就是"samba 那半没算出来"，看上面两条的 stderr；scp 行是可以直接用的 |
| `wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile`（返回码 1） | 站错目录了（`wrg` 只看当前目录往下）；`cd` 到源码树根部再跑。用 rg / fd 时它们跳过的目录（`.repo/`、`out/`）里即使有也不算。只有 `Makefile.am` / `Makefile.in` 的树也算"没有"（它们不在文件集合里） |
| `wrg: 没有匹配 'xxx' 的目标名`（返回码 1） | 精确模式要求名字完全一样（区分大小写）；想按片段找就 `wrg -i 片段`。Makefile 里只认**目标名**：赋值（`VAR := x`）、`ifeq`、依赖列表里的名字都不算 |
| `wrg -i` 打出了 `用户输入… / 实际匹配… / 匹配目标名如下：` 三行 | 这是**有意**的：查询串从尾部截断过（实际匹配的前缀比你输入的去 `_` 版本短），告诉你它到底拿什么去搜的。正常命中不带这三行 |
| `wrg -i` 明明"看着像"却报没有匹配 | 只会从**尾部**截断，最短试到 4 个字符：`vbmzzzzzz` 只剩 `vbm`（3 个字符）就不再往下试了。开头/中间写错救不了，换个写法或者用精确匹配 |
| `wrg -i` 命中了一堆不相干的名字 | 模糊匹配是"归一化后**含**这个前缀"，前缀越短命中越多；表头第三行下面按路径+行号排，用 `grep` 再筛一道 |
| `wrg` 在 Makefile 里搜 `systemimage_intermediates` 没结果 | 它多半是**变量**（`systemimage_intermediates :=$= …`）而不是目标 —— 赋值按规则就不算目标名 |
| `wrg apk` 命中了 `Prebuilt apk found in PRODUCT_COPY_FILES: …` | 已知残留的假阳性：那是 `$(error …)` 跨行字符串的续行，按行看不出它是散文（详见上面「recipe 行与字符串也不算」那段）。真目标名（如 `reportmissinglicenses`）不受影响 |
| `wrg` 搜不到 `.repo/` 或 `out/` 里的目标 | 默认后端是 rg / fd，它们跳过隐藏目录与被 ignore 的目录。要连这些一起搜：`WRG_SEARCH=find wrg 名字` |
| `wrg: WRG_SEARCH=rg 但 PATH 里没有 rg`（返回码 2） | 强制指定了 `rg` 却装没装/不在 PATH 里。装 ripgrep，或者 `WRG_SEARCH=auto` 让它自己挑 |
| `wrg: WRG_SEARCH=fd 但 PATH 里没有 fdfind / fd-find / fd`（返回码 2） | 同上：装 `fd-find`（Ubuntu 里可执行名是 `fdfind`），或改回 `auto` |
| `wrg: WRG_SEARCH 只认 auto / rg / fd / find（现在是 xxx）`（返回码 2） | 变量值拼错了（打错不会静默退回默认） |
| `wrg: WRG_COLOR 只认 auto / always / never（现在是 xxx）`（返回码 2） | 同上 |
| `wrg: --color 只认 auto / always / never（现在是 xxx）`（返回码 2） | 命令行上的 `--color=` 值拼错了；`--color` 后面没跟值也会 rc 2 |
| `wrg: 选项 -A 缺值`（返回码 2） | `-A` / `-B` / `-C` / `-m` / `-e` / `-t` / `--color` 后面没跟值（选项写在最后了）。补上值：`-A 3` 或 `-A3` |
| `wrg: -A/--after-context 需要一个非负整数（现在是 xxx）`（返回码 2） | `-A/-B/-C/-m` 的值只能是非负整数（不认 `-A -1`、`-A x`） |
| `wrg: 只认一个查询串（多出来的：x；多个名字请用 -e）`（返回码 2） | 位置参数给了两个以上（`wrg a b`）。多名字要写成 `wrg -e a -e b` |
| `wrg: -t/--type 只认 bp / mk / make（现在是 xxx）`（返回码 2） | `-t` 的类型拼错了；逗号分隔的每一项都要是这三个之一 |
| `wrg -A3` 打出来的 `--` 是什么 | grep / rg 的块分隔符：两块不相邻的命中之间才有；重叠 / 相邻的块会合并，合并处不打 |
| `wrg -A3` 里的上下文行为什么没有颜色 | 有意如此：只有命中行着色，上下文行（`文件-行号-原文`）永远是纯文本 |
| `wrg -t make 名字` 搜不到 Android.mk 里的目标 | `-t make` 只表示"其它 Makefile"（`Makefile` / `*.mk` / `*.mak` …）；Android.mk 属 `-t mk` 那一类，两类都要就 `-t mk,make` |
| `wrg` 在管道 / 重定向里没有颜色 | 这是有意的：`WRG_COLOR=auto` 只在终端上色。要强制就 `WRG_COLOR=always`（`NO_COLOR` 非空时得用 `--color=always`） |
| `wrg` 在终端里也没有颜色 | 看 `echo $NO_COLOR` —— 非空就不上色（env 的 `WRG_COLOR=always` 也压不过它；命令行 `--color=always` 可以） |
| 敲 `gs` 说 command not found | 这个 shell 的 rc 里没有 wtool 块 —— 项目没装，或者装完没重开 shell（`exec $SHELL`） |

## 测试

```sh
bash tests/env_test.sh     # rg + fd 都装了：499 通过 / 2 失败（那 2 条是 win 的老毛病，见下）
                           # —— 条数随环境变（后端在不在、shell 在不在），以输出为准
                           # 没装 zsh 就只测 bash（会打印跳过）
```

> ⚠️ 本机（WSL）上 `win | head -1` 那两条会因为 `head` 提前关掉管道、`echo` 报
> `write error: Broken pipe` 而 FAIL（**和 wrg 无关、改动前就在**）；容器里
> （`wrg-test`，非 WSL、没有 `ip`、mawk）同一份用例是 **497 通过 / 0 失败**。

它把**同一张用例表**喂给两个 shell：别名在不在、`_up_to_have_dir` / `cw` 能不能找到
`.repo`、`pdd`/`pss` 能不能跳回来、`start` 的补全注册、`win` 的 WSL 分支**逐字等于**
`wslpath -w .`、`win` 的服务器分支（用假 `smb.conf` + `WIN_IP` 注入，最长前缀/路径边界/
三种报错各一条）、以及 WSL 探测函数在**当前这台机器**上给不给对的返回码
（本机是 WSL 就按 WSL 断言，不写死）。

`wrg` 那一段是重点：老行为（精确/模糊/注释/空目录/用法）之外，还比
**三条后端在同一个夹具上的输出逐字一致**（`WRG_SEARCH=auto|fd|rg` vs `find`，`cmp` 比对，
精确 + 模糊两种模式，模糊那条还带"截断表头"）、元字符当字面量（`liba+b` 不命中 `libaaab`，
`-i 'libc.d'` 不命中 `libcxd`）、每条后端的
"没有命中 / 树下没有这三类文件 / 只有 `Makefile.am` 也算没有 / 只有 `Makefile` 也搜得到"、
后端探测顺序（用只有一个可执行名的假 `PATH`）、
强制指定但可执行不存在（rc=2）、高亮（管道里 `grep -c ESC` = 0、`WRG_COLOR=always` 的
精确字节、模糊只包住"实际匹配"的那一段、`NO_COLOR` 压过 `always`、pty 下自动上色）、
以及"隐藏目录里 rg/fd 搜不到、find 搜得到"这条语义差异；
再加五组 2026-10-07 新钉的：**假阳性**（`$T/src4`：TAB/空格缩进的 recipe、`define` 体、
`$(info …)`、注释、`VAR :=`、`export A :=`、TAB 缩进的目标形状行 —— 每条都精确 + 模糊
各断言一遍"不命中"，同时断言真目标照旧命中、输出里 `grep -c '@echo'` = 0）、
**新模糊算法**（`$T/src5`：截断到 `vbmetasyst` 的三行表头逐字、表头第一行保留用户写的 `_`、
`_` 归一等价、正常命中不打表头、下界 4（`vbmzzzzzz` 不命中、`vbme` 命中）、
`vbm` 这种不足 4 个字符的查询整个试、结果与三后端 `cmp` 一致）和
**分两段着色**（`$T/src6`：`-i ystemim` 四行的完整 ANSI 字节 —— 匹配段在中间（前后都绿）、
同一子串出现两次时只有第一处红、匹配段正好在结尾时没有后段绿码；外加"精确模式整名红粗、
一个绿码都没有"、"模糊整名命中也没有绿段"、管道零 ANSI、`NO_COLOR` 压过 `always`、
auto / rg / fd 与 find 的着色输出逐字一致）、
**选项位置自由 + 新选项**（`wrg -A1 -i ctx` / `wrg ctxa -i` / `wrg -B 2 -i ctx` /
`wrg -A 2 ctx -i` 都对着字面量比、`-il` / `-ilA1` 捆绑、`-tbp` 贴值、`--type=bp`；
`--` 结束符（`wrg -- -weird`、`wrg -- --help` 当查询串不打用法）；缺值 / 未知选项 /
多个位置参数都是 rc 2 + 报错；`-t` 只看 `bp`/`mk`/`make` 中的一类（用三类同名的
`mkshared` 钉）、`-l` / `-c` / `-lc` / `-m` / `-e` / `--regexp` 各自的字节；
`--color=always` 压过 `NO_COLOR`、env 的 `WRG_COLOR=always` 被 `NO_COLOR` 压过
（方向相反的两条）、`-h` / `-v`）和
**上下文行**（`$T/src7`：`-A1` / `-B1` / `-C2` 三份逐字节期望值、`-C2` 的重叠块合并
（`sort | uniq -d` 为空、总行数 15）、`--` 条数、值分开/贴合等价、后写覆盖先写、
`-C0` 等于不写、只影响显示不改退出码、跨文件也打 `--`、上下文行永不着色、
三后端 `cmp`（纯文本 + 着色））。

> 用例表是共用的，**每加一条两个 shell 都会跑**；后端相关的用例按"本机有没有那个
> 可执行文件"跳过，所以数字会随环境变 —— 以脚本最后打印的那一行为准
> （2026-10-07 加这一批之前是 299 通过 / 2 失败）。

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
