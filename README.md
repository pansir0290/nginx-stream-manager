# Nginx Stream Manager (NSM)

> **NSM 是一款高效、可靠的 Shell 脚本工具，专注于简化 Linux 环境下 Nginx Stream 模块（四层代理）的配置与管理。实现高性能的 TCP/UDP 端口转发和基于 SNI 的智能代理。**

## 核心功能
- **端口转发**：轻松设置 TCP 和 UDP 端口转发到目标 IP 和端口  
- **SSL 预读 (SNI 路由)**：根据客户端请求的域名（SNI）自动路由流量，解决单端口多服务问题  
- **配置管理**：自动添加、修改和删除 Stream 代理规则  
- **服务控制**：一键重启/重载 Nginx 服务以应用配置  
- **环境自检**：部署脚本包含智能检测，自动安装 Stream 模块并清理配置冲突  

## 兼容性要求
本脚本要求您的系统满足以下条件：  
- **操作系统**：兼容主流 Linux 发行版 (Debian 10+, Ubuntu 18.04+, CentOS 7+)  
- **权限**：必须以 `root` 用户或具有 `sudo` 权限的用户运行  
- **核心组件**：`curl`, `nginx`, `sudo` 等（已包含在部署脚本中）  

## 一键部署 (推荐)
推荐使用一键部署脚本，自动安装所有依赖（包括 Nginx Stream 模块）、下载管理脚本并设置 `nsm` 命令。  

### 步骤 1: 部署并安装  
运行以下命令完成环境配置和安装：  
```bash
# 确保在 Debian/Ubuntu/CentOS 系统上以 root 或 sudo 权限运行
sudo curl -fsSL https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main/deploy.sh | bash
 

请务必复制上方代码块中的完整命令，避免粘贴时命令不完整！

步骤 2: 激活命令

部署完成后，执行以下命令使  nsm  别名生效：


source ~/.bashrc  # 或 source /root/.bashrc
 

手动安装依赖（如果一键部署失败）

若系统环境特殊，可手动安装依赖：

Debian/Ubuntu 系统


sudo apt update
sudo apt install -y curl vim sudo nginx net-tools iproute2 libnginx-mod-stream
 

CentOS/RHEL/Fedora 系统


sudo yum install -y curl vim sudo nginx net-tools iproute2
# 或使用 dnf
# sudo dnf install -y curl vim sudo nginx net-tools iproute2
 

使用方法

部署成功后，在终端输入  nsm  即可启动管理菜单：


nsm
 

主菜单选项说明

选项    命令    描述
1    添加或修改代理规则    引导式添加新的端口转发规则，支持 TCP/UDP 和 SSL 预读配置
2    删除现有代理规则    查看所有已配置的规则，并按序号删除指定的规则
3    重启 Nginx    检查 Nginx 配置语法并重载/重启 Nginx 服务，使规则生效
4    系统状态检查    检查 Nginx 服务状态、配置包含状态、Stream SSL 模块加载状态等
0    退出 NSM    退出管理工具

关键特性说明：SSL 预读

当添加规则时选择开启 SSL 预读（ ssl_preread ）时，NSM 会在 Stream 模块中添加配置，实现：

- 单端口多 HTTPS 服务：例如将 443 端口流量根据域名路由到不同内网 Web 服务器
- 四层代理：Nginx 在 Stream 模块中工作在四层，不会终止 SSL 连接，证书和加解密仍由后端服务器完成

注意事项与故障排查

1. Nginx 配置测试失败

若 Nginx 服务重载失败或提示配置错误，请执行：


sudo nginx -t
 

- Stream 模块问题：提示找不到模块时，确认使用最新  deploy.sh ，它会自动安装  libnginx-mod-stream 
- 语法错误：检查规则文件  /etc/nginx/conf.d/nsm/nsm-stream.conf ，确保没有多余/缺失的  {}  或  ; 

2. 端口占用问题

若添加规则时提示端口已被占用：


sudo netstat -tuln | grep <端口号>
 

配置路径

- 主规则文件:  /etc/nginx/conf.d/nsm/nsm-stream.conf 
- 备份目录:  /etc/nginx/conf.d/nsm/backups 
- 日志文件:  /var/log/nsm-manager.log 

卸载指南

要彻底移除 NSM：


# 清除 Nginx 配置
sudo rm -rf /etc/nginx/conf.d/nsm

# 移除管理脚本
sudo rm -f /usr/local/bin/nsm

# 移除别名（手动编辑 ~/.bashrc 删除对应行）

# 重载 Nginx
sudo systemctl reload nginx
 

许可协议

本项目遵循 MIT 许可协议(https://opensource.org/licenses/MIT)。
