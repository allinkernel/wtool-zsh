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

## ✅ 已完成：H38 —— `zsh -f` 拿不到动态模块（2026-10-26）

**做法**：构建期用 256 字节占位前缀（`build/prefix-placeholder`）编译，安装期由
`scripts/lib/patch-prefix.py` 把选中那套产物里的占位前缀就地换成真实的
`$WTOOL_HOME/usr`。ELF 按「占位符 + 后缀」整段缩、NUL 补在末尾；sidecar
`lib/zsh/.zsh-wtool-patch` 支持重复安装/换路径/卸载还原。

**包装脚本路线实测否决**：`-c` 只能 `eval`/`source` 包一层（`$0`/参数/行号/`-x` 轨迹变），
交互式 `zsh -f -i` 没有 `-c` 可注入（`[[ x =~ x ]]` 仍报模块错误），登录 shell 的
`argv[0]`（`-zsh`）经过 shebang 包装器后丢失。详见 README「为什么不选包装脚本」与 H38。

**判据（VM `mindul@192.168.76.136`，`/tmp/zsh-accept` 干净家目录，2026-10-26 实测）**：

| 命令 | 结果 |
|---|---|
| `zsh -f -c '[[ x =~ x ]] && echo REGEX_OK'` | `REGEX_OK`，rc=0 |
| `zsh -f -c '[[ x =~ y ]] && echo REGEX_OK'` | stderr 空、rc=1（**x 不匹配 y**；原始期望 REGEX_OK 写错了） |
| `zsh -f -c 'zmodload zsh/parameter && echo MOD_OK'` | `MOD_OK`，rc=0 |
| `zsh -c 'echo $module_path[1]'` | `/tmp/zsh-accept/.wtool/usr/lib/zsh/5.9.2` |
| `zsh -ic 'echo IC_OK; bindkey "^[[A"'`（非 tty + PTY） | `IC_OK` + `"^[[A" up-line-or-history`，rc=0 |
| `sh -c 'command -v zsh; zsh --version'` | `/tmp/zsh-accept/.wtool/usr/bin/zsh` + `zsh 5.9.2` |
| `zsh -f -i` 里 `[[ x =~ x ]]`（PTY） | `IREGEX_OK`，rc=0 |
| `zsh -f -c 'print -rl -- $fpath' \| grep -Fx …/functions` | 命中 |
| `zsh -c 'kill -TERM $$'` | rc=143 |
| `zsh -l -c 'echo $options[login] $0'` | `on zsh`，rc=0 |
| 脚本文件 / `#!/…/zsh` shebang | `$0`/参数正确，`SCRIPT_REGEX_OK` / `SHEBANG_REGEX_OK` |

**回归（2026-10-26 本轮实测）**：

- 上游 zsh 测试（在 `/tmp` 的构建树跑 `make -C Test TESTNUM=<组> check`）：
  A **8/8**、B **13/13**、C **5/5**、D **9/9**、E **3/3**，0 失败。
- `tools/git-repo-sh-tools/tests/run_tests.sh`：**630 通过 / 0 失败**。
- `wtool-base-tools/tests/run_all.sh`：**12/13 组绿** —— pairing 60、provision 40、
  publish 219、table 111、release-copy 17、layer 50、docker 102、install-env 67、
  installer 93、export 78、muslbin 121、contract 311（全 0 失败）。
  **`release_test` 184/1**：唯一红是**既有**问题（和本改动无关）——测试夹具在坏包里
  放了绝对软链 `/nonexistent`，Python 3.12 的 `tarfile` 先抛 `AbsoluteLinkError`，
  没走到「坏包里有 `.wtool/usr`」那条断言。建议把夹具改成相对链（引擎侧一行）。
  `run_all.sh` 会停在 release_test，所以后面 7 组是**单独**跑的（上面的数字）。

