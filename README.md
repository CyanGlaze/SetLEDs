# setleds — 用 NumLock 键切换小键盘

在黑苹果（macOS 26）上，物理键盘的 NumLock 键默认无法切换小键盘。本工具在 HID 层监听 NumLock 按键，翻转键盘 LED，从而让 NumLock 直接控制小键盘的开关。

- 唯一源码：`main.c`（含 `-d` 守护监听模式）
- 编译产物：`setleds`
- 安装方式：用户级 LaunchAgent（开机自启）+ 一次性"输入监控"授权

---

## 方式一：一键远程安装（推荐）

适合把项目放到 GitHub 后，给别的 Mac 直接装。

> 前提：你已把编译好的 `setleds` 二进制上传到云端（如 GitHub Release），并把 `setleds.sh` 顶部的 `BINARY_URL` 改成你的真实地址。

终端里执行下面任意一条：

```bash
# 先下载脚本再运行
bash setleds.sh

# 或者直接管道执行（脚本会自动从云端拉取二进制）
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/setleds/main/setleds.sh | bash
```

脚本会自动完成：下载二进制 → 安装 LaunchAgent → 打开"输入监控"授权面板。
下载完成后**仍需你手动授权一次**（见下方"首次必做"）。

---

## 方式二：手动安装（本地编译）

适合你自己在本机开发、或想从源码构建。

```bash
make              # 在当前目录编译出 ./setleds
./install.sh      # 安装为登录自启 + 引导输入监控授权
```

`make clean` 可删除编译产物。安装完成后同样需要手动授权一次。

---

## 首次必做：授予"输入监控"权限

因为工具要监听键盘按键，macOS 强制要求授权（所有键盘类工具都一样，无法绕过）：

1. 打开 **系统设置 → 隐私与安全性 → 输入监控**
2. 点击 **+** ，在文件对话框按 **Cmd-Shift-.** 显示隐藏文件夹，添加 `setleds`
   （用脚本安装时，Finder 已自动帮你定位并高亮了该文件，直接拖进去也行）
3. 确保它旁边的**开关是打开的**

授权后按 NumLock 即可切换小键盘，重启后自动生效。

---

## 使用

- 直接按 **NumLock**（或 Fn+NumLock，视机型）切换小键盘
- 命令行手动控制（需 root，仅临时用）：
  - `sudo setleds +num` 打开小键盘
  - `sudo setleds -num` 关闭
  - `sudo setleds ^num` 翻转状态
  - `sudo setleds -d +num` 以前台守护模式运行（调试用）

---

## 卸载

```bash
./uninstall.sh
```

并可在"输入监控"里把 `setleds` 条目移除。

---

## 注意事项

- **必须用用户级 LaunchAgent**：macOS 26 下即使是 root 的系统级守护进程也打不开 HID 设备（无 GUI 会话会被拒），所以本工具不采用 root 守护进程方案。
- **二进制跨机器签名**：`make` 产出的是 ad-hoc 签名，只在本机有效。发给别人前建议用 Developer ID 证书重签（`codesign --sign "Developer ID Application: 你的名" setleds`），否则对方首次运行可能被 Gatekeeper 拦截。一键安装脚本已自动清除隔离属性以降低阻力。
- **不要重复监听**：LaunchAgent 已在后台运行，请勿再手动 `sudo setleds -d`，两个进程同时监听会互相抵消，看起来像"没反应"。
- **重新编译安装后**：若换了二进制，可能需要在"输入监控"里把开关重新勾选一次。
