# 下载 shell/zsh

这一版：`ds_dev-2026-10-14`（2026-10-14）

| 文件 | 大小 | 是什么 | 直链 |
|---|---|---|---|
| `dist.json` | 916B | — | https://github.com/allinkernel/wtool-zsh/releases/download/ds_dev-2026-10-14/dist.json |
| `release-hash.txt` | 78B | — | https://github.com/allinkernel/wtool-zsh/releases/download/ds_dev-2026-10-14/release-hash.txt |
| `release.zip` | 9.7M | 产物包 | https://github.com/allinkernel/wtool-zsh/releases/download/ds_dev-2026-10-14/release.zip |
| `source-hash.txt` | 77B | — | https://github.com/allinkernel/wtool-zsh/releases/download/ds_dev-2026-10-14/source-hash.txt |
| `source.zip` | 4.5M | 源码包 | https://github.com/allinkernel/wtool-zsh/releases/download/ds_dev-2026-10-14/source.zip |

## 怎么装

**装了 wtool 的机器**（推荐，校验和拼分卷它自己做）：

```sh
wtool download-release shell/zsh   # 按仓库里提交的 scripts/release.json 下载 + 校验
wtool unpack-release shell/zsh     # 拼分卷 + 解到 __output/
wtool install shell/zsh            # 装到本机（登记、软链、shell 集成）
```

**只有浏览器的机器**：把上面每个文件点下来，放进项目的 `__release/` 目录，
再在那台机器上跑后两条命令 —— `unpack-release` 认包里的 `dist.json`，
缺了哪一卷它会说清楚。

`install` 只认 `release.zip`（产物包），不需要 `source.zip`。
