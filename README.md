# Nginx Stream Manager (NSM)

![Version](https://img.shields.io/badge/Version-1.0.1%20(Stable)-blue)
![License](https://img.shields.io/github/license/pansir0290/nginx-stream-manager?color=orange)
![OS Compatibility](https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu%20%7C%20CentOS-green)

> **NSM 是一款高效、可靠的 Shell 脚本工具，专注于简化 Linux 环境下 Nginx Stream 模块（四层代理）的配置与管理。实现高性能的 TCP/UDP 端口转发和基于 SNI 的智能代理。**

## 🚀 核心功能

* **端口转发:** 轻松设置 TCP 和 UDP 端口转发到目标 IP 和端口。
* **SSL 预读 (SNI 路由):** 利用 Nginx 的 `ssl_preread` 功能，根据客户端请求的域名（ SNI ）自动将流量路由到不同的后端服务器，完美解决单端口多服务问题。
* **配置管理:** 自动添加、修改和删除 Stream 代理规则。
* **服务控制:** 一键重启/重载 Nginx 服务以应用配置。
* **环境自检:** 部署脚本包含智能检测，自动安装 Stream 模块并清理配置冲突。

## 📋 兼容性要求

本脚本要求您的系统满足以下条件：

* **操作系统:** 兼容主流 Linux 发行版 (Debian 10+, Ubuntu 18.04+, CentOS 7+)。
* **权限:** 必须以 `root` 用户或具有 `sudo` 权限的用户运行。
* **核心组件:** `curl`, `nginx`, `sudo` 等（已包含在部署脚本中）。
2. 部署指南和手动安装依赖
Markdown

## 🛠️ 一键部署 (推荐)

我们推荐使用一键部署脚本，它将自动安装所有依赖（包括 Nginx Stream 模块）、下载管理脚本并设置 `nsm` 命令。**您无需担心 Stream 模块缺失或配置冲突问题。**

### 步骤 1: 部署并安装

**运行以下命令，完成所有环境配置和安装：**

```bash
# 确保在 Debian/Ubuntu/CentOS 系统上以 root 或 sudo 权限运行
sudo curl -fsSL [https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main/deploy.sh](https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main/deploy.sh) | bash
🛑 请务必复制上方代码块中的完整命令，避免粘贴时命令不完整！

步骤 2: 激活命令
【重要】部署完成后，请执行此命令使 'nsm' 别名生效：

Bash

source ~/.bashrc # 或 source /root/.bashrc

💡 手动安装依赖（如果一键部署失败）

如果您的系统环境特殊，可以手动安装依赖：

对于 Debian/Ubuntu 系统:

Bash

sudo apt update
sudo apt install -y curl vim sudo nginx net-tools iproute2 libnginx-mod-stream
对于 CentOS/RHEL/Fedora 系统:

Bash

sudo yum install -y curl vim sudo nginx net-tools iproute2
# 或使用 dnf
# sudo dnf install -y curl vim sudo nginx net-tools iproute2

### 3. 使用方法和故障排除

```markdown
## 🖥️ 使用方法

部署成功后，只需在终端输入 `nsm` 即可启动管理菜单。

```bash
nsm
主菜单选项说明

选项	命令	描述
1	添加或修改代理规则	引导式添加新的端口转发规则，支持 TCP/UDP 和 SSL 预读配置。
2	删除现有代理规则	查看所有已配置的规则，并按序号删除指定的规则。
3	重启 Nginx	检查 Nginx 配置语法并重载/重启 Nginx 服务，使规则生效。
4	系统状态检查	检查 Nginx 服务状态、配置包含状态、 Stream SSL 模块加载状态等。
0	退出 NSM	退出管理工具。
关键特性说明： SSL 预读

当您在添加规则时选择开启 SSL 预读（ ssl_preread ）时， NSM 会在 Stream 模块中添加配置，让 Nginx 能够读取 SSL 握手时的 SNI 域名信息，从而实现：

单端口多 HTTPS 服务: 例如，将所有 443 端口的流量根据域名路由到不同的内网 Web 服务器。

四层代理: Nginx 在 Stream 模块中工作在四层，不会终止 SSL 连接，证书和加解密工作仍在后端服务器上完成。

⭐ 注意事项与故障排查
1. Nginx 配置测试失败
如果 Nginx 服务重载失败，或您运行 nsm 后提示配置错误，请执行以下命令进行详细诊断：

Bash

sudo nginx -t
Stream 模块问题： 如果提示找不到 Stream 模块 (dlopen() ... failed)，请确认您使用了最新的 deploy.sh ，它会自动安装 libnginx-mod-stream 并清理配置冲突。

语法错误： 如果提示配置语法错误，请检查您的规则文件 /etc/nginx/conf.d/nsm/nsm-stream.conf ，确保没有多余或缺失的花括号 {} 或分号 ;。

2. 端口占用问题
如果您添加规则时 Nginx 无法启动，提示端口已被占用 (bind() failed)，请运行以下命令检查哪个进程占用了该端口：

Bash

sudo netstat -tuln | grep <端口号>
3. 配置路径
所有规则文件都存储在以下路径：

主规则文件: /etc/nginx/conf.d/nsm/nsm-stream.conf

备份目录: /etc/nginx/conf.d/nsm/backups

日志文件: /var/log/nsm-manager.log


### 4. 卸载指南和许可协议

```markdown
## 🗑️ 卸载指南

如果您希望彻底移除 Nginx Stream Manager (NSM)，请执行以下步骤：

**1. 清除 Nginx 配置:**

```bash
sudo rm -rf /etc/nginx/conf.d/nsm
2. 移除管理脚本:

Bash

sudo rm -f /usr/local/bin/nsm
3. 移除别名 (可选):
手动编辑您的 .bashrc 或 .zshrc 文件，删除 alias nsm='...' 这一行。

4. 重载 Nginx:

Bash

sudo systemctl reload nginx
📜 许可协议
本项目遵循 MIT 协议。

