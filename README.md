# Codex Quota Bar

极简 macOS 状态栏工具：图标从 12 点开始顺时针变淡，表示已消耗的 5 小时额度；点击查看 5 小时和周剩余额度。

## 安装

需要 macOS 14+、Xcode Command Line Tools，以及已登录的 Codex CLI（也可使用 ChatGPT.app 内置的 Codex）。

```sh
git clone https://github.com/RYDE-PLAY/CodexQuotaBar.git
cd CodexQuotaBar
./Scripts/build-app.sh
cp -R Build/CodexQuotaBar.app /Applications/
open /Applications/CodexQuotaBar.app
```
