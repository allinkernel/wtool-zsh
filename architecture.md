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
       │       ③ Util/preconfig（autoconf + autoheader）
       │          → ./configure --prefix=$(cat build/prefix-placeholder)
       │       ④ make -j → make install.bin install.modules install.fns（装到占位前缀）
       │          → 把占位树搬到 /root/.wtool/usr（二进制里仍是占位前缀）
       │       ⑤ 容器里自检：占位前缀在不在 / module_path[1] / zsh --version / ldd / glibc
       ├─ docker commit → docker save | tar -x → __layer/<target>/（OCI）
       └─ 导成 __output/<target>/main/{payload,OWNED.tsv}（过 build/export.filter，丢白障）
sh scripts/build.sh          # 宿主上再跑一次（引擎编层 + 别名链 + 选本机那套 + 自检）
wtool install shell/zsh      # 引擎建 L1/L2 + env 块；然后跑 scripts/install.sh
                             #   ① 验收发行版/共享库
                             #   ② scripts/lib/patch-prefix.py：占位前缀 → $WTOOL_HOME/usr
                             #   ③ 验收 zsh -f 的 module_path / regex / zmodload / fpath
```

**三个 configure 开关的理由**（`--disable-cap` 是硬需求，另外两个是防默认值漂移）：

| 开关 | 实测理由 |
|---|---|
| `--prefix=$(cat build/prefix-placeholder)` | **占位前缀**（256 字节，多级目录）：安装期由 `scripts/lib/patch-prefix.py` 缩成真实 `$WTOOL_HOME/usr`。`make install` 之后再把占位树搬进 `/root/.wtool/usr`，所以引擎看到的形状还是"换台机器就是 `~/.wtool/usr`" |
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
* **install.sh 还负责打二进制路径补丁**（H38）：把选中那套 `__output/usr` 里所有含
  占位前缀的文件改成 `$WTOOL_HOME/usr`。ELF（`bin/zsh`、`newuser.so`）按 NUL 字符串
  整段缩、末尾补 NUL；文本（`_run-help`/`run-help`）直接替换。sidecar 落在
  `__output/usr/lib/zsh/.zsh-wtool-patch`，`--uninstall` 用它还原成占位符。

## 5. 现在能验到什么程度（判据，2026-10-14 实测）

| 判据 | 怎么跑 | 现在的结果 |
|---|---|---|
| 三个发行版各自能编出来 | `wtool build shell/zsh` | ✅ 见 `BACKLOG.md` 的实测数字 |
| 产物要求的最低 glibc | `objdump -p …/bin/zsh \| grep -o 'GLIBC_[0-9.]*' \| sort -uV \| tail -1` | 22.04 → 2.34 / 24.04 → **2.38** / 26.04 → 2.38 |
| 二进制不依赖 libcap | `ldd …/bin/zsh` | 只有 `libtinfo.so.6 libm.so.6 libc.so.6`（+ vdso/ld） |
| 跨发行版起不来（三套的理由） | 把 24.04 那份拿到 `ubuntu:22.04` 容器里跑 | ❌ `version 'GLIBC_2.38' not found` |
| 装完之后交互式能起 | `zsh -ic 'echo INTERACTIVE_OK'` | ✅ 只有 `INTERACTIVE_OK`（+ rc 自己那 4 行 `can't change option: zle`，**系统 zsh 同样有**，不是本项目引入的） |
| **`zsh -f` 能加载动态模块**（H38） | `env -u FPATH zsh -f -c '[[ x =~ x ]] && echo REGEX_OK'` / `zmodload zsh/parameter` | ✅ `REGEX_OK` / `MOD_OK`，stderr 空（2026-10-26 VM 实测；旧产物是 `failed to load module zsh/regex` + rc=2） |
| **`zsh -f` 的 fpath 是真实前缀** | `env -u FPATH zsh -f -c 'print -rl -- $fpath' \| grep -Fx "$WTOOL_HOME/usr/share/zsh/$ZSH_VERSION/functions"` | ✅ 在（旧产物是构建时占位路径） |
| 登录 / 嵌套 shell | `zsh -lic 'echo OK'` / `zsh -ic 'zsh -ic "echo OK"'` | ✅ 都过 |
| 补全系统真能用 | `zsh -ic 'autofile… compinit -u; zstyle …'` | ✅ `COMPINIT_OK` + `ZSTYLE_OK` |
| 清单合法 | `wtool validate shell/zsh` | rc=0 |
| 装完账目干净 | `wtool check` | rc=0「一切对得上」 |
| 引擎回归没被带坏 | `cd wtool-base-tools/tests && sh run_all.sh` | 2026-10-26：**12/13 组绿**（release_test 1 条既有红，见 `BACKLOG.md`；契约 311/0） |

