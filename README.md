Sing-Box Shell
一个用于在 Linux 网关设备上自动部署和卸载 sing-box 的 Shell 脚本。目前已在 NanoPi R2S（Armbian Debian 环境）上测试通过。

功能特性
自动安装：一键部署 sing-box，包括依赖安装、配置文件下载和网络设置。
卸载支持：通过 uninstall 参数还原安装时的所有改动。
兼容性：支持 POSIX Shell（如 sh），无需依赖 Bash。
日志输出：美观的日志格式（INFO/DEBUG），便于调试。
灵活配置：支持自定义配置文件 URL，默认提供稳定配置。
环境要求
操作系统：Linux（推荐 Debian/Ubuntu 系，已在 Armbian Debian 测试）
架构支持：x86_64、arm64、armv7、i386
权限：需要 root 或 sudo 权限
网络：设备需能访问 GitHub 或其他指定的下载源
安装方法
从 GitHub 部署
```shell
bash <(curl -s https://github.com/Lsmoisu/sing-box-shell/raw/refs/heads/main/install.sh)
从其他 Git 源部署
```
收起

自动换行

复制
bash <(curl -s https://git.hechunyu.com/chunyu/sing-box-shell/raw/branch/main/install.sh)
本地运行
下载脚本：
bash

收起

自动换行

复制
wget https://github.com/Lsmoisu/sing-box-shell/raw/refs/heads/main/install.sh
添加执行权限并运行：
bash

收起

自动换行

复制
chmod +x install.sh
sh install.sh
卸载方法
运行脚本时添加 uninstall 参数：

bash

收起

自动换行

复制
sh install.sh uninstall
卸载将移除 sing-box 可执行文件、配置文件、服务、防火墙规则，并尝试恢复网络设置（如 /etc/resolv.conf 和 IP 转发）。

使用说明
安装过程：
脚本会检测网络接口和 IP 地址。
提示是否跳过系统更新（快速安装）。
下载并安装 sing-box（默认版本 1.11.4）。
配置 systemd 服务和防火墙规则。
设置 DNS 和 IP 转发。
配置选项：
运行时可输入自定义配置文件 URL，默认使用 https://sub.aaa.team/config-zz-realip-route。
安装完成后，需将其他设备的网关和 DNS 指向设备 IP（如 192.168.1.3）。
日志级别：
默认 INFO：显示主要操作信息。
修改脚本顶部 LOG_LEVEL="DEBUG" 可启用详细调试日志。
已知问题
IPv6 支持：若系统中未安装 ip6tables，IPv6 功能将受限（脚本会自动跳过）。
系统兼容性：目前仅在 NanoPi R2S（Armbian Debian）测试，其他设备可能需调整。
卸载限制：无法完全恢复 /etc/resolv.conf 的原始内容，默认设置为 8.8.8.8。