**代价**：产物 install 后与 `$WTOOL_HOME` 绑定（移动要重装）；目标前缀 ≤256 字节；
只改本机选中的 target。见 README §6 / `architecture.md` §6。

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
| Z-9 | ~~**`zsh -c` / 脚本里 `zmodload` 动态模块会失败**（交互式正常）~~ **✅ 已修（2026-10-26，安装期二进制补丁；见上面 H38 节）** | 根因：`module_path` 被**编进二进制**，而 `MODULE_PATH` **不从环境导入**（`Src/params.c` 的 `PM_DONTIMPORT`，安全设计）→ 只有"读 rc 的 shell"（就是 `env.zsh`）能改对它。**`fpath` 那条已经用 `export FPATH` 补上了**（FPATH 可以从环境导入）；模块这条在旧产物上补不了 —— 2026-10-26 改成安装期二进制补丁后已修。<br>**量过 `--disable-dynamic`（静态链模块），不划算**：zsh 有 **19 个 `link=dynamic` 的模块**会被整个丢掉 —— `zsh/stat`、`zsh/system`、`zsh/zselect`、`zsh/files`、`zsh/mapfile`、`zsh/zpty`、`zsh/zprof`、`zsh/zftp` …（`grep -l '^link=dynamic' Src/Modules/*.mdd Src/Zle/*.mdd`）。静态产物 9.0 MB / 0 个 `.so`（今天 11 MB / 36 个），小 2 MB 但少一批功能 | **✅ 已修**（`zsh -f` / 脚本都行；`--disable-dynamic` 仍不采用） |
| Z-10 | **引擎侧：`<zshrc priority=…>` 被解析但不参与排序** | 实测：把 `<zshrc priority="1"/>` 写进 `wtool.xml`、重装 —— 汇总的 `$WTOOL_HOME/env.zsh` 里那一块还是 `prio=20`。原因在 `wtool_plan.py` 的 `collect_env_blocks()`：它排序读的是 **`var/<项目>/meta.tsv` 的 `priority`**，而那条来自**根元素**；`render_block(...)` 也是拿 `meta["priority"]`。所以**只有根元素的 priority 能调 env 块的顺序**。<br>本项目因此把**根元素**改成 `priority="1"`（env 块必须第一个加载，理由见 `wtool.xml` 的注释）。⚠️ 副作用：这个项目的 **bootstrap 顺序**也跟着变成第一 —— 本项目不依赖别人，可以接受，但这是"为了 env 顺序牺牲了项目顺序"，引擎修好之后应该改回来 | **引擎侧待修**（改 `collect_env_blocks`/`render_block` 用 env 条目的 priority；不属本块） |
| Z-11 | ~~**不读 rc 的 zsh 找不到自己的 functions**~~ **✅ 已修（2026-10-26，同一个二进制补丁把 fpath 也改对；见上面 H38 节）** —— 连带把 `wtool-base-tools/tests/contract_test.sh` 弄红 | 同一个根因的另一个症状（Z-9 是模块，这是 fpath）：`zsh -f` / `zsh -c`（不读 rc）的 `fpath` 是**编进二进制的** `/root/.wtool/usr/share/zsh/…`（目标机上不存在），而**系统 zsh 的** `/usr/share/zsh/functions` 又不在我们的编译默认里 → `autoload -Uz compinit` 失败（`compinit: function definition file not found`）→ `compdef` 不存在 → 补全注册不上。<br>**为什么值得单独记**：`wtool-base-tools/tests/contract_test.sh` 的「zsh 里 wtool 挂到了 _wtool」那一条就是 `zsh -f -c '…; print ${_comps[wtool]}'`。**装过 shell/zsh 的机器上，`zsh` 就是本项目这份**，于是：<br>`sh contract_test.sh` → `PASS 312 FAIL 1`（`run_all.sh` **在这一组就停了**）<br>`PATH=/usr/bin:$PATH sh contract_test.sh` → `PASS 313 FAIL 0`<br>（两条都实测过。**交互式 shell 不受影响**：rc → env.zsh 会把 fpath 设对，`zsh -ic 'compinit'` 实测 OK。） | **✅ 已修**（补丁后 `zsh -f` 的 fpath 直接指向 `$WTOOL_HOME/usr/share/zsh/<ver>/functions`；引擎侧测试仍建议显式给 fpath，见 Z-12） |
| Z-13 | **产物 install 后与 `$WTOOL_HOME` 绑定** | `module_path`/`fpath` 是安装期写死的绝对路径；移动 `.wtool` 要 `wtool install shell/zsh --force`（sidecar 会再打）；`--uninstall` 会还原成占位符。`$WTOOL_HOME/usr` 最长 256 字节 | **已知取舍**（H38 的代价；不是 bug） |
| Z-12 | **要不要用系统层把 functions 挂到 `/usr/local/share/zsh/site-functions`** | 那个路径**在我们编译进去的 fpath 里**（zsh 的默认 `sitefndir`）—— 往里放一条指向 `$WTOOL_HOME/usr/share/zsh/$ver/functions` 的链，`-f` / 脚本里的 autoload 就都能用了。代价：要 root（`wtool sudo-install`）、而且是**系统级**改动（换 WTOOL_HOME 要重放） | 待决定 |



