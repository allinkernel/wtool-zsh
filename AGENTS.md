# AGENTS.md（shell/zsh）

> 给后续的 AI 助手看。用户级规则在 `~/.dsh/AGENTS.md`，工作区规则在根目录 `AGENTS.md`；
> 本文件只讲**动这个仓库**必须知道的事。

## 1. README.md 是这个项目给用户的完整功能说明书

- **代码/配置一有变化，必须同步更新本仓库的 `README.md`** —— 别让 README 和代码说两种话。
  改了 `env.zsh` / `env.bash` 里的别名、函数、报错文字、退出码、环境变量，都要回到
  README 里改对应那一行；加了新东西就补一行，删了就把那一行删掉。
- **README 里不写"怎么装"** —— 安装统一由 wtool 管，README 的「安装」一节只有一句话
  加一个链接，指向 GitHub 上的 wtool README（`allinkernel/wtool` 仓库的 `README.md`）。
  项目自己的 `install.sh` / `uninstall.sh` 已经退休，**别把它们写进文档**，
  也别在文档里叫用户直接跑（详见任务口径：以后安装强依赖 wtool）。
- **README 的章节结构**（改动时保持这个骨架，别自创一套）：

  | 章节 | 写什么 |
  |---|---|
  | 功能说明 | 这个项目**到底提供什么**：别名、函数、加载方式……逐条说明，**每条都能在代码里找到出处** |
  | 安装（由 wtool 统一管） | 一句话 + wtool README 链接；本仓库只是源码/配置 |
  | 配置项 | 读哪些环境变量 / 配置文件，各自的默认值和影响 |
  | 快捷键 | key binding / widget；本仓库没有就明确写"没有"，并指出快捷键实际来自哪些项目 |
  | 排错 | 常见报错文字 → 原因 → 怎么办 |
  | 测试 | 跑什么命令、几条 |
  | 文件 | 每个文件一句话 |

- **只写从代码里读出来的东西。** 命令、变量名、报错文字、退出码都要对着
  `env.zsh` / `env.bash` / `wtool.xml` / `tests/env_test.sh` 核过再写；
  核不实的宁可不写（README 是给用户的功能说明书，写错比不写更坏）。

## 2. 这个仓库的硬规矩

- **`env.zsh` 和 `env.bash` 必须同改。** 两份内容等价：同一批别名、同样的函数行为、
  同样的报错文字、同样的退出码。只改一份的后果是"那个 shell 的用户敲命令
  command not found"，而文件里看起来明明装过。
- zsh 版允许用 zsh 专有语法（`${var:h}`、`funcstack`、`<->`……），bash 版**不行**
  （`${var%/*}` + `case`；别把三元运算符那类 bashism 写进 bash 版，`sh -n` 查不出来）。
- `wtool.xml` 里项目 id 是 `shell/zsh`，**这是契约**（rc 文件的块名、中转链接路径
  `~/.wtool/wtool-work-dir/links/shell/zsh` 都用它），改名要连带改文档。
- `priority=20`：必须排在 `shell/oh-my-zsh`(10) 之后 —— 主题/补全先就位，
  这里的别名才盖得住。别随手改优先级。
- `WTOOL_PROJECT_DIR` 的默认值是给"单独 source 本项目"兜底的；
  正常路径由 wtool 块导出，别在文件里改成写死的绝对路径。

## 3. 验证（改完必须跑）

```sh
bash tests/env_test.sh     # 20 条，应该全绿；没装 zsh 就只跑 bash 那 10 条
```

- 用例表两个 shell 共用，断言别名、`_up_to_have_dir` / `cw`、`pdd`/`pss`、
  WSL 探测的返回码（按本机实际情况断言）。
- 测试自己造临时工作区，**不要**在真 `$HOME` 上试（工作区级 AGENTS.md 里的硬规矩）。
- 改完 shell 至少 `sh -n` 一遍，但**别把 `sh -n` 当成"能跑"**。
- 提交只提交到 `ds_dev`，`git add` 之前先 `git diff` 看一遍；不 push、不动 `main`。
