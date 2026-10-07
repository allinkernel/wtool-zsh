# BACKLOG —— shell/zsh

> 这个文件是这个项目"接下来做什么、做到哪了"的**唯一权威**。
> 引擎/跨项目的事在 `~/self/wtool/harness/BACKLOG.md`，别混。
>
> 状态：⬜ 待做 · 🔄 在做 · ✅ 做完（写清怎么做的、验证到什么程度）· ⏸ 待决定（要人来拍）·
> ❌ 不修（人已拍板不做，理由与留档写在条目里）

---

## ✅ `wrg` 加 rg/grep 风格选项（含 `-A/-B/-C` 上下文行）+ 选项位置自由 —— 做完（2026-10-07，提交 `24c38fe`）

**需求（用户 2026-10-07）**：`wrg` 要像 rg/grep 那样有 `-A/-B/-C`（上下文行）、
`-t/--type`、`-l/--files`、`-c/--count`、`-m/--max-count`、`--color`、`-e`、`--`、`-v`，
而且**选项位置自由**（`wrg system_image_defaults -A3`、`wrg x -i`、`wrg -A 2 x -i` 都要能跑）。
硬不变量不变：三后端输出逐字一致（`cmp` 钉着）、两个 shell 的 `wrg` 段逐字等价。

**做了什么**（`env.zsh` + `env.bash` 同改；`wrg` 段 487 → **865 行**，两份**逐字相同**
—— 新写的代码全用 `[ ]`，所以连 `[[ ]]` / `[ ]` 这点差异都没有；`_WRG_AWK` 段 md5
两边都是 `3a1db3018f4602a4a76d5cc9168d1bfc`）：

- **解析**：手写全参数扫描（不用 `getopts` —— POSIX 那套不认长选项，也做不到"选项写在查询串后面"）。
  `--` 之前按选项解释、之后一律位置参数；短选项簇里布尔项就地吃掉，碰到 `A B C m e t`
  就把**剩下的字符**当值（`-ilA3` = `-i -l -A 3`），剩下的为空就吃下一个参数（`-A 3`）；
  长选项 `--x=v` / `--x v` 都认；选项和查询串混着写都行，位置参数**最多一个**
  （多个 → rc 2 + `只认一个查询串（多出来的：…；多个名字请用 -e）`）。
- **上下文行**（关键约束：必须由共用 awk 算，不能用 rg/grep 自带的 `-A/-B`）：新增
  `WRG_PASS=ctx` —— shell 侧照样先 `sort -t: -k1,1 -k2,2n`（`-m` 截断在这之后、展开之前），
  ctx pass 按路径攒一批，`flush()` 把命中窗口 `[行号-B, 行号+A]` 并成块（重叠/相邻**合并**），
  再 `getline < 路径` 逐行读回文件，块里的行按形状打：命中行 `路径:行号:原文`（照旧分两段红/绿）、
  上下文行 `路径-行号-原文`（**不着色**）、**块与块之间**（含跨文件）一行 `--`（grep 惯例）；
  读完 `close()`（不攒 fd），文件读不出来时退化成"只打命中行"。`-A/-B/-C` **只影响显示**
  （命中判定 / 排序 / 退出码不变），`-C 0` 等于不写、走老的 `paint` 路径 → 输出与改造前逐字一致。
- **新选项**：`-t/--type bp|mk|make`（可重复 / 逗号分隔；判类别仍是共用 awk 的 `kind()`，
  外面再加一层 `WRG_KINDS` 掩码 —— 三条后端的文件集合不会各说各话；预检提示语跟着类型走）、
  `-l/--files`、`-c/--count`（`路径:条数`）、`-m/--max-count`（**全局**、排序后取前 n、
  `-m 0` → rc 1）、`-e/--regexp`（多个查询串合成 rg 粗筛的**一个 alternation**，真判命中仍回 awk；
  模糊时每个名字各算一次前缀、各打各的表头，某个名字一个都没枚举到就只给它一行 stderr 警告）、
  `--color=auto|always|never`、`--`、`-v/--version`（`wrg 1.0（后端 rg）`）。
- **颜色语义**（rg 的口径，两层）：CLI 的 `--color=always` **压过 `NO_COLOR`**；
  env 里的 `WRG_COLOR=always` **仍旧被 `NO_COLOR` 压过**；`--color=never` 压过 `WRG_COLOR`。
- 未知选项 / 缺值 / `-A/-B/-C/-m` 的值不是非负整数 / `-t`、`--color` 取值不认 /
  位置参数多个 / 一个查询串都没有 → 都是 **rc 2 + 用法**；`-h` / `--help` / `-v` 是 stdout + rc 0。

**验证到什么程度**：

- `bash tests/env_test.sh`（本机 WSL，rg 14.1.0 + fd 9.0.0）：**499 通过 / 2 失败**
  （改前 299 通过 / 同样那 2 条；新加 200 条 = 每个 shell +100）。那 2 条失败还是
  `win | head -1` 的破管道老毛病 —— `git show 24c38fe^:env.zsh` 那份**改动前**的代码同样失败，
  与 wrg 无关；
- **反向验证**：新测试脚本配改动前的 `env.zsh` / `env.bash`（`24c38fe^`）跑
  → **351 通过 / 150 失败**（148 条 wrg 新用例 + 那 2 条 win 老毛病）；
  脚本比对过：77 条字面量新断言里**没有一条**在旧实现上也是 ok 的（"两边都报错所以相等"
  这种假通过不存在——位置自由那几条都锚定到字面量期望值）；
