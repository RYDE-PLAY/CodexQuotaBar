# Codex Quota Bar

极简 macOS 状态栏工具。
图标从 12 点开始顺时针变淡，表示已消耗的 5 小时额度；点击查看 5 小时和周剩余额度。

## DevSpace 控制

菜单中提供一个 `DevSpace` 开关，可把本机 `devspace serve` 注册为当前用户的 LaunchAgent。打开后即使退出 CodexQuotaBar，DevSpace 也会继续由 `launchd` 管理，并在下次登录时自动启动；关闭开关会停止并移除该 LaunchAgent。

运行环境会自动探测。支持当前 `PATH`、登录 shell、nvm、fnm、Volta、asdf、mise、Homebrew 等常见 Node 安装方式。对于 nvm 这类版本目录，应用会同时解析对应的 Node 与 DevSpace 入口，并将绝对路径写入 LaunchAgent，避免依赖 GUI/launchd 的 PATH。若 nvm 切换版本导致旧路径失效，CodexQuotaBar 下次启动时会重新探测并修复。

为避免误伤其他服务，如果 `127.0.0.1:7676` 已被未受 CodexQuotaBar 管理的进程占用，应用不会抢占或杀掉该进程。日志位于：

```text
~/Library/Logs/CodexQuotaBar/devspace.log
~/Library/Logs/CodexQuotaBar/devspace-error.log
```

LaunchAgent 位于：

```text
~/Library/LaunchAgents/red.ryde.codexquotabar.devspace.plist
```

删除 CodexQuotaBar 前建议先在菜单中关闭 DevSpace；否则 LaunchAgent 会继续独立运行。

## 安装

可以使用以下任一方式安装。

1. 直接下载：

    从 [Releases](https://github.com/RYDE-PLAY/CodexQuotaBar/releases/latest) 下载 ZIP，解压后将应用拖入「应用程序」。支持 Apple Silicon 和 Intel；需要 macOS 14+ 和已登录的 Codex CLI。安装包尚未公证，若首次打开被拦截，在「系统设置 → 隐私与安全性」中选择「仍要打开」。

2. 从源码构建：

    需要 macOS 14+、Xcode Command Line Tools，以及已登录的 Codex CLI（也可使用 ChatGPT.app 内置的 Codex）。
  
    ```sh
    git clone https://github.com/RYDE-PLAY/CodexQuotaBar.git
    cd CodexQuotaBar
    ./Scripts/build-app.sh
    cp -R Build/CodexQuotaBar.app /Applications/
    open /Applications/CodexQuotaBar.app
    ```
