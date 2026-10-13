# architecture —— shell/zsh（现状）

> 只写**现在长什么样**：为什么这么定看 `harness/docs/adr/0045-wtool-redesign/`（D27 / §1.4 / §2.3），
> 接下来做什么看 `BACKLOG.md`。用户说明书是 `README.md`。
>
> ⚠️ 这份文件讲的是**这个项目**；引擎怎么驱动 `kind="docker"` 的构建是**引擎的现状**，
> 权威在 `harness/architecture.md` §4（`<build kind="docker">` 那一节）。两边冲突时以那边为准。

---

## 1. 这个项目是什么

**③ 类 docker 跨发行版构建项目**（`wtool.xml` 根元素 `kind="docker"`，ADR-0045 §1.4 / D49）：

* 内容是**上游 zsh 的源码**（fork 自 `zsh-users/zsh`，基线 tag **`zsh-5.9.2`**）；
* **要 build**（容器里编）、**要 `__layer`**（OCI 布局，可 push/pull）、**碰 `__output`**；
* 三个发行版各一套产物，**装机时按本机发行版挑一份**；
* 产物用 `<export_usr src="__output/usr"/>` 导成 3 条 **L2 链**（不是 `<link>`，D3 已删）。

判据（`README.md` §1 那张表就是它）：

```sh
grep -n 'kind="docker"'                wtool.xml   # 根元素：③ 类
grep -n '<build kind="docker"/>'       wtool.xml   # 怎么构建：docker
grep -nE '<(link|env|provision)([[:space:]>]|$)' wtool.xml   # 无输出（老标签一个都没有）
head -1 build/targets.tsv              # 注释行：三个目标系统的由来
awk '!/^#/ && NF {print NF}' build/layers.tsv   # 4 —— 层名/父层/镜像名/命令
```

## 2. 装完之后磁盘上是什么样

```
工作区 ~/self/wtool/shell/zsh/                     $WTOOL_HOME（今天 = ~/.wtool）
├── wtool.xml                                      ├── wtool/shell/zsh ──L1──► 工作区那份目录
├── build/{targets,layers}.tsv, export.filter      │     （env.zsh/build/*.tsv 从这里被读）
├── scripts/{build,install}.sh                     ├── usr/bin/zsh    ──L2──► …/__output/usr/bin/zsh
├── env.zsh / env.bash                             ├── usr/lib/zsh    ──L2──► …/__output/usr/lib/zsh
├── __layer/ubuntu_<ver>/    （OCI，gitignore）    ├── usr/share/zsh  ──L2──► …/__output/usr/share/zsh
└── __output/                （产物，gitignore）    ├── env.zsh / env.bash（各一节 wtool 块）
    ├── ubuntu_22.04/main/payload/usr/{bin,lib,share}   └── var/（账本：L1 链 + 3 条 L2 + 2 个 env 块）
    ├── ubuntu_24.04/main/payload/usr/…
    ├── ubuntu_26.04/main/payload/usr/…
    ├── ubuntu_<ver>/usr -> main/payload/usr        （别名链 ×3）
    └── usr             -> ubuntu_<本机>/usr        （**选择链** —— wtool.xml 认它）
$HOME 里：**什么都没有**（rc 里只有那两行 export + source，而且是你自己加的）
```

* **L2 落点是"条目"，不是目录**：`$WTOOL_HOME/usr/bin` 永远是**实体目录**（所有项目共享），
  里面一条一链（D7）。本项目占的条目是 `bin/zsh`、`bin/zsh-5.9.2`、`lib/zsh`、`share/zsh`。
* **`__output/` 的形状由引擎定**（`wt_layer_export`）：`<target>/<层名>/payload/…`，
  payload 是**相对影子 `$HOME`** 的路径 —— 所以是 `payload/usr/bin/zsh` 而不是 `payload/bin/zsh`。
  `<target>/usr` 和 `usr` 这两级**是 `scripts/build.sh` 加的别名链**，引擎不认识它们。
* L1 链是**绝对**路径（开发机指向工作区），L2 链是**相对**路径（`../../wtool/shell/zsh/__output/…`）。

## 3. 构建：谁在什么时候做什么

```
wtool build shell/zsh
  └─ 引擎（wtool.sh: wt_docker_build，按 build/targets.tsv 逐个 target）
       ├─ 每个 target 起一个容器：ubuntu:<版本> + -v <项目>:/proj:ro --network=host
       ├─ 在容器里跑 build/layers.tsv 里那一行：
       │     sh /proj/scripts/build.sh --in-docker --target={target}
       │       ① apt 换 http 源 → 装 build-essential/autoconf/libncurses-dev/xz-utils
       │       ② 源码 /proj → /src（排除 .git/__output/__layer/__release）
       │       ③ Util/preconfig（autoconf + autoheader）→ ./configure --prefix=/root/.wtool/usr
       │       ④ make -j → make install.bin install.modules install.fns
       │       ⑤ 容器里自检：zsh --version / ldd / glibc 门槛 / 体积
       ├─ docker commit → docker save | tar -x → __layer/<target>/（OCI）
       └─ 导成 __output/<target>/main/{payload,OWNED.tsv}（过 build/export.filter，丢白障）
sh scripts/build.sh          # 宿主上再跑一次（引擎编层 + 别名链 + 选本机那套 + 自检）
wtool install shell/zsh      # 引擎建 L1/L2 + env 块；然后跑 scripts/install.sh 验收
```

