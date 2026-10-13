# BACKLOG —— shell/zsh

> 这个项目**还剩什么**。做完的事写清"实际怎么做的、验证到什么程度"，
> 需要用户拍板的单独列出来。引擎侧的事在 `harness/BACKLOG.md`，别混。

---

## ✅ 已完成：ADR-0045 第 ⑦.4 块 —— 新建 `shell/zsh`（2026-10-14）

**做了什么**：上游 `zsh-users/zsh` 的 fork（`allinkernel/wtool-zsh`，基线 tag `zsh-5.9.2`）
+ docker 三发行版构建 + `<export_usr>` 导出 + 两份 env + 这套文档。

**判据（全部实测，命令可原地重跑）**：

| # | 判据 | 怎么跑 | 结果 |
|---|---|---|---|
| 1 | 引擎驱动三发行版构建 | `wtool build shell/zsh` | ✅ rc=0；`__layer/{ubuntu_22.04,ubuntu_24.04,ubuntu_26.04}/` + `__output/…/main/payload/usr/{bin,lib,share}`，每份 **11 MB / 1274 文件 / 36 个 `.so`** |
| 2 | 每份产物在**自己的**容器里能起 | `docker run --rm -v __output/ubuntu_<v>/main/payload:/p:ro ubuntu:<v> /p/usr/bin/zsh -ic 'echo INTERACTIVE_OK'` | ✅ 三个都 `zsh 5.9.2 (x86_64-pc-linux-gnu)` + `INTERACTIVE_OK`，rc=0 |
| 3 | **为什么必须三套**（反向证据） | 把 24.04 那份放进 `ubuntu:22.04` | ❌ `version 'GLIBC_2.38' not found`，rc=1 |
| 4 | 每份要求的最低 glibc | `grep -ao 'GLIBC_[0-9.]*' …/bin/zsh \| sort -uV \| tail -1` | 22.04→**2.34**、24.04→**2.38**、26.04→**2.38** |
| 5 | 二进制不依赖 libcap | `ldd …/bin/zsh`（容器里） | 只有 `libtinfo.so.6 libm.so.6 libc.so.6`（+vdso/ld）—— 三个发行版都是 |
| 6 | 26.04 真的没有 libcap | `docker run --rm ubuntu:26.04 ls /usr/lib/x86_64-linux-gnu/libcap.so.2` | ❌ 不存在（22.04/24.04 都有）→ `--disable-cap` 的理由 |
| 7 | `fpath`/`module_path` **必须**重设 | 影子路径 ≠ 编译路径时跑 `zle -la` / `compinit` | 不设：`failed to load module 'zsh/zle': /root/.wtool/usr/lib/zsh/5.9.2/zsh/zle.so`；设了：`ZLE_OK` + `COMPINIT_OK` |
| 8 | 清单合法 | `wtool validate shell/zsh` | ✅ `ok: shell/zsh`，rc=0 |
| 9 | 项目被引擎看见 | `wtool_plan.py list-projects --root .` | ✅ 列出 `shell/zsh`（priority 20） |
| 10 | 引擎回归没被带坏 | `cd wtool-base-tools/tests && sh run_all.sh` | 见下面「本轮 run_all」 |

**本轮踩到、值得记的坑**（都进 `AGENTS.md` 了）：

1. **XML 注释里不能有连续两个减号** —— 我在 `wtool.xml` 的注释里写了 `--prefix`，
   `ElementTree` 直接 `not well-formed`，症状是**项目从 `list-projects` 里整个消失**
   （看着像"引擎没扫到这个目录"）。差分定位花的这几分钟值：见 AGENTS.md 铁律 3。
2. **git 检出里没有 `configure`**（只有 `configure.ac`）→ 容器里要先跑 `Util/preconfig`
   （= `autoconf` + `autoheader`），否则报 `./configure: not found`。
3. **`libncurses-dev` 必须有**，否则 `configure: error: No terminal handling library was found`。
   基础镜像里只有运行库 `libtinfo.so.6`，没有头文件。
4. **`make install` 会连带 `install.man`**，它要 yodl（没装）→ 卡在
   `test -s zsh.1 || exit 1`，**整个 install 失败**（前面几步的成果白费）。
   改成显式列目标：`install.bin install.modules install.fns`；
   并且 man 落在 `$PREFIX/share/man` 会被 `<export_usr>` 当成 `share` 的一个条目导出去、
   把**共享的** `$WTOOL_HOME/usr/share/man` 整条占住 —— 所以不装 man 是**两个**理由。
5. **`install.man` 失败前会先 `mkdir` 出空的 `share/man/man1`** —— 空目录一样会被导出去，
   所以 `rm -rf $PREFIX/share/man` 兜底（脚本里有）。
6. **`scripts/build.sh` 在宿主上跑时 `wtool` 可能不在 `$PATH` 里**（非登录 shell）——
   加了绝对路径兜底 `$WTOOL_HOME/wtool/wtool-base-tools/bin/wtool`。
