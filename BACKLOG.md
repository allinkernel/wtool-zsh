# BACKLOG —— shell/zsh

> 这个文件是这个项目"接下来做什么、做到哪了"的**唯一权威**。
> 引擎/跨项目的事在 `~/self/wtool/harness/BACKLOG.md`，别混。
>
> 状态：⬜ 待做 · 🔄 在做 · ✅ 做完（写清怎么做的、验证到什么程度）· ⏸ 待决定（要人来拍）

---

## ✅ `wrg` 换三级搜索后端（rg → fd → find）+ 命中片段高亮 —— 做完（2026-10-07，提交 `0769c0f`）

**做了什么**（`env.zsh` + `env.bash` 同改，两份的 `wrg` 段各 228 行、逐字等价）：

- `wrg` 从"只用 `find`"改成**按顺序探测三个后端**：`rg` → `fdfind`/`fd-find`/`fd` → `find`；
  用**一个**环境变量 `WRG_SEARCH=auto|rg|fd|find`（默认 `auto`）强制指定 ——
  指定的可执行不存在、或取值不认 → stderr 报错、返回 2，**不静默换成别的**
  （原来的 `WRG_NO_FD` 方案作废，没实现）；
- **rg 那条路**：`Android.mk` / `Android.bp` 两种写法不同 → 各跑一次
  `rg --no-heading --line-number --with-filename --color=never -g <名> -e <正则> .` 再合并；
  值做正则转义（`_wrg_re_escape`：`liba+b` 不会命中 `libaaab`），
  模糊模式只给值套 `(?i:...)`（关键词仍大小写敏感）；rg 的 rc=1（没命中）不当错误；
- **fd 那条路**：`<fd> -t f -g 'Android.{mk,bp}' -X awk '<共用脚本>'`；
- 三条后端**共用同一段 awk**（`_WRG_AWK`：`WRG_PASS=search` 扫文件、`WRG_PASS=paint` 上色），
  路径统一归一化成 `find` 的形状（补 `./`），所以三条输出**逐字一致**；
  `find` 兜底那条路的行为/输出/退出码与改动前逐字一致（`liba+b`、注释、空目录、用法都测了）；
- **高亮**：命中的**那一段**（精确 = 整个目标名；模糊 = 名字里命中的子串）包
  `\033[1;31m` … `\033[0m`；`WRG_COLOR=auto`（默认：只有 stdout 是终端才上色）/
  `always` / `never`，`NO_COLOR` 非空一律不上色（**优先级最高**，压过 `always`）；
  排序在着色**之前**、排的是纯文本，ANSI 不进排序键。

**验证到什么程度**：

- `bash tests/env_test.sh`（本机 WSL，rg 14.1.0 + fd 9.0.0 都在）：**129 通过 / 0 失败**
  （改前 67）；再把 PATH 收窄成"只有 rg"→ 121、"只有 fd"→ 115、
  "rg/fd 都没有（纯 find 兜底）"→ 105，**四种情况都 0 失败**（后端相关用例按环境跳过）；
- 新增用例：`WRG_SEARCH=auto|fd|rg` 与 `find` 的输出 **`cmp` 逐字比对**（模糊 + 精确两种模式）、
  元字符当字面量（`liba+b` 不命中 `libaaab`、`libc.d` 不命中 `libcxd`）、
  每条后端的"没有命中 / 树下没有这两种文件"（rc + 报错文字）、后端探测顺序
  （用只有一个可执行名的假 PATH 逼出来；`auto` 用"记一笔再 exec"的 wrapper 证明真走了 rg）、
  强制指定但不存在（rc=2）、高亮（管道里 `grep -c ESC` = 0、`WRG_COLOR=always` 的**精确字节**、
  `NO_COLOR` 压过 `always`、`script`(pty) 下自动上色）、隐藏目录差异（rg/fd 搜不到、find 搜得到）；
- **容器实测**（`wrg-test`：`ubuntu:24.04` + `apt-get install ripgrep fd-find`，
  `/aosp/android16-release`，**13,108 个 Android.mk/bp**）：
  - `wrg -i camera`：rg / fd / find 三条**各 445 行、md5 全是 `ee9e78c8…`**，`cmp` 逐字一致；
  - `wrg libbase`：三条**各 21 行、md5 全是 `f5cbea4f…`**，`cmp` 逐字一致；
  - **独立交叉核对**（grep）：`grep -rn --include=Android.mk -P
    '^\s*(LOCAL_MODULE|LOCAL_PACKAGE_NAME)\s*:?=\s*[^\s#]*(?i:camera)'` +
    `.bp` 的 `'^\s*name\s*:\s*"[^"]*(?i:camera)[^"]*"'` → 0 + 445 = **445 行**，
    与三条 wrg 一致；按 wrg 同一个排序键 `sort -t: -k1,1 -k2,2n` 排完 **`cmp` 也一致**
    （第一次比对用的默认 `sort`，键不同才报差异 —— 是比对脚本的问题，不是 wrg 的）；
  - 高亮：管道下 ESC 计数 = 0；`WRG_COLOR=always` 给出
    `name: "^[[1;31mlibbase^[[0m",`；模糊 `-i base` 只包住 `base`
    （`com.android.art-^[[1;31mbase^[[0m-defaults`）；`docker exec -t … zsh -c '… wrg -i base'`
    和 `script`(pty) 下 auto 都自动上色，`NO_COLOR=1` 就不上色；
  - 耗时（同一棵树**串行**跑，页缓存已热；find 的**冷**跑另测过一次 65s 级）：
    `wrg -i camera` → **rg 1.79s / fd 1.17s / find 8.02s**（第二轮 1.81 / 1.22 / 7.88）；
    `wrg libbase` → **rg 1.82s / fd 1.16s / find 7.86s**；把 PATH 挡掉 rg/fd（auto 回退 find）
    → 7.83s，输出与 rg 那条路逐字一致。**这里 fd 比 rg 略快**（不是"rg 最快"）：
    分项量过 —— rg 每种文件写法各要**一次全树遍历**（.bp 0.92s + .mk 0.88s，存在性探测只 0.02s），
    fd 只遍历一次（列文件 0.57s）再一次性 awk；`find` 光遍历就 6.84s；