**三个 configure 开关的理由**（`--disable-cap` 是硬需求，另外两个是防默认值漂移）：

| 开关 | 实测理由 |
|---|---|
| `--prefix=/root/.wtool/usr` | 容器里 `/root` 就是 `$HOME` → 产物形状 = "换台机器就是 `~/.wtool/usr`" |
| `--disable-cap` | 否则硬依赖 `libcap.so.2`；**实测 26.04（resolute）基础镜像里没有这个库**，22.04/24.04 有 |
| `--disable-gdbm` / `--disable-pcre` | 默认本来就 off，写出来是防止默认值哪天变了 |

**不装 man**：`make install` 会连带 `install.man`，它要 yodl（没装）→ 整个 install 失败；
而且 man 会落 `$PREFIX/share/man`，被 `<export_usr>` 当成 `share` 的一个**条目**导出去，
`$WTOOL_HOME/usr/share/man` 整条就会被本项目占住（共享目录里最忌讳这个）。
所以显式列目标：`install.bin install.modules install.fns`，并 `rm -rf $PREFIX/share/man`
兜底（`Doc/install.man` 失败前会先 mkdir 出空目录，空目录一样会被导出）。

## 4. 三个发行版怎么选（**这是本项目最容易出错的一环**）

引擎的 `<export_usr src=…>` 是**静态字符串**，它不会按本机发行版挑目录
（`{target}` 替换只发生在 `build/layers.tsv` 的命令里）—— 这是 ADR-0045 里**还开着的 Q5**。
本项目用一条**选择链**绕过：

```
__output/usr -> ubuntu_<本机>/usr -> main/payload/usr        （两级，都是相对软链）
```

* 建链的人：`scripts/build.sh`（宿主模式）。它同时给三个发行版各建一条别名链。
* **选错不会在 install 之前报错**（链是相对软链，目标树确实存在）—— 所以
  `scripts/install.sh` 会核对：选择链指向的必须是 `/etc/os-release` 说的那个发行版，
  不对就 `exit 1` 并给出 `ln -sfn` 的修法；然后真跑一次 `zsh --version` 与 `zsh -c`，
  再看 `ldd` 有没有 `not found`。
* **为什么要在 install.sh 里拦**：`$WTOOL_HOME/usr/bin` 排在 `PATH` 最前，
  装错的那一份就是用户**下一个登录 shell**；而 L2 链是引擎在跑 `install.sh` **之前**
  就建好的（`harness/architecture.md` §4.2），所以"检查"没法更早，但"失败要响"必须在这儿响。

## 5. 现在能验到什么程度（判据，2026-10-14 实测）

| 判据 | 怎么跑 | 现在的结果 |
|---|---|---|
| 三个发行版各自能编出来 | `wtool build shell/zsh` | ✅ 见 `BACKLOG.md` 的实测数字 |
| 产物要求的最低 glibc | `objdump -p …/bin/zsh \| grep -o 'GLIBC_[0-9.]*' \| sort -uV \| tail -1` | 22.04 → 2.35 / 24.04 → **2.38** / 26.04 → 2.43 |
| 二进制不依赖 libcap | `ldd …/bin/zsh` | 只有 `libtinfo.so.6 libm.so.6 libc.so.6`（+ vdso/ld） |
| 跨发行版起不来（三套的理由） | 把 24.04 那份拿到 `ubuntu:22.04` 容器里跑 | ❌ `version 'GLIBC_2.38' not found` |
| 装完之后交互式能起 | `zsh -ic 'echo INTERACTIVE_OK'` | 见 `BACKLOG.md`（**必须真跑**，不许只写"已装"） |
| 清单合法 | `wtool validate shell/zsh` | rc=0 |
| 引擎回归没被带坏 | `cd wtool-base-tools/tests && sh run_all.sh` | 13 组全绿 |

## 6. 不知道 / 没做的

* **`zsh -c` / 脚本里的 `zmodload`（动态模块）会失败** —— 交互式 shell 一切正常。
  根因在 `Src/params.c`：`module_path` 的初值是**编进二进制的**绝对路径，而
  `MODULE_PATH` 这条环境变量 zsh **故意不导入**（`PM_DONTIMPORT`，注释写着
  "not imported for security reasons"）→ 除了"读 rc 的 shell"（= `env.zsh` 生效的那个），
  别的 zsh 进程改不动它。`fpath` 不受这条限制（`FPATH` 能导入），所以 `env.zsh`
  里 `export FPATH` 让子进程/脚本的 autoload 正常。详见 README「模块路径」与 BACKLOG Z-9。
  **`--disable-dynamic` 量过了，不采用**：会丢掉 19 个 `link=dynamic` 的模块。
* **`download-release` + `unpack-release` 那条路没有端到端验过**：`release.zip` 的
  对照表（`scripts/release.json`）还没写，换台机器解完**还得选一次发行版**。
  发布侧属于别的块，见 `BACKLOG.md`。
* **产物没 strip**（11 MB / 1274 个文件 / 36 个 `.so`）。`make install-strip` 能小一截，
  但会改掉产物的形状与可比性，没做。
* **没给非 Ubuntu 的发行版**（Debian / Fedora / Alpine）。`build/targets.tsv` 加一行就多一个，
  但 `scripts/build.sh` 的 apt 那一段是 Ubuntu 专有的（换源、包名），要改。
* **上游没跟版本**：基线是 `zsh-5.9.2`，`master` 上已经有 `5.9.999.3-test`。
  要不要跟、多久跟一次，见 `BACKLOG.md`。