7. **`unpack-layer` 的落点是 `__output/<target>/<层名>/payload/…`**，不是设计稿里写的
   `__output/<target>/usr`（见下面「与设计稿的差异」）。

**产物落在哪（实测，权威）**：

```
__output/<target>/main/payload/usr/{bin,lib,share}   ← 引擎 wt_layer_export 落的（真身）
__output/<target>/usr -> main/payload/usr            ← scripts/build.sh 做的别名链
__output/usr          -> <本机发行版>/usr             ← **选择链**，wtool.xml 认它
```

### ❗与设计稿的两处差异（**以本条为准**）

1. **`__output` 的形状**：`DESIGN.md` §1.4/§2.3 与 `pre_architecture.md` §5.2 写的是
   "产物汇入 `__output/ubuntu_<ver>/usr`"。**引擎今天不这么落** ——
   `wt_layer_export` 一律落到 `__output/<target>/<层名>/{payload,OWNED.tsv}`，
   payload 是**相对影子 `$HOME`** 的路径。所以本项目**多加了两级别名链**，
   让设计稿里那个路径真的存在（`__output/ubuntu_<ver>/usr`），
   而 `<export_usr src>` 指**不带发行版名字**的那条（`__output/usr`）。
2. **`<export_usr src>` 是静态的**：引擎不做"按本机发行版挑一套"（`{target}` 替换只发生在
   `build/layers.tsv` 的命令里）。这就是 ADR-0045 里**还开着的 Q5**；
   本项目用选择链绕过，代价是"选错不会在 install 之前报错" →
   由 `scripts/install.sh` 兜住（核对发行版 + 真跑一次 + `ldd`）。

---

## 待做 / 待决定

| # | 事项 | 为什么要 / 说明 | 状态 |
|---|---|---|---|
| Z-1 | **发布链路**：`scripts/release.json` 的对照表（资产 → 解到 `__output/` 哪） | ③ 类要发 `release.zip`（开发机）+ `release-offline.zip`（断网机，D50/D54）。`unpack-release` 是**声明式**的（D57）：没有这张表，换台机器解完之后**还得手工选一次发行版** | 未做（属别的块） |
| Z-2 | **`download-release` + `unpack-release` 端到端验一遍** | 今天只验了"本机 build → install"这条路 | 未做 |
| Z-3 | **产物 strip**（`make install-strip`） | 今天 11 MB / 1274 文件。strip 能小一截，但会改掉产物的形状与可比性 —— **要用户点头** | 待决定 |
| Z-4 | **要不要把 26.04 那套去掉** | 实测：26.04 编出来的二进制**只要 `GLIBC_2.38`**（和 24.04 那份一样），而且 24.04 那份**在 26.04 上能跑**。所以今天这三套里，26.04 那套的**额外**价值只有在"26.04 上出现了 2.39+ 的新符号"时才体现出来 | 待决定 |
| Z-5 | **跟上游版本** | 基线 pin 在 `zsh-5.9.2`；`master` 上已经是 `5.9.999.3-test`。要不要定期跟、跟的判据是什么 | 待决定 |
| Z-6 | **加别的发行版**（Debian / Fedora / Alpine） | `build/targets.tsv` 加一行就多一个目标，但 `scripts/build.sh` 的 apt 那一段是 Ubuntu 专有的（换源 + 包名） | 未做 |
| Z-7 | **上游 `Scripts/` vs 我们的 `scripts/`** | 大小写不敏感的文件系统上会撞（macOS/Windows）。引擎契约写死了 `scripts/`，改不了 → 只能在 README 里说清楚 | 已知限制 |
| Z-8 | **`--enable-cap` 到底要不要** | 今天统一 `--disable-cap`（26.04 没有 libcap.so.2）。代价是 `zsh/cap` 模块不可用 —— 日常没人用 | 已知取舍 |
| Z-9 | **`zsh -c` / 脚本里 `zmodload` 动态模块会失败**（交互式正常） | 根因：`module_path` 被**编进二进制**，而 `MODULE_PATH` **不从环境导入**（`Src/params.c` 的 `PM_DONTIMPORT`，安全设计）→ 只有"读 rc 的 shell"（就是 `env.zsh`）能改对它。**`fpath` 那条已经用 `export FPATH` 补上了**（FPATH 可以从环境导入），模块这条补不了。<br>**量过 `--disable-dynamic`（静态链模块），不划算**：zsh 有 **19 个 `link=dynamic` 的模块**会被整个丢掉 —— `zsh/stat`、`zsh/system`、`zsh/zselect`、`zsh/files`、`zsh/mapfile`、`zsh/zpty`、`zsh/zprof`、`zsh/zftp` …（`grep -l '^link=dynamic' Src/Modules/*.mdd Src/Zle/*.mdd`）。静态产物 9.0 MB / 0 个 `.so`（今天 11 MB / 36 个），小 2 MB 但少一批功能 | **已知限制**（要让脚本也能加载模块，唯一的正路是引擎侧支持"装到固定绝对路径"，或者用户自己 `zmodload` 前先设 `module_path`） |