- `zsh -n env.zsh` / `sh -n env.zsh` / `bash -n env.bash` / `sh -n env.bash` /
  `bash -n tests/env_test.sh` 都过。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/shell/zsh && bash tests/env_test.sh          # 129 通过, 0 失败
# 容器（工作区只读挂载，改完直接生效；容器里已经装了 ripgrep + fd-find）：
docker exec wrg-test zsh -c 'export WTOOL_PROJECT_DIR=/wtool/shell/zsh;
  . /wtool/shell/zsh/env.zsh; cd /aosp/android16-release;
  for v in rg fd find; do WRG_SEARCH=$v wrg -i camera | md5sum; done'   # 三个 md5 一样
docker exec wrg-test zsh /tmp/wrg_container_test.sh    # 上面那份完整对比脚本（含计时/高亮）
```

**顺带发现（都写进 `architecture.md` 了）**：

- fd 的 `-g` 是**开关**不是"带参数的选项"：`-g A -g B` 会被当成"搜索路径 B 不存在"报错，
  两个文件名必须合成**一个** glob `Android.{mk,bp}`；
- fd 的 `-X`（批量 exec）默认给相对路径**加** `./` 前缀（直接打印时才没有）——
  所以"fd 没有 `./` 前缀"只在直接打印时成立；归一化照做，加了也无害；
- `-X cmd .` 里那个 `.` 是**传给 cmd 的参数**（不是搜索根）：容器里 `awk` 就是 mawk，
  打开目录直接 `read error (Is a directory)` 退出 2 → 整条 fd 路会全空。
  实现改成**不传** `.`（fd 默认就搜当前目录）；
- fd 9.0.0 **没有命中时退出码是 0**（不是文档里那种 1）：实现按"空输出 + 1 当没命中"兜住；
- rg 遇到读不了的目录会退 2（find 也会退非 0）——三条后端统一按"非 0 = 搜索失败"处理，
  与改动前 find 的行为一致；
- 这台机器的环境里有 `NO_COLOR=1`（宿主 shell 里），所以**在宿主的终端里看不到高亮**是正常的：
  看 `echo $NO_COLOR`；要看得 `env -u NO_COLOR` 或 `WRG_COLOR=always`。

**这条语义差异在真实 AOSP 树上确实存在**（容器里量的）：`find` 看得到 13,108 个 mk/bp，
rg/fd 看得到 13,106 个 —— 差的两个是
`external/cpuinfo/deps/clog/Android.bp`、`frameworks/multidex/library/Android.bp`
（被 ignore 的目录）。这次两条路的结果仍然一致，是因为这俩文件里没有 `camera` / `libbase`。

---

## ✅ `start` 加路径补全 / `win` 加服务器分支 / 新增 `wrg` —— 做完（2026-10-06，提交 `a207795`）

**做了什么**（`env.zsh` + `env.bash` 同改）：

- `start <TAB>` 补当前目录的文件/目录名：bash 用 `complete -o default -o filenames start`；
  zsh 跑过 compinit（装了 `shell/oh-my-zsh` 时）用 `compdef _files start`，
  只装本项目、没有 compinit 时退回 `compctl -f start`；
- `win` 的非 WSL（普通服务器）分支：打两行 —— samba 路径
  `//<ip>/<share><相对路径>`（读 `WTOOL_SMB_CONF`，默认 `/etc/samba/smb.conf`；
  `[share]` 段 + 段里的 `path =`，**最长前缀**匹配、按路径分隔符对齐）+ scp 路径
  `<user>@<ip>:<绝对路径>`。`ip` 取 `WIN_IP`，没设就从 `ip -4 addr` 取第一个非 `lo` 的地址；
  取不到 IP / 读不到配置 / 没有 share 匹配，都在 stderr 说清楚并返回 1
  （后两种仍然给出 scp 那一行）。**WSL 分支没动**：还是 `wslpath -w .`；
