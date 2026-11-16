# merlin_tailscale_arm384

## 是什么？

ks的改版梅林设备上面运行的tailscale的包。

## 支持机型

以ac68u为例的ks改版梅林固件路由器。384/386版本

## 为什么停在 1.80.3

AC68U 这类机型的梅林 384/386 固件内核是 Linux 2.6.36。

- Tailscale 1.80.3 用 Go 1.23 构建，Go 1.23 支持 Linux 2.6.32+。
- Tailscale 1.82.0 起改用 Go 1.24，Go 1.24 要求 Linux 3.2+。

因此将 1.80.3 固定为旧内核的兼容候选版本，不跟随上游自动升级。这是根据工具链要求做出的选择，不是 Tailscale 官方对 AC68U 的支持声明；ARM 构建、启动、联网和路由能力仍需实机验证。依据：[1.80.3 工具链](https://github.com/tailscale/tailscale/blob/v1.80.3/go.toolchain.branch)、[1.82.0 go.mod](https://github.com/tailscale/tailscale/blob/v1.82.0/go.mod)、[Go 内核要求](https://go.dev/doc/go1.23#linux)。

## 登录使用

1. 在软件中心离线安装本项目生成的 `tailscale.tar.gz`，重新打开插件页面；若仍是旧页面，请强制刷新浏览器。
2. 打开插件开关，等待 `tailscaled` 启动。
3. 点击“登录账号”。页面会显示“打开授权链接”，也可选中下方输入框复制链接。
4. 在浏览器打开链接，登录与手机、电脑或群晖相同的 Tailscale 账号，完成设备授权。
5. 页面每 5 秒刷新一次状态。若需要管理员批准，到 `Admin console` 中批准设备。

`Admin console` 是管理后台入口，直接打开它不会绑定当前路由器。登录按钮使用现有守护进程的本地 Unix socket，不增加监听端口；只启用运行状态并请求授权，保留现有账号配置、DNS、路由和防火墙设置，已登录时不会重新认证。

登录功能要求路由器上的 `curl` 支持 `--unix-socket`。未启动、本地接口错误和 Tailscale 自报的健康问题会显示在登录区域。若一直取不到授权链接，检查页面顶部的“tailscaled运行日志”，排查路由器自身的 DNS、时间和连接问题；更换版本不一定能解决网络故障。

## 构建

```sh
./build.sh
```

脚本从 Tailscale 官方下载 `tailscale_1.80.3_arm.tgz`，替换 `tailscale/bin/` 下的两个程序，生成 `tailscale.tar.gz`，并更新 `version`、`config.json.js`。下载或打包失败时不会覆盖原文件。

若电脑暂时无法访问下载服务器，但已有本项目的 1.80.3 二进制，可显式离线重新打包：

```sh
./build.sh --offline
```

离线模式需要安装 Go，用 `go version -m` 核实两个程序的内嵌版本、工具链、系统和架构，避免给旧二进制贴上新版本号；不重新编译程序。有 Go 的在线构建也执行相同检查。

两个二进制合计约 47MB，安装前检查 `/jffs` 可用空间。构建时若找到 `llvm-strip`，会尝试去掉调试信息；也可用 `STRIP=/path/to/strip ./build.sh` 指定工具。实际节省量取决于上游构建。

安装后可在路由器 SSH 中确认：

```sh
/koolshare/bin/tailscale version
df -h /jffs
```


[下载本仓库安装包](https://github.com/gofunbox/merlin_tailscale_arm384/raw/refs/heads/main/tailscale.tar.gz)（需先将成功构建的安装包同步到仓库；本地修改不会自动更新线上下载）
