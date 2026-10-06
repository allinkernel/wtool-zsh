# BACKLOG —— shell/zsh

> 这个文件是这个项目"接下来做什么、做到哪了"的**唯一权威**。
> 引擎/跨项目的事在 `~/self/wtool/harness/BACKLOG.md`，别混。
>
> 状态：⬜ 待做 · 🔄 在做 · ✅ 做完（写清怎么做的、验证到什么程度）· ⏸ 待决定（要人来拍）

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
