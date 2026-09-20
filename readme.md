# 说明

个人 shell 的别名/函数集合：`cw`（跳到 repo 根）、`gba`、`pdd`/`pss`（记路径再跳回来）、
WSL 的 `win` / `start`，以及 `gs` / `gl` / `s` / `kls` 这类短别名。

## 两个 shell 各一份

| 文件 | 给谁 | 被谁 source |
|---|---|---|
| `env.zsh` | zsh | `~/.zshrc` 里的 wtool 块 |
| `env.bash` | bash | `~/.bashrc` 里的 wtool 块 |

两份**内容等价**（同一批别名/函数、同样的行为）。受众里有人机器上没有 zsh，
所以 bash 版是必需品；改一个就要在另一个里做等价修改。

## 测试

```sh
bash tests/env_test.sh     # 20 条；没装 zsh 就只测 bash
```

它把同一张用例表喂给两个 shell：别名在不在、`_up_to_have_dir` / `cw` 能不能找到
`.repo`、`pdd`/`pss` 能不能跳回来、WSL 探测函数在**当前这台机器**上给不给对的返回码
（本机是 WSL 就按 WSL 断言，不写死）。

> 历史：这里原来只有 `env.zsh`，配置是从 `mytool` 的 `source_all_env.sh` 链上来的；
> 现在由 wtool 的块加载，不再需要那个链条。
