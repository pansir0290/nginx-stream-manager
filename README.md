Markdown

# Nginx Stream Manager (NSM)

![Version](https://img.shields.io/badge/Version-1.0.1%20(Stable)-blue)
![License](https://img.shields.io/github/license/pansir0290/nginx-stream-manager?color=orange)
![OS Compatibility](https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu%20%7C%20CentOS-green)

Nginx Stream Manager (NSM) 是一个简单、易用的 Shell 脚本工具，旨在帮助 Linux 用户快速配置和管理 Nginx 的 Stream 模块（四层代理），实现 TCP/UDP 端口的转发与代理。特别支持 SSL/TLS 预读功能，用于根据 SNI 路由流量。

## 🚀 核心功能

* **端口转发:** 轻松设置 TCP 和 UDP 端口转发到目标 IP 和端口。
* **SSL 预读支持:** 利用 Nginx 的 `ssl_preread` 功能，根据客户端请求的 SNI 信息进行更智能的代理。
* **配置管理:** 自动添加、修改和删除 Stream 代理规则。
* **服务控制:** 一键重启/重载 Nginx 服务以应用配置。
* **环境检查:** 自动检查 Nginx 核心配置和 Stream 模块的加载状态。

## 📋 兼容性要求

本脚本要求您的系统满足以下条件：

1.  **操作系统:** 兼容主流 Linux 发行版 (Debian 10+, Ubuntu 18.04+, CentOS 7+)。
2.  **权限:** 必须以 `root` 用户或具有 `sudo` 权限的用户运行。
3.  **核心组件:** `curl`, `nginx`, `sudo`, `vim` 或 `nano`。

## 💡 安装依赖

在运行部署脚本之前，请确保您的系统已安装所有必要的组件。

**对于 Debian/Ubuntu 系统:**

```bash
sudo apt update
sudo apt install -y curl vim sudo nginx net-tools iproute2

对于 CentOS/RHEL/Fedora 系统:
Bash

sudo yum install -y curl vim sudo nginx net-tools iproute2
# 或使用 dnf
# sudo dnf install -y curl vim sudo nginx net-tools iproute2

    注意： net-tools 或 iproute2 用于端口占用检查。如果您的 Nginx 是从源码编译安装，请确保已启用 ngx_stream_module 和 ngx_stream_ssl_module。

🛠️ 部署脚本

执行以下命令即可部署 Nginx Stream Manager (NSM)。脚本会自动下载、安装并配置环境，然后创建别名。
Bash

sudo curl -fsSL [https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main/deploy.sh](https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main/deploy.sh) | bash

运行完成后，请执行以下命令以确保 nsm 命令别名生效：
Bash

source ~/.bashrc

🖥️ 使用方法

部署成功后，只需在终端输入 nsm 即可启动管理菜单。
Bash

nsm

主菜单选项说明

选项	命令	描述
1	添加或修改代理规则	引导式添加新的端口转发规则，支持 TCP/UDP 和 SSL 预读配置。
2	删除现有代理规则	查看所有已配置的规则，并按序号删除指定的规则。
3	重启 Nginx	检查 Nginx 配置语法并重载/重启 Nginx 服务，使规则生效。
4	系统状态检查	检查 Nginx 服务状态、配置包含状态、Stream SSL 模块加载状态等。
0	退出 NSM	退出管理工具。

⭐ 注意事项与故障排查

1. Nginx Stream 模块

NSM 依赖于 Nginx 的 Stream 模块。大多数发行版安装的 Nginx 默认包含该模块。如果在使用 TCP/UDP 或 ssl_preread 时报错，请运行菜单中的 4) 系统状态检查，并确保 Nginx 主配置文件中已正确加载 ngx_stream_ssl_module.so。如果缺失，脚本会尝试自动修复。

2. SELinux (CentOS/RHEL 用户)

如果您的系统启用了 SELinux，可能会阻止 Nginx 监听高权限端口。

    脚本会尝试临时禁用 SELinux (setenforce 0) 并修改配置文件永久禁用。

    强烈建议在部署后，重启系统使 SELinux 永久禁用生效，以避免后续端口转发失败。

3. 配置路径

所有规则文件都存储在以下路径：

    主规则文件: /etc/nginx/conf.d/nsm/nsm-stream.conf

    备份目录: /etc/nginx/conf.d/nsm/backups

如果遇到配置问题，您可以手动检查或恢复备份文件。

4. 日志文件

脚本的所有操作和错误信息都会记录在：

    日志文件: /var/log/nsm-manager.log

遇到任何问题时，查看此文件可以帮助您定位故障。

📜 许可协议

本项目遵循 MIT 协议。