- `wrg <名字>` / `wrg -i <片段>`：在当前目录树下找 `Android.mk`（`LOCAL_MODULE` /
  `LOCAL_PACKAGE_NAME`）与 `Android.bp`（`name: "xxx"`）的构建目标名，
  精确 / 模糊两种模式，输出 `文件:行号:命中行`。

**验证到什么程度**：

- `bash tests/env_test.sh` → **67 通过 / 0 失败**（改前 22 条：把 HEAD 那份 `git archive`
  到临时目录、对旧代码跑过一遍，22 通过 0 失败）；
- `win` 的 WSL 分支：`HEAD~1` 的旧文件与新文件，在 4 个目录（含带空格的路径）× 两个 shell
  下输出**逐字一致**；测试里另有一条断言"输出等于 `wslpath -w .`"；
- `win` 的服务器分支：用**假 `smb.conf`**（`WTOOL_SMB_CONF` 注入，不碰真 `/etc/samba`）跑 ——
  最长前缀胜出、`path=/ws/a` 不被 `/ws/ab` 命中、三种失败各有用例，两个 shell 同一张表；
- `start <TAB>`：pty 驱动真交互 shell 实测（把 `start` 覆盖成会回声参数的函数，
  敲 `start li<TAB><Enter>`，看执行到的是 `lib` 还是 `li`）—— 本机 bash / zsh /
  zsh+compinit 三条路都补出 `lib`；**反证**：同一个探针换成 `complete -A hostname start`
  就补不出来，说明探针真的在测补全；
- **容器验证**（2026-10-06，`ubuntu:24.04`、`--network=host`、工作区 `:ro` 挂载）：
  `bash container-raw.sh` → `./install.sh` → `eval "$(sh ~/.wtool/bootstrap/wtool.sh doctor --quiet)"`
  （等价于 `exec $SHELL`）→ `wtool sudo-bootstrap` → `wtool install shell/zsh`
  （**没有**跑 `wtool bootstrap`）。装出来的块 `head=a2077954e81d` 就是本提交。容器里：
  - `start li<TAB>` → `lib`（bash 和 zsh 都补出来；反证探针也跑了）；
  - `win`（容器不是 WSL）→ `//10.1.2.3/proj/sub` + `root@10.1.2.3:<目录>`、rc=0；
    读不到 `smb.conf`、没有匹配的 share → rc=1 且报错清楚；
  - `wrg libfoo` → `./foo/Android.mk:1:LOCAL_MODULE := libfoo`；
    `wrg -i LIB` → `Android.bp` 与 `Android.mk` 两个文件都命中。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/shell/zsh && bash tests/env_test.sh    # 67 通过, 0 失败
```

---

## ✅ `_up_to_have_dir` 最顶层那一格：两份不等价 —— 已修（2026-10-04，提交 `ad39c5e`）

**原来什么样**（P2 文档/代码核对时发现，方向由用户 2026-10-04 拍板：**以 bash 版为准**）：

- `env.zsh`——`cur_dir=${cur_dir:h}` 之后才 `[[ ${cur_dir} == / ]] && return 1`，
  **`/` 本身那一格从来没被测过**；
- `env.bash`——`case` 把 `/usr` 切成空串、再用 `[ -z ] && cur_dir=/` 补回 `/`，
  循环**会**回头测一次 `//<目标>`，所以挂在 `/` 下的目录找得到。

判据（只依赖 `/etc` 存在，只读、不碰 `$HOME`）：

```sh
R=~/self/wtool/shell/zsh
bash -c "export WTOOL_PROJECT_DIR=/x; cd /var/log; . $R/env.bash; _up_to_have_dir usr; echo rc=\$?"
zsh  -c "export WTOOL_PROJECT_DIR=/x; cd /var/log; . $R/env.zsh;  _up_to_have_dir usr; echo rc=\$?"
# 修前：bash 打印 / 、rc=0；zsh 打印空、rc=1
# 修后：两份都打印 / 、rc=0
```

**怎么修的**：`env.zsh` 改成和 `env.bash` 同构 —— **先判"已经在 `/` 了"再往上走**，
顺手删掉没被任何地方读的 `origin_dir`（`grep -rn origin_dir` 只剩定义那一行）。
没有改 `env.bash`（它本来就对）。

**验证到什么程度**：

- `bash tests/env_test.sh` → **22 通过 / 0 失败**（两个 shell 各 11 条；
  新加的"最顶层那一格"用例断言输出是 `/` 且 rc=0，两边同一张表）；
- **反证**：把新用例拿去跑**旧** `env.zsh`（`git archive HEAD` 到临时目录，
  只替换测试文件）→ `zsh：最顶层那一格 FAIL（期望 [/|rc=0] 实际 [|rc=1]）`，
  `21 通过, 1 失败`；说明这条用例真的盯着这个缺陷，不是白加的；
- `zsh -n env.zsh` / `bash -n tests/env_test.sh` 都过。

**结论**：现在两份 `env.*` 没有已知的不等价点。
修复提交：`ad39c5e`（`ds_dev`）；反证用的临时目录已删，命令都在上面，可原地重跑。

---

## ⏸ 待拍板

（暂时没有。）
