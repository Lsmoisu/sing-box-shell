# Sing-Box Shell
本脚本由Grok3生成  
一个用于在 Linux 网关设备上自动部署和卸载 `sing-box` 的 Shell 脚本。
目前已在 **NanoPi R2S**上测试通过。
测试的系统：
 **Debian arm64**
 **Ubuntu 24 arm64**
 **Ubuntu 24 x86**

## 功能特性

- **自动安装**：一键部署 `sing-box`，包括依赖安装、配置文件下载和网络设置。
- **卸载支持**：通过 `uninstall` 参数还原安装时的所有改动。
- **兼容性**：支持 POSIX Shell（如 `sh`）。
- **日志输出**：美观的日志格式（INFO/DEBUG），便于调试。
- **灵活配置**：支持自定义配置文件 URL(sing-box格式)，默认为模板配置，只能保证正常启动,安装后可手动替换配置问题件，路径为/etc/sing-box/config.json。

## 环境要求

- **操作系统**：Linux（推荐 Debian/Ubuntu 系，只在 Armbian Debian 测试通过，其他设备和架构请自行测试）
- **架构支持**：x86_64、arm64、armv7、i386
- **权限**：需要 root 或 sudo 权限
- **网络**：设备需能访问 GitHub 或其他指定的下载源，如无法访问请使用github加速地址https://gh.aaa.team/

## 安装方法

### 从 GitHub 部署

```shell
bash <(curl -sL https://github.com/Lsmoisu/sing-box-shell/raw/refs/heads/main/install.sh)
```

### 使用加速地址
```shell
bash <(curl -sL https://gh.aaa.team/https://github.com/Lsmoisu/sing-box-shell/raw/refs/heads/main/install.sh)
```
### 从 其他Git 部署
```shell
bash <(curl -sL https://git.aaa.team/chunyu/sing-box-shell/raw/branch/main/install.sh)
```

## 本地运行
下载脚本：
```shell
wget https://gh.aaa.team/https://github.com/Lsmoisu/sing-box-shell/raw/refs/heads/main/install.sh
```
添加执行权限并运行：
```shell
chmod +x install.sh
sh install.sh
```

## 卸载方法
运行脚本时添加 uninstall 参数：
```shell
sh install.sh uninstall
```
卸载将移除 sing-box 可执行文件、配置文件、服务、防火墙规则，并尝试恢复网络设置（如 /etc/resolv.conf 和 IP 转发）。

## 使用说明
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

## 已知问题
IPv6 支持：未实现。
系统兼容性：目前仅在 NanoPi R2S（Armbian Debian）测试，其他设备可能需调整。
卸载限制：无法完全恢复 /etc/resolv.conf 的原始内容，默认设置为 8.8.8.8。
