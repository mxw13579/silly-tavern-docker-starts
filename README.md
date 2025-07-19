# Silly Tavern 一键部署脚本

## 简介

Silly Tavern 是一个非常有趣的项目，本脚本旨在简化其在 Linux 和 Windows 系统上的部署过程。

## Linux 系统一键安装脚本

### 支持的 Linux 发行版

- Debian
- Ubuntu
- CentOS/RHEL
- Fedora
- Arch Linux
- Alpine Linux
- SUSE Linux Enterprise Server / openSUSE Leap / openSUSE Tumbleweed

### 安装步骤

你可以使用以下命令在 Linux 系统上一键安装 Silly Tavern Docker 环境：

```bash
#国内服务器为
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/linux-silly-tavern-docker-deploy.sh | sudo bash
#国外服务器为
curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/linux-silly-tavern-docker-deploy.sh | sudo bash


bash -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/sillytavern-toolkit/install.sh)"
```

该脚本会自动检测你的Linux发行版，并安装所需的Docker环境。

## Windows 系统安装步骤

对于 Windows 用户，请从我们的 GitHub 仓库 中的 Releases 下载最新的 `windows-silly-tavern-deploy.bat` 文件

[Windows 一键安装版本 V1.0.0](https://github.com/mxw13579/silly-tavern-docker-starts/releases/download/v1.0/windows-silly-tavern-deploy.bat)

开启魔法的 系统代理+ TUN 模式后右键点击该文件以管理员身份运行。


在脚本执行时会检测 IP 地址以及对应地区，当安装失败后请检测地区与魔法地区是否吻合