- 容器 `wrg-test`（Ubuntu 24.04、**mawk 1.3.4**、非 WSL、没有 `ip`、rg + fdfind）：
  **497 通过 / 0 失败**；
- `zsh -n env.zsh` / `bash -n env.bash` / `sh -n env.bash` / `sh -n env.zsh` /
  `bash -n tests/env_test.sh` 全过；两份 `wrg` 段机械比对**逐字相同**（各 865 行）；
- **容器实测**（`/aosp/android16-release`，真 AOSP 16，默认后端 rg）：

  ```
  $ wrg system_image_defaults -A3          # ← 用户截图那条，现在能跑了（选项写在查询串后面）
  ./build/make/target/product/generic/Android.bp:463:    name: "system_image_defaults",
  ./build/make/target/product/generic/Android.bp-464-    module_type: "android_filesystem_defaults",
  ./build/make/target/product/generic/Android.bp-465-    config_namespace: "ANDROID",
  ./build/make/target/product/generic/Android.bp-466-    bool_variables: ["TARGET_ADD_ROOT_EXTRA_VENDOR_SYMLINKS"],
  --
  ./build/make/target/product/generic/Android.bp:481:    name: "system_image_defaults",
  ./build/make/target/product/generic/Android.bp-482-    partition_name: "system",
  ./build/make/target/product/generic/Android.bp-483-    base_dir: "system",
  ./build/make/target/product/generic/Android.bp-484-    stem: "system.img",

  $ wrg systemimage -A3                    # 20 行；924 / 925 两个命中并成一块（925 只出现一次）
  ./build/make/core/Makefile:924:.PHONY: systemimage
  ./build/make/core/Makefile:925:systemimage:
  ./build/make/core/Makefile-926-
  ./build/make/core/Makefile-927-# -----------------------------------------------------------------
  ./build/make/core/Makefile-928-
  --
  ./build/make/core/Makefile:3623:systemimage: $(INSTALLED_SYSTEMIMAGE_TARGET)
  …

  $ wrg -i systemimage -C1 | head -5       # 全文 50 行 / 15 条命中 / 11 个 --
  ./build/make/core/Makefile-923-# if they don't do anything.
  ./build/make/core/Makefile:924:.PHONY: systemimage
  ./build/make/core/Makefile:925:systemimage:
  ./build/make/core/Makefile-926-
  --

  $ wrg -l systemimage                     # ./build/make/core/Makefile
  $ wrg -c systemimage                     # ./build/make/core/Makefile:5

  $ NO_COLOR= WRG_COLOR=always wrg system_image_defaults -A3 | cat -v | head -2
  ./build/make/target/product/generic/Android.bp:463:    name: "^[[1;31msystem_image_defaults^[[0m",
  ./build/make/target/product/generic/Android.bp-464-    module_type: "android_filesystem_defaults",   ← 上下文行零 ANSI
  $ NO_COLOR=1 wrg --color=always system_image_defaults -A3 | head -1 | cat -v
  ./build/make/target/product/generic/Android.bp:463:    name: "^[[1;31msystem_image_defaults^[[0m",   ← 显式 always 压过 NO_COLOR
  ```

- **三后端 `cmp`**（真 AOSP 上：`-i systemimage -C1` 的 50 行 + 着色版 `system_image_defaults -A3`）：
  `auto` / `rg` / `fd`(fdfind) 三份与 `find` **纯文本、着色各 3 组 `cmp` 全 OK**，
  管道输出 ESC 计数 = 0；
- **耗时**（同一棵树，各跑 3 次取区间）：`wrg systemimage` 2714–2760 ms、
  `-A3` 2705–2746 ms、`-C1` 2725–2740 ms、`-C3` 2747–2824 ms ——
  **上下文本身没有量得出来的额外开销**（瓶颈是 rg 扫那棵 169G 的树）；
  `-i systemimage`（模糊那条路要多扫一遍来枚举目标名）不带上下文 5811 ms / `-C1` 5572 ms /
  `-C3` 5574 ms（开销在模糊那一遍枚举上，与 `-C` 无关）；
  `find` 后端 `-i systemimage -C1` = 29134 ms（它不跳 ignore 目录，慢是后端本身的老差异）。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/shell/zsh && bash tests/env_test.sh        # 499 通过, 2 失败（2 条是 win 的老毛病）

# 反向验证：新用例配改动前的实现（应当 351 通过 / 150 失败）
rm -rf /tmp/oldimpl && mkdir /tmp/oldimpl &&
  git show 24c38fe^:env.zsh  > /tmp/oldimpl/env.zsh &&
  git show 24c38fe^:env.bash > /tmp/oldimpl/env.bash &&
  cp -r tests /tmp/oldimpl/ &&
  bash /tmp/oldimpl/tests/env_test.sh

docker exec wrg-test bash -c 'bash /wtool/shell/zsh/tests/env_test.sh | tail -1'   # 497 通过, 0 失败

docker exec wrg-test bash -c 'cd /aosp/android16-release &&
  WTOOL_PROJECT_DIR=/wtool/shell/zsh . /wtool/shell/zsh/env.bash
  wrg system_image_defaults -A3'                           # 9 行，含一行 --（就是上面那段）

# 三后端 cmp（纯文本）
docker exec wrg-test bash -c 'cd /aosp/android16-release &&
  WTOOL_PROJECT_DIR=/wtool/shell/zsh . /wtool/shell/zsh/env.bash
  for v in auto rg fd find; do WRG_SEARCH=$v wrg -i systemimage -C1 > /tmp/c-$v.txt; done
  cmp /tmp/c-auto.txt /tmp/c-find.txt && cmp /tmp/c-rg.txt /tmp/c-find.txt &&
  cmp /tmp/c-fd.txt /tmp/c-find.txt && echo cmp-ok'
