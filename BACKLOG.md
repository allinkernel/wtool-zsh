# BACKLOG —— shell/zsh

> 这个文件是这个项目"接下来做什么、做到哪了"的**唯一权威**。
> 引擎/跨项目的事在 `~/self/wtool/harness/BACKLOG.md`，别混。
>
> 状态：⬜ 待做 · 🔄 在做 · ✅ 做完（写清怎么做的、验证到什么程度）· ⏸ 待决定（要人来拍）

---

## ⏸ 待拍板

### 1. `_up_to_have_dir` 最顶层那一格：`env.zsh` 和 `env.bash` 行为不一致

**现状**（2026-10-04 P2 文档/代码核对时发现，**只记录，没改代码**）：

- `env.zsh:36-39`——`cur_dir=${cur_dir:h}` 之后立刻 `[[ ${cur_dir} == / ]] && return 1`，
  **`/` 本身那一格从来没被测过**；
- `env.bash:36-43`——`case` 把 `/usr` 切成空串、再用 `[ -z ] && cur_dir=/` 补回 `/`，
  循环**会**回头测一次 `//<目标>`，所以能找到挂在 `/` 下的目录。

判据（只依赖 `/usr` 存在，两个 shell 各一条）：

```sh
R=~/self/wtool/shell/zsh
bash -c "export WTOOL_PROJECT_DIR=/x; cd /var/log; . $R/env.bash; _up_to_have_dir usr; echo rc=\$?"
#   /        rc=0
zsh  -c "export WTOOL_PROJECT_DIR=/x; cd /var/log; . $R/env.zsh;  _up_to_have_dir usr; echo rc=\$?"
#   （空）   rc=1
```

**影响**：本仓库的硬规矩是"两份必须等价"，这是目前**唯一已知**的不等价点；
但实际用途是找 `.repo` / `.git`，`/` 下不会有这两个东西，所以现实里碰不到。
`tests/env_test.sh` 也没覆盖这一格（用例表里没有"目标只在 `/` 下"这一条）。

**要人拍的三条路**（别替用户选）：

1. 把 `env.zsh` 改成和 `env.bash` 一样（先测 `/` 再 `return 1`）—— 动代码，且要补一条用例；
2. 反过来把 `env.bash` 改成 `env.zsh` 的行为（`/` 不测）—— 也是动代码；
3. 认定"`/` 下不会有 `.repo`/`.git`"，两份都保持原样，只在 README 里写明差异
   （**当前就是这一条**：README「`_up_to_have_dir`」一节 + AGENTS.md §3 已注明）。

拍板之后：改代码的走"一份改动 = 两个 shell + 一条用例 + README"这套流程。
