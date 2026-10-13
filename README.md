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
3. 把源码从只读的 `/proj` 拷到 `/src`，`./configure --prefix=/root/.wtool/usr`；
4. `make` → `make install.bin install.modules install.fns`；
5. 在容器里立刻自检一次（`zsh --version` / `ldd` / glibc 门槛 / 体积），然后引擎
   `docker commit` → `__layer/<target>/`（OCI 布局）→ 导出 `__output/<target>/main/payload/`。

一次目标大约 **1.5 分钟**（32 核，`make -j32`）；三个目标串行约 5 分钟。
第 5 步之后产物**只有 `/root/.wtool/usr` 这一棵子树** —— 源码和 `.o` 中间物留在 `/src`，
**不进产物**（引擎的导出规则只取容器里 `root/.wtool/*`）。

### configure 的那几个开关（都有理由，别顺手删）

| 开关 | 为什么 |
|---|---|
| `--prefix=/root/.wtool/usr` | 容器里的**影子 `$HOME`**：引擎把 `root/.wtool/*` 剥两节导成 payload。`/root` 是容器的 `$HOME`，正好对上"换台机器 = `~/.wtool`"那个形状 |
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
* **`fpath` / `module_path` 必须在 `env.zsh` 里重设**：`--prefix` 是**编进二进制的
  绝对路径**（容器里那个 `/root/.wtool/usr`），而你机器上的 `$WTOOL_HOME` 十有八九
  不是同一个串。不重设的症状是"补全和行编辑像个残废 zsh"（模块 `.so` 一个都找不到）。
  `env.zsh` 从 `$WTOOL_HOME` 现算，绝不写死构建路径。
* ⚠️ **这个修复必须第一个生效**，所以本项目的 env 块是 `$WTOOL_HOME/env.zsh` 里的
  **第一块**（根元素 `priority="1"`）。理由：汇总里 `wtool-base-tools` 的工具块
  （priority 5）自己会 `zmodload zsh/parameter`、oh-my-zsh（10）会 `compinit` ——
  **谁排在我们前面，谁就报一屏 `failed to load module`**（实测踩过，见 `wtool.xml` 注释）。
* 这个项目**不碰你的 `$HOME`**，也不改 `~/.zshrc`：那条 `source ${WTOOL_HOME}/env.zsh`
  是你自己加的（引擎会提示，但**不代写**）。

### 装完怎么验（**别省这一步**）

```sh
zsh --version                      # 有输出
zsh -ic 'echo INTERACTIVE_OK'      # 交互式真能起（-i = 读 rc，模拟登录 shell）
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

### ⚠️ 模块路径：交互式一切正常，脚本里 `zmodload` 动态模块会失败

zsh 把 `module_path`（`$WTOOL_HOME/usr/lib/zsh/5.9.2`）**编进了二进制**，而它
**不从环境导入** —— `Src/params.c` 那条声明写着
`IPDEF8("MODULE_PATH", …, PM_DONTIMPORT|PM_RESTRICTED|PM_TIED)`，注释是
*"MODULE_PATH is not imported for security reasons"*（防止用环境变量注入恶意 `.so`）。
**实测**：`MODULE_PATH=/p/usr/lib/zsh/5.9.2 zsh -c 'print -l $module_path'`
打印的还是编译进去的 `/root/.wtool/usr/lib/zsh/5.9.2`。

后果（在容器里逐条量过，`WTOOL_HOME=/fakehome` 挂的是真产物）：

| 场景 | 结果 |
|---|---|
| 交互式 shell（读 rc → `env.zsh`）：`zle` / `compinit` / `zmodload zsh/stat` | ✅ 全 OK |
| 子进程 `zsh -c` 里 `autoload` 一个函数（靠 `env.zsh` 导出的 `FPATH`） | ✅ OK（`FPATH` 是**可以**从环境导入的） |
| 子进程 `zsh -c` 里 `zmodload zsh/stat`（不读 rc） | ❌ `failed to load module … /root/.wtool/usr/…` |
| **完全不读 rc 的 zsh**（`zsh -f` / 脚本）：`autoload -Uz compinit` | ❌ `compinit: function definition file not found`（我们的 functions 在 `$WTOOL_HOME/usr/share/zsh/…`，而编译进去的是构建时的路径） |

⚠️ 最后那条有个**现实后果**：`wtool-base-tools/tests/contract_test.sh` 里
「zsh 里 wtool 挂到了 _wtool」那一条就是拿 `zsh -f` 测的 —— **装过 shell/zsh 的机器上
`zsh` 就是本项目这份**，于是它 `PASS 312 FAIL 1`（`run_all.sh` 会在这一组停下）；
把系统 zsh 放前面（`PATH=/usr/bin:$PATH sh contract_test.sh`）就是 `PASS 313 FAIL 0`。
两条都实测过。**这不是 shell/zsh 坏了，是"测试假设 PATH 上那个 zsh 自带 functions"**，
引擎侧该修（`shell/zsh/BACKLOG.md` Z-11）。

**为什么不干脆 `--disable-dynamic`（把模块全静态链进去，那样就没有路径问题）** ——
量过了，**不划算**：zsh 有 **19 个只能动态构建的模块**（`Src/Modules/*.mdd` 里
`link=dynamic`），静态构建会把它们**整个丢掉**，包括 `zsh/stat`、`zsh/system`、
`zsh/zselect`、`zsh/files`、`zsh/mapfile`、`zsh/zpty`、`zsh/zprof`、`zsh/zftp`…
实测静态产物 9.0 MB / 0 个 `.so`：体积是小了 2 MB，但**功能少了一批**。
两害相权，保持动态构建 + 在 `env.zsh` 里现算路径。详见 `BACKLOG.md` Z-9。