```

**已知边界 / 没做**（都写进 `architecture.md` §4.5 / §4.5.4 了）：

- `-t make` 的文件名集合里有 `*.mk`，所以"树里只有 Android.mk"时**预检**算"有文件"
  （报"没有匹配"而不是"树下没有 …"）—— 三条后端一致；
- `-m` 是**全局**的（不是 grep 的"每文件"语义），而且是"排序后取前 n 条"
  （不是"边读边停"）；可观测行为一样；
- `-c` 只列**有命中**的文件（`grep -rc` 会连 0 条的文件一起列）—— 有意的，
  不然三条后端的文件集合会打起来；
- `-v` 定成 `--version`（不是 grep 的"反向匹配"），版本号先写死 `wrg 1.0`；
  实现里没做"版本从哪读"，改版本号要动 `env.zsh` / `env.bash` 两处；
- 上下文行**永不着色**（rg 默认会给上下文行上暗色），按需求实现；
- 没做：`--color=ansi`（只有 auto/always/never）、`-n` / `-H` 这类"关掉行号 / 文件名"的开关、
  颜色值可配置。

---
## ✅ `wrg` 高亮改成"分两段"：命中段红粗 + 目标名其余部分绿 —— 做完（2026-10-07，提交 `98d976e`）

**需求（用户 2026-10-07）**：模糊匹配（`wrg -i <输入>`）命中时**整个目标名**都要着色 ——
用户输入匹配到的那一段**红 + 加粗**（`\033[1;31m…\033[0m`，不变），目标名里**其余（没匹配到的）
部分绿、不加粗**（`\033[32m…\033[0m`）。`wrg -i ystemim` 命中 `systemimage` 要渲染成
`\033[32ms\033[0m\033[1;31mystemim\033[0m\033[32mage\033[0m`（前缀 `s` 绿 / `ystemim` 红粗 / 尾巴 `age` 绿）。

**做了什么**（`env.zsh` + `env.bash` 同改、逐字等价，只差 `[[ ]]` vs `[ ]`；`wrg` 段 478 → 487 行。
**只动 `WRG_PASS=paint` 那一层** —— 判命中 / 抠目标名 / 枚举 / 排序 / 退出码 / 后端选择一律没动）：

- `paint` pass 里用 `vlen = length(v)` 定目标名结尾，`mid` 拼三段：命中段**之前**一段绿
  （`o > 0` 才打）、命中段红粗、命中段**之后**一段绿（`o + hlen < vlen` 才打），
  最后 `print fp ":" fl ":" substr(ft, 1, vs - 1) mid substr(ft, vs + vlen)`；
  原来是 `substr(ft, 1, vs - 1 + o) … substr(ft, vs + o + hlen)`（只包命中段、名字其余部分原样）；
- **精确模式不变**：命中的就是整个名字，两头都空 → 自动没有绿段；模糊但**整名命中**也没有绿段；
- **只标第一处**：`hit()` 找的是第一处命中，同一个子串在一个名字里出现多次时，
  第二次出现连同尾巴一起落在绿段里；
- 行内其它字符（`name: "` / `",` / `.PHONY: ` / `: $(…)`）仍然不着色（`WO[]` 定名字起点、
  `length(v)` 定名字结尾，绿段只在名字内部切）。

**验证到什么程度**：

- `bash tests/env_test.sh`（本机 WSL，rg 14.1.0 + fd 9.0.0）：**299 通过 / 2 失败**（改前 279/2；
  新加 20 条 = 每个 shell 10 条；那 2 条失败还是 `win | head -1` 的破管道老毛病 ——
  `git show HEAD~1:env.zsh` 那份**改动前**的代码同样失败，与 wrg 无关）；
  PATH 收窄成受限目录另测三种（**这次三种都实测过**）：只有 rg = **279**、只有 fd = **273**、
  都没有（纯 find）= **245**（失败数都是那同样的 2 条）；
- 容器 `wrg-test`（Ubuntu 24.04、**mawk 1.3.4**、非 WSL、没有 `ip`、rg + fdfind）：
  **297 通过 / 0 失败**；
- **新用例对旧实现会挂**：新测试脚本配 `git show HEAD~1:env.zsh|env.bash` 在 `/tmp/wt-regress` 里跑
  → **291 通过 / 10 失败**（4 条/shell：3 条改过的旧着色断言 + 新的 `-i ystemim` 四行字节断言）；
- `zsh -n env.zsh` / `bash -n env.bash` / `sh -n env.bash` / `bash -n tests/env_test.sh` 全过；
  `env.zsh` 与 `env.bash` 的 `wrg` 段去掉 `[` `]` 后逐字相同，`_WRG_AWK` 段 md5 相同
  （`5da5bb943f58781c6eb65d863a758089`）；
- **容器实测**（`/aosp/android16-release`，真 AOSP，默认后端 rg）：

  ```
  $ NO_COLOR= WRG_COLOR=always wrg -i ystemim | cat -v | head -6
  ./build/make/core/Makefile:924:.PHONY: ^[[32ms^[[0m^[[1;31mystemim^[[0m^[[32mage^[[0m
  ./build/make/core/Makefile:925:^[[32ms^[[0m^[[1;31mystemim^[[0m^[[32mage^[[0m:
  ./build/make/core/Makefile:3623:^[[32ms^[[0m^[[1;31mystemim^[[0m^[[32mage^[[0m: $(INSTALLED_SYSTEMIMAGE_TARGET)
  ./build/make/core/Makefile:3627:.PHONY: ^[[32ms^[[0m^[[1;31mystemim^[[0m^[[32mage-nodeps^[[0m snod
  ./build/make/core/Makefile:3628:^[[32ms^[[0m^[[1;31mystemim^[[0m^[[32mage-nodeps^[[0m snod: $(filter-out systemimage-nodeps snod,$(MAKECMDGOALS)) \
  ./build/make/core/Makefile:7645:^[[32ms^[[0m^[[1;31mystemim^[[0m^[[32mage^[[0m: $(INSTALLED_QEMU_SYSTEMIMAGE)
  ```

  `main.mk:1383/1384` 的 `vbmetasystemimage` 同理：绿 `vbmetas` + 红粗 `ystemim` + 绿 `age`；
  三后端（auto / rg / fd vs find）×（着色 / 纯文本）**9 组 `cmp` 全 OK**（`cat -v` 与原始字节都比），
  4 份着色输出各 15 行、ESC 计数都是 15，4 份纯文本 ESC 计数**全是 0**，rc=0、stderr 都是 0 字节；
  精确 `wrg systemimage` 仍整名红粗（`grep -c` 绿码 = 0）、`NO_COLOR=1` 压过 `WRG_COLOR=always`；
- 文档：`architecture.md` §4.5.2 重写成"两段"表 + 边界说明（§4.5 / §4.5.1 附近提到高亮的两处同步了），
  §5 补第六棵树 `$T/src6` 与四组条数；`README.md` 的「高亮」段与示例补了绿段。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/shell/zsh && bash tests/env_test.sh          # 299 通过, 2 失败（2 条是 win 的老毛病）
docker exec wrg-test bash -lc 'cd /aosp/android16-release && source /wtool/shell/zsh/env.bash
  NO_COLOR= WRG_COLOR=always wrg -i ystemim | cat -v | head -6'
docker exec wrg-test bash /tmp/wrg6_cmp.sh                   # 三后端 cmp + ESC 计数（脚本在容器 /tmp 里）
```

**已知边界（写进 `architecture.md` §4.5.2 了）**：

- 绿段只在**模糊**模式出现：精确匹配、`-i` 整名命中都没有绿段（"没匹配到的部分"为空 → 不打那对码）；
- 只标**第一处**命中；后面的（含同一子串第二次出现）算"没匹配到" → 绿；
- 绿的只是**目标名内部**：`name: "` / `",` / `.PHONY: ` / `: $(…)` 这些行内其它字符仍不着色。

---

## ✅ `wrg` 修假阳性 + 模糊匹配换成"去 `_` + 逐级截断前缀" —— 做完（2026-10-07，提交 `55cd9d9`）

**做了什么**（`env.zsh` + `env.bash` 同改、逐字等价，只差 `[[ ]]` vs `[ ]`；`wrg` 段 478 行）：

① **假阳性**（用户实测报的两行，都在 `build/make/core/Makefile`）——两条新规则：

- **以 TAB 开头的行一律不算目标定义**（`rule_prefix()` / `cand_bp()` / `cand_mk()` 各一份）：
  Makefile 的 recipe 必须 TAB 缩进，那是命令行不是目标；
- **冒号前那段里有 `"` 或 `'` 的整行否决**（`@echo "Target system fs image: $(1)"` 这种字符串）；
  `.PHONY:` 声明词里带引号的也跳过（和原有的 `$` `=` `\` 一个待遇）。

  为什么两条都要：`:3616:`（`\t@echo "Install system fs image: $@"`）是 TAB recipe，
  **TAB 那条**挡得住；`:3514:`（`  @echo "Target system fs image: $(1)"`）缩进是**两个空格**
  （它在 `define build-systemimage-target` 体内），TAB 那条**管不着**它 —— 靠**引号那条**才挡掉。
  `.PHONY: $(TARGETS)` 这种老反例不受影响。

② **模糊匹配（`-i`）按新语义重做**（`architecture.md` §4.5.3）：

- **枚举目标名**：新增 `_wrg_prefix`，先用**和搜索同一个后端**把三类文件里的所有目标名抠一遍
  （awk 的 `WRG_PASS=names` / `names3`，`take()` 进收集分支），**每次运行都重扫、不缓存**；
  `find -exec {} +` / `fd -X` 会分批 → 每批各打印一行，shell 侧取最长的那行；
- **归一化**：`key()` = 去掉 `_` + 转小写，查询串和候选名两边都过；
- **逐级截断**：`addname()` 算"和归一化查询的最长公共前缀"，`END` 里只在前缀长度
  ≥ `min(4, 查询长度)` 时打印 `substr(npat, 1, maxlen)` —— 也就是**实际匹配的前缀**；
  **最短试到 4 个字符**，查询本身不足 4 个字符就整个试；
- **表头**：`实际匹配` 与"用户输入去 `_` 后"**不同**时才打三行
  （`用户输入<原样>` / `实际匹配<前缀>` / `匹配目标名如下：`），正常命中保持干净输出；
- **命中仍是子串匹配**（不锚定目标名开头）—— 既有的 `-i kphony1` 命中 `mkphony1` 不能退化，
  用户那个例子（`vbmeta_systmmm` → `vbmetasyst` → `vbmetasystem*`）也满足；
  **用户已确认取 A（2026-10-07）**：A = **子串匹配、不锚定目标名开头**（即现状，**不改代码**）；
  `architecture.md` §4.5.3 与 README「用法」表/排错表里写的现状就是这一条（前缀 `metasystem`
  能命中 `vbmetasystem`），已核对一致，**没动**；
- **高亮**：包住前缀在**原文**里覆盖的那一段（`hit()` 把归一化下标映射回原串）——
  `vbmeta_system_other` 里的 `vbmetasyst` 连中间的 `_` 一起包住；
- **rg 那条路的粗筛**换成 `_wrg_re_us`：把前缀的每个字符转义后**逐字挂一个 `_*`**、整段
  `(?i:…)`。归一化只做"去掉 `_`"，所以"归一化后含前缀"⇔"原文匹配这条正则"——
  既不漏带 `_` 的名字（`vbmeta_system_mk` 能被 `vbmetasystem` 命中），元字符也仍是字面量。

**验证到什么程度**：

- `bash tests/env_test.sh`（本机 WSL，rg 14.1.0 + fd 9.0.0）：**279 通过 / 2 失败**（改前 199/0；
  新加 80 条，每个 shell 40 条 —— 含一条把"子串不锚定"钉死的：`-i metasystemim`
  截成 `metasystem` 后命中 `vbmetasystem`，表头逐字）。那 2 条失败是 `win | head -1` 的破管道老毛病
  （`/tmp/old_env.zsh` 那份**改动前**的代码同样失败，与 wrg 无关）；
  把 PATH 收窄成受限目录另测三种：只有 rg = **261**、只有 fd = **255**、
  都没有（纯 find）= **231**（失败数都是那同样的 2 条）；
- 容器 `wrg-test`（Ubuntu 24.04、非 WSL、没有 `ip`、rg + fdfind）：**277 通过 / 0 失败**
  （差 4 条是 WSL/`ip` 那些"按本机实际情况断言"的用例，与 wrg 无关）；
- **新用例对旧实现会挂**：把新测试脚本配 `git show HEAD:env.zsh|env.bash`（改动前那份）
  在 `/tmp/wt-regress` 里跑 → **38 条 FAIL（19 个/shell）**，正好是假阳性 + 新模糊算法那批，
  说明用例真的钉住了这两个改动（不是"怎么改都过"）；
- **容器实测**（`/aosp/android16-release`，真 AOSP）：
  - `wrg system`：**旧**（`/tmp/old_env.zsh`）→ 命中所报那两行
    （`:3514:  @echo "Target system fs image: $(1)"`、`:3616:\t@echo "Install system fs image: $@"`）；
    **新** → `wrg: 没有匹配 'system' 的目标名`，rc=1（树里没有真名叫 `system` 的目标）；
  - `wrg systemimage` → **5 行**（`:924:.PHONY: systemimage`、`:925:systemimage:`、`:3623:`、`:7645:`、`:7736:`）；
    `wrg -i systemimage` → **15 行**（多了 `systemimage-nodeps snod`、`main.mk:1383/1384 vbmetasystemimage`，
    以及 `system_image_defaults` / `aosp_system_image` 这类**带 `_` 的 bp 名字** —— 老代码按原文子串匹配，
    这些是搜不到的）；三后端 stdout+stderr **`cmp` 逐字一致**；
  - `wrg -i vbmeta_systmmm` → 表头 + 2 行：
    ```
    用户输入vbmeta_systmmm
    实际匹配vbmetasyst
    匹配目标名如下：
    ./build/make/core/main.mk:1383:.PHONY: vbmetasystemimage
    ./build/make/core/main.mk:1384:vbmetasystemimage: $(INSTALLED_VBMETA_SYSTEMIMAGE_TARGET)
    ```
    `WRG_COLOR=always … | cat -v` → `./build/make/core/main.mk:1383:.PHONY: ^[[1;31mvbmetasyst^[[0memimage`
    （只包住实际匹配的那 10 个字符）；`wrg -i vbmeta_system`（带 `_`）→ 同 2 行、**不打表头**；
  - **三后端 `cmp`**：`find` / `fd` / `rg` / `auto` 四种跑 5 条探针（精确 `system`、`systemimage`；
    模糊 `systemimage`、`vbmeta_systmmm`、`vbmeta_system`），**15 组 `cmp` 全 OK**（stdout + stderr 都比）；
    管道里 `grep -c ESC` **全是 0**；`WRG_COLOR=always` 的模糊/精确着色输出在四种后端间也**全 OK**；
  - 耗时（容器，页缓存热，毫秒级只报秒）：

    | 探针 | rg | fd | find | auto |
    |---|---|---|---|---|
    | 精确 `systemimage` | 2.79s | 2.27s | 10.46s | 2.82s |
    | 模糊 `-i vbmeta_systmmm` | 5.79s | 4.96s | 20.42s | 5.89s |

    模糊 ≈ 2× 精确（多了一整遍"枚举目标名"的扫描），这是新算法的固定成本；
  - **独立交叉核对**（不碰 `wrg` 那段 awk、也不用 shell）：
    ① Python 另写一份规则复算 → 归一化目标名 **44,054** 个（`Android.bp` 38,610 / `Android.mk` 73 /
    Makefile 类 5,520），`vbmeta_systmmm` → 前缀 `vbmetasyst`、命中 2 行，
    **与 `wrg` 的 find/fd/rg/auto 四种输出 `cmp` 逐字一致**；
    ② `rg -o` + `awk`/`tr` 独立提取：`Android.bp` 的 `name:` **38,610** 个、`Android.mk` 的
    `LOCAL_MODULE|LOCAL_PACKAGE_NAME` **73** 个 —— 和 ①对得上；
    ③ `rg -c -g Android.bp '^\t+name[[:space:]]*:'` → **空**（这个 AOSP 树里没有 TAB 缩进的 `name:`，
    所以"TAB 一律否决"在这个树上零代价）；
- `zsh -n env.zsh` / `bash -n env.bash` / `bash -n tests/env_test.sh` 全过；
  `env.zsh` 与 `env.bash` 的 `wrg` 段机械转换后**逐字相同**（`/tmp/z2b.py` 那套检查）。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/shell/zsh && bash tests/env_test.sh          # 279 通过, 2 失败（2 条是 win 的老毛病）
docker exec wrg-test bash -lc 'cd /aosp/android16-release && source /wtool/shell/zsh/env.bash
  wrg system; echo rc=$?'                                     # 没有匹配 'system' 的目标名 / rc=1
docker exec wrg-test bash -lc 'cd /aosp/android16-release && source /wtool/shell/zsh/env.bash
  wrg -i vbmeta_systmmm'                                      # 三行表头 + main.mk:1383/1384
bash /tmp/wrg_cmp.sh                                          # 三后端 cmp + 耗时（脚本在容器 /tmp 里）
```

**已知边界（写进 `architecture.md` §4.5.1、README 的注释块与排错表了）**：

- **残留假阳性**：`$(error …)` / `$(warning …)` 这种跨行字符串的**续行**里是一句散文时，
  里面的词还是会被当成目标名 —— 真 AOSP 例：`wrg apk` 会命中
  `./build/make/core/Makefile:104:     Prebuilt apk found in PRODUCT_COPY_FILES: $(1), …`。
  试过的两条修法**都会误伤真目标**，所以**没做**：
  ① "行尾反斜杠 + 冒号前多于一个词"否决 → 真 AOSP 里有 24 条这种行，其中
  `systemimage-nodeps snod:`、`.PRECIOUS .INTERMEDIATE:`、`firework.o newdemo.o …:` 都是**真目标**；
  ② 跟踪 `define`/`endef` 块 → `reportmissinglicenses` / `reportallnoticelibrarynames` /
  `test-art-run-test` 这些真目标会被整块吞掉（它们确实定义在 `define` 块附近）；
  另外"上一行是不是续行"这条上下文 **rg 那条路拿不到**（`recheck` 只看到 rg 筛出来的行），
  加了它三条后端就不一致了；
- 模糊匹配**只从尾部截断**：开头/中间写错救不了；前缀越短命中越多（表头就是告诉你它截到多短）；
- 枚举那一步的退出码**不检查**（`PIPESTATUS` 和 zsh 的 `pipestatus` 写法不同，为了两份逐字等价就不取）；
  真出错时后面那次搜索照样会报。

---

## ❌ `wrg`：`$(error …)` 续行散文仍会被当成目标名（上面那条"已知边界"的残留）—— **不修（用户 2026-10-07 决定）**

**决定**：**不修（won't fix）** —— 用户 2026-10-07 拍板，理由（原话大意）：
"**无所谓，搜出来用户点进去看了就知道是 error 打印的，会自动忽略掉**。"
也就是说这条假阳性的成本只是"多一行噪音"，而命中行本身就是 `$(error \` 的续行散文，
点进去一眼认得出来，不值得为它去动匹配规则。

**留档（别删）**：现象描述、真 AOSP 例子（`build/make/core/Makefile:104` 的
`     Prebuilt apk found in PRODUCT_COPY_FILES: $(1), …`）以及"试过的两条修法**都会误伤真目标**"
的判据，仍留在上面那条 ✅ 的「已知边界」里：
① 行尾反斜杠 + 冒号前多于一个词 → 误伤 `systemimage-nodeps snod:` 这类真目标（真 AOSP 里 24 条）；
② 跟踪 `define`/`endef` 块 → 整块吞掉 `reportmissinglicenses` 这类真目标。

**（留档）万一将来回头修**：得先解决"跨行上下文"：要么让 rg 那条路也能看到上一行（例如改成列文件 + awk 读文件，
或者 rg `-U` 多行匹配再自己修正行号），要么做括号/续行配对。**先想清楚三后端一致性再动**，
别为了这一条把 `find`/`fd`/`rg` 的输出差异引回来。

---

## ✅ `wrg` 扩到第三类文件：Makefile 的构建目标名 —— 做完（2026-10-07，提交 `3f850ed`）

**做了什么**（`env.zsh` + `env.bash` 同改，两份的 `wrg` 段各 324 行（分隔线注释到函数结尾，和上一轮同一口径）、逐字等价）：

- 文件集合从两类扩成**三类**（按 basename 分类，`kind()`）：
  - `Android.bp` → `name: "X"`（不变）；
  - `Android.mk` → `LOCAL_MODULE` / `LOCAL_PACKAGE_NAME`（不变）；
  - **其它 Makefile**（`Makefile` / `makefile` / `GNUmakefile` / `*.mk`（`Android.mk` 除外）/ `*.mak`）
    → **构建目标名**：规则行 `^[[:space:]]*<目标>([[:space:]]+<目标>)*[[:space:]]*:` 冒号前那串
    **不含 `=` `$` `#` 的词**，外加 `.PHONY: <目标> …` 声明的词；一行多个目标逐个算，
    取第一个命中的（一行只输出一次、高亮只包那个词）；
- **反例**（都不算，测试逐条钉着）：`VAR := x` / `VAR ::= x`（冒号紧跟 `=` / `::=` 是赋值）、
  `VAR ?= x` / `VAR = x` / `export A := b`（扫到 `=` 否决整行）、`ifeq (...)` / `include $(...)`
  （目标不许有 `$`）、`$(MKTARGET): dep`、`# 注释: 里的冒号`、`.PHONY: $(TARGETS)`；
  `Android.mk` 只走 Android 语义，**它里面的规则行不算**（不然同一个目标被两套语义各算一遍）；
- **三条后端同步扩**：
  - rg：三次**粗筛** —— `-g Android.bp`、`-g Android.mk`、
    `--type amake --type make -g '!Android.bp' -g '!Android.mk'`（`amake` = `*.bp`/`*.mk`、
    `make` = `Makefile`/`*.mk`/`*.mak` 那一族；`Makefile.am`/`.in` 会被捎上，由 awk 按 basename 丢掉），
    合并后**再过一遍共用的 awk（新的 `WRG_PASS=recheck`）**才判命中 ——
    正则只是粗筛，最终判定回到同一段 awk，三条后端 + 两个 shell 才逐字一致。
    Makefile 那套粗筛：精确 `(^|[^[:alnum:]_])<值>([^[:alnum:]_]|$)`、模糊 `(?i:<值>)`
    （**模糊不能加词边界**：`-i system` 要能命中 `vbmetasystemimage`）；
  - fd：glob 扩成 `{Android.bp,Android.mk,Makefile,makefile,GNUmakefile,*.mk,*.mak}`；
  - find：`-name` 列表同步扩；
- 报错文字跟着改：`wrg: 当前目录树下没有 Android.mk / Android.bp` →
  `wrg: 当前目录树下没有 Android.bp / Android.mk / Makefile`（`Makefile.am` / `.in` 不算）；
- **顺手修了一个老 bug**：`Android.mk` 的高亮位置原来差一格
  （`vs = RSTART + RLENGTH - 1 - length(v)` 没区分"匹配尾巴是不是值的一部分"），
  `LOCAL_MODULE := libfoo` 会把 ` libfo` 包红；现在按各类文件分别算值起点，
  `LOCAL_MODULE := ^[[1;31mlibfoo^[[0m` 才对（新用例钉住）。

**验证到什么程度**：

- `bash tests/env_test.sh`（本机 WSL，rg 14.1.0 + fd 9.0.0 都在）：**199 通过 / 0 失败**
  （改前 129）；PATH 收窄成"只有 rg"→ 185、"只有 fd"→ 179、"rg/fd 都没有（纯 find）"→ 161，
  **四种都 0 失败**（后端相关用例按环境跳过）；
  容器里（`wrg-test`：rg + fdfind 都在、没有 `ip`）：**195 通过 / 0 失败** ——
  差的 4 条是 WSL / `ip addr` 那几条"按本机实际情况断言"的用例，与 wrg 无关（逐条 diff 过）；
- **容器实测**（`/aosp/android16-release`，真 AOSP）：
  - `wrg systemimage` → **5 行**，含 `./build/make/core/Makefile:924:.PHONY: systemimage`
    与 `:925:systemimage:`、`:3623:`、`:7645:`、`:7736:`；三后端 rg/fd/find **各 5 行、
    md5 全 `95222a35ede3d0885a28eb88b396bf4c`、`cmp` 逐字一致**；
  - `wrg -i systemimage` → **9 行**，多出 `systemimage-nodeps snod:`、
    `./build/make/core/main.mk:1383:.PHONY: vbmetasystemimage`、`:1384:vbmetasystemimage:`；
    三后端**各 9 行、md5 全 `dac4207661b26d386937c7e12694b32c`、`cmp` 一致**；
  - **独立交叉核对**（都不用 `wrg` 那段 awk）：① `find` 列出同一批文件（**19,346 个三类文件**，
    其中 Makefile 类 6,238 个），Python 另写一份判定 → 精确 5 行 / 模糊 9 行，
    **与 `wrg` 输出 `cmp` 逐字一致**；② `grep -E`（第三套正则引擎）按"规则行 + `.PHONY` 声明"数 →
    精确 **5 行**，**`cmp` 也一致**；③ 用户手动那条 `rg --type amake --type make systemimage`
    是 **31 行**（它按"文本任意出现"算），`wrg` 的 5 行**全在里面**；多出来的 26 行正是规格里
    要排除的（`systemimage_intermediates :=$= …` 这种赋值、`#` 注释、依赖列表里的名字）；
  - **awk 实现交叉**：宿主机是 **gawk 5.2.1**、容器里是 **mawk 1.3.4**，同一条命令三个后端
    输出**逐字一致**（`cmp`）；
  - 耗时（容器，两轮，页缓存热）：精确 `systemimage` → **rg 2.73/2.70s、fd 2.21/2.14s、
    find 10.29/10.26s**；模糊 `-i systemimage` → **rg 2.75/2.77s、fd 2.14/2.14s、find 10.26/10.33s**
    （fd 比 rg 略快，和上一轮同一个形状：rg 要为三套写法各遍历一次全树）；
  - 高亮原始字节：`NO_COLOR= WRG_COLOR=always wrg systemimage | cat -v` →
    `./build/make/core/Makefile:925:^[[1;31msystemimage^[[0m:`（只包目标名那一段）；
- `zsh -n env.zsh` / `sh -n env.zsh` / `bash -n env.bash` / `sh -n env.bash` /
  `bash -n tests/env_test.sh` 都过。

**判据（可原地重跑）**：

```sh
cd ~/self/wtool/shell/zsh && bash tests/env_test.sh        # 199 通过, 0 失败
docker exec wrg-test zsh -c 'export WTOOL_PROJECT_DIR=/wtool/shell/zsh;
  . /wtool/shell/zsh/env.zsh; cd /aosp/android16-release;
  for v in rg fd find; do WRG_SEARCH=$v wrg systemimage | md5sum; done'   # 三个 md5 一样
docker exec wrg-test zsh -c 'export WTOOL_PROJECT_DIR=/wtool/shell/zsh;
  . /wtool/shell/zsh/env.zsh; cd /aosp/android16-release;
  NO_COLOR= WRG_COLOR=always wrg systemimage | cat -v | head -3'          # ^[[1;31msystemimage^[[0m
```

**已知边界（都写进 `architecture.md` §4.5.1 / README 的排错表了）**：

- `Makefile.am` / `Makefile.in` **不在**文件集合里（rg 的 `--type make` 会捎上，awk 按 basename 丢掉）；
  只有它们的树算"没有可搜文件"；
- `systemimage_intermediates` 这类**变量名**按规格**不算**目标名（它是 `:=` 赋值）——
  `wrg -i systemimage` 不会给出它；要找变量得用 `rg`。

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

## ✅ 2026-10-07：`proxy_on` / `proxy_off` 从用户 .zshrc 搬进项目（值改成"问用户要"）

- **需求**（用户原话大意）：把 `.zshrc` 里写死 `127.0.0.1:7897` 的 `proxy_on`/`proxy_off`
  搬进 `shell/zsh`，**参考 `win` 的风格，操作前要求用户输入 `PROXY_IP` 和 `PROXY_PORT`**。
- **实现**：两个 shell 文件里各加一节（**2810 字节逐字相同**）；取值顺序
  参数 → `$PROXY_IP`/`$PROXY_PORT` → 交互式询问；`[ -t 0 ]` 为假时 **rc=2 + 提示，绝不挂住**；
  端口非数字 rc=2；`all_proxy` 用 `socks5://`；`no_proxy` **存原值 + 追加**、`proxy_off` 还原；
  定义前 `unalias proxy_on proxy_off`（老别名优先于函数，不清掉函数轮不到）。
- **验证**：`tests/env_test.sh` 新增 **9×2 = 18 条**（参数/环境变量/非交互 rc=2/非法端口/
  no_proxy 追加/还原/清六个保留 IP 端口/别名被 unalias/pty 交互式询问）→ 本机 **517 通过 / 2 失败**
  （那 2 条是既有的 `win` share 前缀用例，与本次无关）；两个 shell 行为逐字一致。
- **可重跑判据**：见 `architecture.md` §4.6 末尾那段 for 循环（bash/zsh 各跑一遍，输出注释里那四行）。
- **注意**：用户 `.zshrc` 第 41–57 行那两条别名现在**失效**（被 unalias），可以删；不删也不影响。

## ✅ 2026-10-07：`win` 不再自动探测 IP —— 只认 `WIN_IP`

- **需求**（用户原话大意）：`win` 不要自己用 `ip addr` 探测，"像阿里云服务器一样，探测出来的不一定准，
  就让用户配置 `WIN_IP` 就可以了"。
- **改法**：`_win_ip` 收缩成"有 `$WIN_IP` 就打印它，否则返回 1"（删掉 `ip -4 addr` 那整段 awk）；
  `_win_server` 的报错文案同步成 `win: 没设 WIN_IP（本命令不自动探测 IP —— 服务器上探到的常常是内网地址）。`
- **测试**：删掉"从 ip addr 兜底"那条（它依赖本机网卡，本身就不稳），换成 4 条：
  `_win_ip` 没设 → rc=1；设了 → 原样打印；`win`（非 WSL）没设 `WIN_IP` → rc=1 且 **stdout 空**；
  设了 → 两行都在。两 shell 各 4 条。
- **判据**：`tests/env_test.sh` 全绿（除既有 win share 前缀那 2 条）；
  `WIN_IP=203.0.113.7 zsh -c '. env.zsh; this_is_wsl(){ return 1; }; win'` → 两行。

## ✅ 2026-10-07：两条"常驻失败"的 `win` 用例其实是**测试写错**（EPIPE 噪音并进 stdout）

- **现象**：`tests/env_test.sh` 长期 `2 失败`（bash/zsh 各一条）：
  `win（非 WSL）按最长前缀挑 share…（期望 [//10.1.2.3/ws/ab] 实际 [//10.1.2.3/ws/ab
…write error: Broken pipe]）`。
- **根因**（不是 `win` 算错）：用例里写的是 `win | head -1`，`head` 读一行就关管道 →
  `win` 的第二行（scp 那行）`echo` 撞 **EPIPE**，shell 把 `write error: Broken pipe`
  打到 **stderr**；而测试助手 `sh_eval` 是 `2>&1` 合并的 → 噪音进了被测值。
  `--dry-run` 式的自查：单跑那段（不接 `head`）输出完全正确，`//10.1.2.3/ws/ab` ✓。
- **修法**：用例改成 `win 2>/dev/null | head -1`（只取第一行时明确丢掉 stderr）。
- **结果**：**525 通过 / 0 失败**（项目首次全绿）。
- **教训（写给下一个人）**：给**多行输出**的命令接 `| head` 时，若那条流水线又把 stderr 并进 stdout，
  就会把 EPIPE 噪音当成"实际值"——断言会以一个极像真 bug 的样子失败。
  判据：把同一条命令**不接 `head`** 跑一遍，输出对 → 就是测试的锅。
