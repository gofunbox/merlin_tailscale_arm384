# merlin_tailscale_arm384

适用于 AC68U 等带软件中心的 Koolshare 改版梅林 384/386 固件。

## 下载和安装

到 [GitHub Releases](https://github.com/gofunbox/merlin_tailscale_arm384/releases/latest) 下载附件，软件中心选择“离线安装”：

| 附件 | 用途 |
| --- | --- |
| `tailscale.tar.gz` | 推荐。小安装包只含插件网页、脚本等，安装时从 Tailscale 官方下载程序。 |
| `tailscale-full.tar.gz` | 完整离线包。包含官方程序，用于路由器无法访问官方下载站的情况。 |
| `SHA256SUMS` | 核对下载的附件是否完整。 |
| `version`、`config.json.js` | 小安装包的版本和 MD5 元数据。 |

不要下载 GitHub 自动生成的 `Source code` 压缩包来安装。

小包安装会下载固定的 `https://pkgs.tailscale.com/stable/tailscale_1.80.3_arm.tgz`。下载、解压、检查架构、在路由器上执行版本检查均通过后，才停止并替换旧插件；下载失败或程序不能运行时保留现有插件。需要路由器自身能访问官方站点，下载仍约 26MB，只是不再随源码推送和手动上传插件包。安装后的程序仍约占 47MB，检查 `/jffs` 和 `/tmp` 空间。

## 登录

安装后强制刷新插件页面，打开开关，点击“登录账号”，再点击“打开授权链接”。登录与其他设备相同的 Tailscale 账号；页面每 5 秒刷新状态。如果需要管理员批准，到 `Admin console` 批准设备。

登录接口通过本机 Unix socket 读取真实状态，保留已有账号、路由和 DNS 设置，不增加监听端口。需要路由器 `curl` 支持 `--unix-socket`。连接错误会显示在登录区域，也可查看“tailscaled运行日志”。后台账号登录和官方安装包下载是两个不同的连接步骤。

## 版本范围

插件版本在 `tailscale/version`，当前为 `1.80.3.1`；实际 Tailscale 客户端版本单独固定在 `tailscale/tailscale.version`，为 `1.80.3`。

1.80.3 的上游工具链为 Go 1.23；1.82.0 起要求 Go 1.24，而 Go 1.24 要求 Linux 3.2+。因此为 AC68U 的 Linux 2.6.36 选择 1.80.3 作为兼容候选，不代表上游保证 AC68U 可用；仍需实机验证。

依据：[1.80.3 工具链](https://github.com/tailscale/tailscale/blob/v1.80.3/go.toolchain.branch)、[1.82.0 Go 要求](https://github.com/tailscale/tailscale/blob/v1.82.0/go.mod)、[Go Linux 内核要求](https://go.dev/doc/go1.23#linux)。

## 构建

```sh
./build.sh          # 生成小包，不联网
./build.sh --full   # 从官方固定地址下载程序，生成完整离线包
```

所有产物只写入被 Git 忽略的 `dist/`。不再提交 `tailscale/bin/`、根目录 `tailscale.tar.gz`、`version` 或 `config.json.js`。即使本机仍缓存着旧的 `tailscale/bin/`，小包也会明确排除它。

## 自动发布 Release

`.github/workflows/release.yml` 在 PR 上运行检查并上传小包作为 Actions artifact。推送版本标签时，检查通过后自动构建两个安装包、校验文件和元数据，发布到 GitHub Releases：

```sh
git tag v1.80.3.1
git push origin v1.80.3.1
```

标签必须与 `tailscale/version` 一致。后续修改插件时，先递增插件版本再创建新标签，不必改变客户端版本。也可在 Actions 手动运行工作流，填写已经存在的同名标签；不应重复发布已经发布的版本。工作流使用内置 `GITHUB_TOKEN`，不需要配置个人访问令牌。Fork 若未启用 Actions，需要先在 Actions 页面启用。

## 已经提交过大文件怎么办

`.gitignore` 只影响之后的文件跟踪，无法移除旧提交里已经存在的对象。如果本地尚未推送的提交含有约 73MiB 的新二进制和安装包，继续推送那个分支仍会上传它们。

本改动放在基于远端原始提交创建的新分支，避免新提交携带这些大对象。先把旧分支保留作备份，确认没有未提交改动，再切到新分支；不要把带大文件的旧本地提交合并回新分支。远端已存在的旧版本历史不重写。

```sh
git status --short
git branch backup/before-small-installer
git fetch origin
git switch -c small-installer origin/codex/install-time-download
```

也可直接在 GitHub 合并该分支的 PR，再从更新后的 `origin/main` 开始后续工作。无需再次上传这些新大文件。

## 检查

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
node tests/test_auth_ui.js
```

检查使用下载和 LocalAPI 测试替身，不访问真实账号，也不等于 AC68U 实机测试。
