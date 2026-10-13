# AGENTS.md —— shell/zsh

> 先读用户级 `~/.dsh/AGENTS.md`（工作区通用规则）和仓库根 `AGENTS.md`（多仓库工作区规则），
> 本文件只讲**这个项目**的事。**现状**看 `architecture.md`，为什么这么定看
> `harness/docs/adr/0045-wtool-redesign/`，接下来做什么看 `BACKLOG.md`。

## 这个项目是什么

**zsh 的源码**（上游 `zsh-users/zsh` 的 fork）+ **按发行版各编一份的 docker 构建**。
按 ADR-0045 的分类它是 **③ 类 docker 跨发行版构建项目**（`wtool.xml` 根元素
`kind="docker"`）—— 三个类里唯一"要 build、要 `__layer`、碰 `__output`"的那一类。
它是 **D27 / 第 ⑦.4 块**里给 docker 分层这条线立的**试验田**（`editor/astronvim_v5`
被用户屏蔽了，见 DESIGN §1.4 末段）。

**它是 wtool 的子项目**：装、卸、编都由 wtool 按 `wtool.xml` + `build/*.tsv` 执行。
仓库里**没有**安装入口脚本（`scripts/install.sh` 是引擎调用的**项目脚本**，不是给你敲的）。

| 文件 | 是干什么的 |
|---|---|
| （上游那一堆） | **zsh 源码本身 + 上游文档**。除下面这几个新文件外，一个字都别改 |
| `wtool.xml` | 项目声明：`kind="docker"`、`<zshrc>/<bashrc>`、`<build kind="docker"/>`、`<export_usr src="__output/usr"/>` |
| `build/targets.tsv` | 三个目标系统 → 基础镜像 / 代号 / glibc。**加一个发行版 = 加一行** |
| `build/layers.tsv` | 层清单（一层 `main`），容器里跑 `scripts/build.sh --in-docker` |
| `build/export.filter` | 导出过滤；今天是空的（理由写在文件里） |
| `scripts/build.sh` | 双模式：`--in-docker`（引擎用）/ 不给参数（宿主上一条命令做完） |
| `scripts/install.sh` | 引擎在 `wtool install` 时跑；职责是**验收**（选中的那套必须是本机的、能跑） |
| `env.zsh` / `env.bash` | shell 集成，两份**逐字等价**（差异只有 shell 名 + bash 没有 fpath 那一段） |
| `README.md` | **给用户的完整说明书**：为什么要三套、怎么选、怎么编、怎么验 |
| `architecture.md` | 这个项目**现在长什么样** |
| `BACKLOG.md` | 这个项目还剩什么 |

## 铁律

1. **上游的东西不要动。** `README`、`INSTALL`、`Doc/`、`Src/`、`Functions/`、`ChangeLog`…
   都是上游的。**要改 zsh 本身的行为**（打补丁）是另一件事：先开一条 `BACKLOG.md` 条目、
   写清为什么，别顺手改。**这份 fork 的可辨识度就是资产** —— 上游一升级就能 diff 出来。
2. **`env.zsh` 与 `env.bash` 必须同改。** 两份的差异只允许是：① 注释里那句 shell 名、
   ② 报错文案里的 `~/.zshrc` / `~/.bashrc`、③ env.zsh 里 `fpath` / `module_path` 那一段
   （bash 没有这两个东西，那边用一段注释说明"这里没有对应物，是有意的"）。
   改任何共用行都要两边一起改 —— 症状是"某个 shell 里 zsh 是 command not found，
   而 `wtool install` 明明说装好了"。
3. **`wtool.xml` 的注释里不能出现连续两个减号。** XML 规范禁止（`--` 在注释里非法），
   `ElementTree` 会直接报 `not well-formed`。写 `--prefix` 这种长选项时，
   改写成中文描述（"prefix 那一段"）或者放到 `README.md`/`architecture.md` 里 ——
   **已经踩过一次**：整个项目从 `list-projects` 里消失，症状像"引擎没扫到这个项目"。
4. **别在大小写不敏感的文件系统上 clone 本仓。** 上游有 `Scripts/`，我们有 `scripts/`
   （引擎契约写死 `scripts/{build,install}.sh`，改不了）—— macOS 默认、Windows 上会撞。
5. **`scripts/build.sh` 在容器里不往项目目录写东西**（`/proj` 是**只读**挂的）。
   产物只落 `/root/.wtool/usr`；引擎按 `root/.wtool/*` 导出。往里写会静默失败
   （只读）或者污染产物。
6. **装完必须自己验**（别只信 `wtool install` 的最后一行）：
   `zsh --version` + `zsh -ic 'echo INTERACTIVE_OK'`。装错了就先
   `wtool uninstall shell/zsh` —— `$WTOOL_HOME/usr/bin` 在 `PATH` 最前，
   错的 zsh 就是你**下一个登录 shell**。
7. **改任何东西之后跑一遍**（见 `architecture.md` §5 的判据）：
   `sh -n scripts/*.sh`、`wtool validate shell/zsh`、
   `cd ../../wtool-base-tools/tests && sh run_all.sh`。

## 分支与提交（这个仓**不是**普通 wtool 仓）

* 本仓是**上游的 fork**，默认分支叫 `master`（上游的名字）。**`master` / `main` 都不动。**
* `ds_dev` = **改动只提交在这里**（工作区统一规矩，`~/.dsh/AGENTS.md` §1）。
  清单 `.repo/manifests/default.xml` 里 `revision="ds_dev"` 就是钉它。
* `wsw` = 留给"构建适配分支"的名字（和清单里 `tools/wsw-repo-fork` 的 `revision="wsw"`
  同一个约定）。**今天是空分支、与 `ds_dev` 同一个提交** —— 设计里没写清这个仓该用哪个，
  按任务口径"两个都建、适配提交到 `ds_dev`"办。
* **不 push**：推 GitHub 是用户拍板之后的独立一步。
* 提交一律 `-m`；`git add` 之前先 `git diff` 看一遍；见到 `【wsw: …】` 批注要读、照做、删掉。

## 本地怎么快速试（不装到 $HOME）

```sh
sh scripts/build.sh                  # 编三个发行版 + 选本机那套（要 docker，约 5 分钟）
wtool validate shell/zsh             # 清单 + 产物形状对不对
wtool install --dry-run shell/zsh    # 看计划，不动手
```

**真装**（会改 `$WTOOL_HOME`，`zsh` 会排到 `PATH` 最前）：只有在
`zsh --version` + `zsh -ic 'echo ok'` **两个都过了**之后才允许，而且装完立刻复验一遍。
