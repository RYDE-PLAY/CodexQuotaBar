# Codex Quota Bar

极简 macOS 状态栏工具。
图标从 12 点开始顺时针变淡，表示已消耗的 5 小时额度；点击查看 5 小时和周剩余额度。

已安装 DevSpace 的用户还可通过菜单开关控制服务；开启后会在后台持续运行并随登录启动，卸载本工具前请先关闭该开关。

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
