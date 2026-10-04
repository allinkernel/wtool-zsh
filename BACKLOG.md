# BACKLOG —— shell/zsh

> 这个文件是这个项目"接下来做什么、做到哪了"的**唯一权威**。
> 引擎/跨项目的事在 `~/self/wtool/harness/BACKLOG.md`，别混。
>
> 状态：⬜ 待做 · 🔄 在做 · ✅ 做完（写清怎么做的、验证到什么程度）· ⏸ 待决定（要人来拍）

---

## ✅ `_up_to_have_dir` 最顶层那一格：两份不等价 —— 已修（2026-10-04）

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

---

## ⏸ 待拍板

（暂时没有。）
