# shell/zsh —— wtool 里那个 zsh

这是 **zsh 的源码**（上游 [zsh-users/zsh](https://github.com/zsh-users/zsh) 的 fork），
在 **docker 里按发行版各编一份**，装完之后 `zsh` 这条命令就是它。

```sh
wtool build   shell/zsh      # 三个发行版各编一份（容器里编，宿主要装 docker）
wtool install shell/zsh      # 把**本机这个发行版**那一套装上 → $WTOOL_HOME/usr/bin/zsh
zsh --version                # zsh 5.9.2 (x86_64-pc-linux-gnu)
```

装 / 卸都由 wtool 按 `wtool.xml` 的声明执行，仓库里没有 `install.sh` 那种入口 ——
入口只有 `wtool install` / `wtool uninstall`。

---

## 1. 为什么是"一份源码、三个发行版各编一份"

**不是洁癖，是硬约束**：zsh 是 C 程序，编出来的二进制**要求某个最低 glibc 版本**，
而 glibc 是**向前**兼容、**不向后**兼容的。实测（2026-10-14，容器里量的）：

| 构建用的系统 | 编出来的二进制要求 | 跑在 22.04（2.35） | 24.04（2.39） | 26.04（2.43） |
|---|---|---|---|---|
| `ubuntu:22.04`（glibc 2.35） | `GLIBC_2.35` 一级 | ✅ | ✅ | ✅ |
| `ubuntu:24.04`（glibc 2.39） | **`GLIBC_2.38`** | ❌ `version 'GLIBC_2.38' not found` | ✅ | ✅ |
| `ubuntu:26.04`（glibc 2.43） | `GLIBC_2.43` 一级 | ❌ | ❌ | ✅ |

所以 **24.04 上编的那一份，拿到 22.04 上是起不来的** —— 而 `$WTOOL_HOME/usr/bin`
排在 `PATH` 最前面，装错的那一份就是你**下一个登录 shell**。这就是"三套产物"的全部理由。

**"要求 GLIBC_x.yz" 怎么自己量**（三行，不用猜）：

```sh
objdump -p <产物>/bin/zsh | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1
ldd --version | head -1                     # 这台机器有哪个 glibc
<产物>/bin/zsh --version                    # 在目标机器/容器里真跑一次
```

## 2. 三个发行版产物怎么选

产物做出来之后，磁盘上是这样（`__output/` 不进 git）：

```
shell/zsh/__output/
├── ubuntu_22.04/main/payload/usr/{bin,lib,share}/…     ← 引擎从容器层导出来的（真身）
├── ubuntu_24.04/main/payload/usr/…
├── ubuntu_26.04/main/payload/usr/…
├── ubuntu_22.04/usr -> main/payload/usr                ← 别名链（每条都相对，可搬）
├── ubuntu_24.04/usr -> main/payload/usr
├── ubuntu_26.04/usr -> main/payload/usr
└── usr             -> ubuntu_24.04/usr                 ← **本机选中的那一套**
```

`wtool.xml` 里写的是 `<export_usr src="__output/usr"/>` —— 那条不带发行版名字的
**选择链**。为什么要有它：引擎的 `src=` 是**静态**的，它不会按发行版替换路径，
所以"装哪一套"必须由链来回答（见 §6 的待决定）。

**选本机那一套**，一条命令（它同时会补上三条别名链）：

```sh
sh scripts/build.sh          # 宿主上跑：wtool build → 建别名链 → 选本机那套 → 自检
```

只想重选一次（产物已经在磁盘上、不想重编）：

```sh
ln -sfn ubuntu_24.04/usr __output/usr      # 把 24.04 换成你那个发行版
```

⚠️ **选中了错的发行版不会当场报错**，要到 `wtool install` 才拦：
`scripts/install.sh` 会核对"选中的那一套 = 本机发行版"，不对就**报错并停**，
并给出上面那条 `ln -sfn`。宁可装不上，也不要留一个起不来的登录 shell。

## 3. 构建：容器里发生了什么

`wtool build shell/zsh` 会按 `build/targets.tsv` 里那三个目标各起一个容器，
每个容器跑一遍 `scripts/build.sh --in-docker --target=ubuntu_<版本>`：

1. **换 apt 源到 http**（`mirrors.ustc.edu.cn`）—— 基础镜像里**没有 CA**，https 源会失败；
2. 装构建依赖（实测**必需**的这几个）：
   `build-essential`（gcc/make）、`autoconf`、`libncurses-dev`、`xz-utils`、`ca-certificates`；
   * `libncurses-dev` 少了 → `configure: error: "No terminal handling library was found"`
   * `autoconf` 少了 → `./configure: not found`（git 检出里**没有** `configure`，
     上游只在 release tarball 里带；本仓用 `Util/preconfig` 现生成）
3. 把源码从只读的 `/proj` 拷到 `/src`；
4. `./configure --prefix=$(cat build/prefix-placeholder)` —— **编译期前缀是一个够长的
   占位符**（`/w/zsh-placeholder-…/usr`），不是 `/root/.wtool/usr`；
5. `make` → `make install.bin install.modules install.fns` → 把装到占位前缀的那棵树
   搬进容器里的 `/root/.wtool/usr`（引擎只导出这棵）；二进制里**仍然**是占位前缀；
6. 在容器里立刻自检一次（占位前缀在不在、`module_path[1]` 是不是它、`zsh --version` /
   `ldd` / glibc 门槛 / 体积），然后引擎
   `docker commit` → `__layer/<target>/`（OCI 布局）→ 导出 `__output/<target>/main/payload/`。

一次目标大约 **1.5 分钟**（32 核，`make -j32`）；三个目标串行约 5 分钟。
装完之后产物**只有 `/root/.wtool/usr` 这一棵子树** —— 源码和 `.o` 中间物留在 `/src`，
**不进产物**（引擎的导出规则只取容器里 `root/.wtool/*`）。

### configure 的那几个开关（都有理由，别顺手删）

| 开关 | 为什么 |
|---|---|
| `--prefix=$(cat build/prefix-placeholder)` | **不是** `/root/.wtool/usr`：编进二进制的是 256 字节占位前缀，安装时 `install.sh` 再把它缩成真实的 `$WTOOL_HOME/usr`（H38）。`make install` 装到占位目录后再搬到 `/root/.wtool/usr`，所以引擎看到的形状不变。占位前缀够长，短目标用 NUL 补齐；目标路径超过 256 字节会**装不了**（报错，不会装坏） |
| `--disable-cap` | 否则二进制会**硬依赖 `libcap.so.2`**，而 `ubuntu:26.04` 基础镜像里**没有它**（实测：22.04/24.04 有，26.04 没有）。zsh 的 cap 支持只给 `zsh/cap` 模块用，日常用不到 |
| `--disable-gdbm` / `--disable-pcre` | 这两个库的**默认值本来就是 off**，写出来是为了"哪天被默认值改了"能一眼看见，而不是靠运气 |

### 不装的东西（也是实测踩出来的）

* **man 页不装**：`make install` 会连带 `install.man`，而它要 `yodl` 生成
  `Doc/zsh*.1` —— 容器里没装 yodl，会卡在 `test -s zsh.1 || exit 1`，**整个 install 失败**。
  更要紧的是：man 会落在 `$PREFIX/share/man`，而 `$WTOOL_HOME/usr/share/` 是
  **所有项目共享**的 —— `<export_usr>` 会把 `share/man` 也当成一个条目导出去，
  于是 `$WTOOL_HOME/usr/share/man` 整条被这个项目占住，**盖住别人**。
  要 `man zsh` 就用系统装的那个 zsh 的 man 页。

## 4. 装完之后

```
$WTOOL_HOME/usr/bin/zsh        → …/__output/usr/bin/zsh（软链，指向下面那棵树的真身）
$WTOOL_HOME/usr/lib/zsh        → …/__output/usr/lib/zsh        （36 个 .so 模块）
$WTOOL_HOME/usr/share/zsh      → …/__output/usr/share/zsh      （functions / scripts / site-functions）
```

* `$WTOOL_HOME/usr/bin` 由**引擎统一放在 `PATH` 最前**，所以敲 `zsh` 就是它；
  想看系统那个：`command -v zsh` 之后直接敲绝对路径 `/usr/bin/zsh`。
* **`fpath` / `module_path` 现在由安装期二进制补丁修好**：`configure --prefix` 编进去的是
  占位前缀，`scripts/install.sh` 在引擎建完 L2 链之后把它换成真实的 `$WTOOL_HOME/usr`
  （sidecar 记着占位符/当前前缀，重复安装不重复打、换路径能再打、卸载会还原）。
  所以 **`zsh -f`（不读任何 rc）也能加载动态模块、fpath 也对**。
  `env.zsh` 里那段 `fpath`/`module_path` 仍然保留，是给旧二进制/交互式兜底，见 §6。
* **env 块仍然是第一块**（根元素 `priority="1"`），但理由变了：二进制补丁之后新产物
  不再依赖它；保留是给**旧二进制**（升级前装的 / 整机包里还没重装的）。旧产物上
  `wtool-base-tools`（priority 5）的 `zmodload`、oh-my-zsh（10）的 `compinit` 会抢在前面
  报一屏 `failed to load module`（实测踩过，见 `wtool.xml` 注释）。
* 这个项目**不碰你的 `$HOME`**，也不改 `~/.zshrc`：那条 `source ${WTOOL_HOME}/env.zsh`
  是你自己加的（引擎会提示，但**不代写**）。

### 装完怎么验（**别省这一步**）

```sh
zsh --version                      # 有输出
zsh -ic 'echo INTERACTIVE_OK'      # 交互式真能起（-i = 读 rc，模拟登录 shell）
zsh -f -c '[[ x =~ x ]] && echo REGEX_OK'   # H38：-f 不读 rc，测二进制里的 module_path
```

**起不来就立刻撤**：`wtool uninstall shell/zsh`（撤掉的是那 3 条链，产物还在磁盘上）。

## 5. 上游 / 这份 fork 改了什么

上游文档（`README`、`INSTALL`、`Doc/`、`ChangeLog`…）**一个字没动** —— 这是 fork，
要保留上游可辨识度。本仓**新增**的东西：

| 新增 | 是什么 |
|---|---|
| `wtool.xml` | 项目声明：`kind="docker"`、两行 env、`<export_usr src="__output/usr"/>` |
| `build/targets.tsv` | 三个目标系统 → 基础镜像 / 代号 / glibc（引擎读前两列） |
| `build/layers.tsv` | 层清单：一层 `main`，容器里跑 `scripts/build.sh --in-docker` |
| `build/export.filter` | 导出过滤（今天没有额外规则，它存在本身是契约） |
| `scripts/build.sh` | 容器里的构建步骤；宿主上跑 = 一条命令做完 build + 选发行版 |
| `scripts/install.sh` | **验收**：选中的那一套必须是本机的、能跑、不缺共享库 |
| `env.zsh` / `env.bash` | shell 集成（重设 `fpath` / `module_path`；两份逐字等价） |
| `README.md` / `AGENTS.md` / `architecture.md` / `BACKLOG.md` | 这套文档 |
| `.gitignore` 末尾一段 | 忽略 `__output/` `__layer/` `__release/` `wtool.local.xml` |

**基线是上游 tag `zsh-5.9.2`**（不是 `master`）—— 登录 shell 用发行版，不用开发快照。
改上游源码时的规矩见 `AGENTS.md`。

## 6. 已知限制 / 待决定

* **`<export_usr src=>` 是静态的**：引擎不会"按本机发行版自动挑 `__output/ubuntu_<ver>/`"。
  今天靠 `__output/usr` 这条选择链绕过（§2）。**这是 ADR-0045 里还开着的 Q5**
  （"要不要让 `install` 自己挑最接近的一套 / 要不要同时保留 `__output/usr`"）——
  引擎一旦实现，这里就能少一条链。
* **`download-release` + `unpack-release` 那条路**：`release.zip` 里装的是产物树，
  换台机器解出来之后**还是要选一次**（`ln -sfn … __output/usr`）。
  发布侧的对照表（`scripts/release.json`）还没做 —— 见 `BACKLOG.md`。
* **不给别的发行版**（Debian / Fedora / Alpine）：只做 Ubuntu 22.04 / 24.04 / 26.04，
  往 `build/targets.tsv` 加一行就多一个（`scripts/build.sh` 会自动带上它）。
* **产物没 strip**（11 MB / 1274 个文件）。要小可以 `make install-strip`，但那会改掉
  产物的形状与可比性 —— 留给 `BACKLOG.md` 里那条待办。
* ⚠️ **本仓顶层有上游的 `Scripts/`，我们加了 `scripts/`** —— 在
  **大小写不敏感**的文件系统（macOS 默认、Windows）上这两个会撞。
  引擎的契约写死了 `scripts/{build,install}.sh`（`wtool.sh` 的 `wt_project_script`），
  所以这条改不了，只能在 README 里说清楚：**别在大小写不敏感的盘上 clone 本仓**。

### ✅ 模块路径：`zsh -f` / 脚本也能拿到模块（2026-10-26 起）

zsh 把 `--prefix` 编进二进制，`module_path` / `fpath` 的**初值**就是那个路径；
而 `MODULE_PATH` **不允许从环境导入**（`Src/params.c` 的 `PM_DONTIMPORT`，注释
*"MODULE_PATH is not imported for security reasons"*）。只靠 `.zshenv` / `env.zsh`
修不了 `zsh -f`（`-f` 不读任何 rc）—— 这就是 H38。

**现在的做法**（不是包装脚本，理由见下面）：构建期用 256 字节的占位前缀
（`build/prefix-placeholder`）代替真实路径，安装期由 `scripts/lib/patch-prefix.py`
在 ELF 的 NUL 字符串里就地替换成 `$WTOOL_HOME/usr`：

* 替换时把「占位符 + `/lib/zsh/5.9.2` 这类后缀」当**一整段**缩，NUL 补在这段末尾；
  直接 `replace(占位符, 目标)` 会把后缀截掉（实测过，模块路径会变成 `$WTOOL_HOME/usr/zsh/…`）。
* sidecar 在 `__output/usr/lib/zsh/.zsh-wtool-patch`：记占位符、当前前缀、改过的文件。
  重复 install 同一路径 **不重复打**；换 `$WTOOL_HOME` 再 install 会按 sidecar 再打一次；
  `wtool uninstall` 会**还原成占位符**（产物回到可重定位状态）。
* 判据（`scripts/install.sh` ④ 每次都跑，清了 `FPATH`/`ZDOTDIR` 测的是编译期路径）：

```sh
zsh -f -c 'print -r -- $module_path[1]'          # → $WTOOL_HOME/usr/lib/zsh/<ver>
zsh -f -c '[[ x =~ x ]] && echo REGEX_OK'        # → REGEX_OK（要真的匹配才返回 0！）
zsh -f -c 'zmodload zsh/parameter && echo MOD_OK' # → MOD_OK
zsh -f -c 'print -rl -- $fpath' | grep -Fx "$WTOOL_HOME/usr/share/zsh/<ver>/functions"
```

⚠️ 用户最初给的验收命令是 `[[ x =~ y ]] && echo REGEX_OK` —— **`x` 不匹配 `y`**，
在正确的 zsh 上也是 rc=1、不打印 `REGEX_OK`。修好后的判据是「**stderr 为空** + rc=1」；
要看到 `REGEX_OK` 必须写成 `[[ x =~ x ]]`（`install.sh` 用的是后者）。

**为什么不选包装脚本**：包装器要在 exec 真身之前注入 `module_path`，但 `-c` 的代码不能
拼字符串（引号/多行会坏），只能 `eval` / `source` 包一层 —— 实测 `$0`/参数/行号/`-x`
轨迹都会变；而且**交互式 `zsh -f -i` 没有 `-c` 可注入**，`zsh -f -i` 里 `[[ x =~ x ]]`
仍然失败；登录 shell 的 `argv[0]`（`-zsh`）经过 shebang 包装器后由内核换成脚本路径，
包装器**没法知道**自己是登录 shell。二进制补丁保持原生二进制，这些语义全不变。

**代价（明确写在这里）**：

* 产物在 **install 之后与当时的 `$WTOOL_HOME` 绑定**（二进制里已经是那个绝对路径）。
  **移动 `.wtool` 之后要重跑 `wtool install shell/zsh --force`**（sidecar 会再打）；
  没重装就 `zsh -f` 会去旧路径找模块。
* `$WTOOL_HOME/usr` 的**字节长度上限是占位符的 256 字节**；超了 `install.sh` 直接报错
  （不会写坏二进制）。改占位符长度要同时改 `build/prefix-placeholder` 并重建。
* 只改**本机选中的那个 target** 的产物；`__output` 下另外两个发行版仍是占位符，等它们
  被选中安装时再打。`release.zip` / 整机包里带着 sidecar，目标机 install 会按自己的
  `$WTOOL_HOME` 再打一次，所以**功能上打包不要求先卸载**。
  ⚠️ 但 install 会改 `__output` 里的字节（二进制 + sidecar），**包内容就带上了本机的
  `$WTOOL_HOME`** —— 要在意"两次打包逐字节相同"，打包前先 `wtool uninstall shell/zsh`
  （或从干净 build 打包）让产物回到占位符。
* `zsh` 只是**动态模块加载**修好了；`--disable-dynamic` 仍然不采用（会丢 19 个模块，见
  `BACKLOG.md` Z-9 的历史记录）。