**env 块的加载顺序是判据的一部分**（不是细节）：

```sh
grep -n '^# --- wtool:' "$WTOOL_HOME/env.zsh" | head -2   # 第一块必须是 wtool:shell/zsh
zsh -ic 'echo ok' 2>&1 | wc -l                            # 5（= 1 行 ok + rc 自己那 4 行）
```

排在别人后面会怎样（旧产物实测）：整屏
`failed to load module 'zsh/parameter': /root/.wtool/usr/lib/zsh/5.9.2/zsh/parameter.so`
—— 旧二进制的 `module_path` 只有 `env.zsh` 能改对，而工具块（priority 5）与
oh-my-zsh（10）在它之前就 `zmodload` / `compinit` 了。**新产物由安装期二进制补丁
保证编译期路径正确**，不依赖这一块；但升级前的旧二进制、以及整机包里还没重装的
那份仍靠它，所以 priority=1 保留，别改回去。


## 6. 不知道 / 没做的

* **产物在 install 之后绑定当时的 `$WTOOL_HOME`**（2026-10-26 起）：二进制里的
  `module_path`/`fpath` 是安装期写死的绝对路径。移动 `.wtool` 后必须重跑
  `wtool install shell/zsh --force`（sidecar 会按新路径再打）；否则 `zsh -f` 会去旧路径找
  模块。`--uninstall` 会把二进制还原成占位前缀（可重定位状态），所以打包不要求先卸载。
* **`$WTOOL_HOME/usr` 最长 256 字节**（占位前缀长度）。超了 `install.sh` 直接报错；
  要支持更长路径就改 `build/prefix-placeholder` 并重建三套产物。
* **只给 Ubuntu 22.04/24.04/26.04 编**；别的发行版要加 `build/targets.tsv` 一行并改
  `build.sh` 的 apt 段。
* **`--disable-dynamic` 不采用**：会丢掉 19 个 `link=dynamic` 的模块（`zsh/stat` / `zsh/system`
  / `zsh/zselect` / `zsh/files` / `zsh/mapfile` / `zsh/zpty` / `zsh/zprof` / `zsh/zftp`…）。
  现在的修法是"安装期改二进制路径"，不是静态链模块。
* **`download-release` + `unpack-release` 那条路没有端到端验过**：`release.zip` 的
  对照表（`scripts/release.json`）还没写，换台机器解完**还得选一次发行版**。
  发布侧属于别的块，见 `BACKLOG.md`。
* **产物没 strip**（11 MB / 1274 个文件 / 36 个 `.so`）。`make install-strip` 能小一截，
  但会改掉产物的形状与可比性，没做。
* **没给非 Ubuntu 的发行版**（Debian / Fedora / Alpine）。`build/targets.tsv` 加一行就多一个，
  但 `scripts/build.sh` 的 apt 那一段是 Ubuntu 专有的（换源、包名），要改。
* **上游没跟版本**：基线是 `zsh-5.9.2`，`master` 上已经有 `5.9.999.3-test`。
  要不要跟、多久跟一次，见 `BACKLOG.md`。

