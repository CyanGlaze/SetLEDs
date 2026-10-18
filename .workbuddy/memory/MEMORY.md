# SetLEDs 项目要点

黑苹果（macOS 26 Tahoe，联想 Legion 笔记本）让物理 NumLock 键切换小键盘。

## 硬件/系统事实（调试结论）
- 内置键盘走 ITE Device(8910)（USB vid=0x048d pid=0xc100），顶层 collection 是 vendor-defined(0xFF79)，按"键盘 usage"匹配的枚举看不到它；但它才是发出 NumLock 键事件(usage 0x53)的设备。
- LED 写入只需发给标准键盘设备 'Keyboard'(vid=0x05ac pid=0xffff, usage 1/6)，即 `setleds +num` 的路径，EC 固件会跟着切小键盘。
- 普通用户进程打开 HID 一律 0xe00002e2（TCC 拒绝），root 可用。
- 曾下载的 xiaoMGit Y7000 NumLockFix 的 plist 是 302 跳转 HTML 假文件，从未生效（已于 install.sh 中清理）。

## 方案（2026-10-18 最终：用户级 LaunchAgent + 输入监控授权）
- **root LaunchDaemon 在 macOS 26 上不可行**：系统域守护进程无 GUI 会话，IOHIDManagerOpen 即使 root 也返回 0xe00002e2（已实测）。终端里 sudo 可用是因为在用户 GUI 会话内。
- setleds(main.c) 内置 -d/--daemon 模式：NULL 匹配监听全部 HID 的 0x53 → 复用 setAllKeyboards(^num) 切换；+num/-num 定初始状态。前台 `sudo setleds -d +num` 已实测可切换小键盘。
- 正确安装方式：用户级 LaunchAgent（com.setleds.numlockd，~/Library/LaunchAgents/），二进制放 ~/Library/Application Support/setleds/setleds（编译时嵌入 Info.plist + adhoc 签名，TCC 显示 "NumLock daemon"），日志 ~/Library/Logs/setleds.log，系统设置→隐私与安全性→输入监控 一次性授权。
- 项目文件：main.c + main.h（依赖）+ Info.plist（编译用）+ Makefile + install.sh/uninstall.sh；豆包旧文件在 archive-doubao/。
- 注意：重建二进制后 CDHash 变化，输入监控授权可能要重新勾选；守护进程运行时不要再手动前台跑 -d（双进程双重切换）。

## 用户习惯
- 用户对源文件命名不精确（称 main.c 为 main.py），手动运行 setleds 时习惯 sudo。
