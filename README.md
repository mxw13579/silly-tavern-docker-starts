
# SillyTavern 一键部署脚本

## 简介

本项目用于简化 **SillyTavern** 在 Linux / Windows 系统上的部署流程。

脚本会自动完成以下操作：

- 检测当前系统发行版
- 检测服务器所在地区
- 自动安装 Docker
- 自动安装 Docker Compose
- 根据地区选择官方源或国内镜像源
- 生成 SillyTavern Docker Compose 配置
- 可选开启外网访问
- 可选配置用户名和密码
- 可选启用 Watchtower 自动更新

> 注意：SillyTavern 原项目名称为 **SillyTavern**，不是 `Silly Tavern`。

---

## Linux 一键安装

### 支持的 Linux 发行版

当前脚本主要支持以下 Linux 发行版：

- Debian
- Ubuntu
- CentOS / RHEL
- Rocky Linux
- AlmaLinux
- Fedora
- Arch Linux
- Alpine Linux
- SUSE Linux Enterprise Server
- openSUSE Leap
- openSUSE Tumbleweed

部分基于 Debian / Ubuntu / RHEL 的衍生系统也可能可用，但不保证完全兼容。

---

## 安装方式

### 国内服务器

如果服务器位于中国大陆，推荐使用加速地址：

```bash
bash -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/linux-silly-tavern-docker-deploy.sh)"
```

如果当前用户不是 root，脚本会自动尝试使用 `sudo`。

也可以手动使用：

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/linux-silly-tavern-docker-deploy.sh -o linux-silly-tavern-docker-deploy.sh
bash linux-silly-tavern-docker-deploy.sh
```

---

### 国外服务器

如果服务器位于中国大陆以外，推荐使用 GitHub 原始地址：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/linux-silly-tavern-docker-deploy.sh)"
```

也可以手动下载后运行：

```bash
curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/linux-silly-tavern-docker-deploy.sh -o linux-silly-tavern-docker-deploy.sh
bash linux-silly-tavern-docker-deploy.sh
```

---

## 安全建议

一键脚本会在服务器上安装 Docker、修改部分系统配置并创建容器。

如果你对脚本内容不熟悉，建议先查看脚本内容：

```bash
curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/linux-silly-tavern-docker-deploy.sh -o linux-silly-tavern-docker-deploy.sh
less linux-silly-tavern-docker-deploy.sh
```

确认无误后再运行：

```bash
bash linux-silly-tavern-docker-deploy.sh
```

---

## 安装过程说明

脚本执行过程中会询问：

### 1. 是否开启外网访问

- 选择 `n`：
    - 仅监听 `127.0.0.1:8000`
    - 外网无法直接访问
    - 更安全
    - 可通过 SSH 隧道访问

- 选择 `y`：
    - 监听 `0.0.0.0:8000`
    - 可通过公网 IP 访问
    - 会要求配置用户名和密码

### 2. 用户名密码生成方式

开启外网访问后，可以选择：

- 随机生成用户名和密码
- 手动输入用户名和密码

用户名和密码要求：

- 长度 3-64 位
- 不能是纯数字
- 仅允许以下字符：

```text
A-Z a-z 0-9 . _ @ -
```

### 3. 是否启用 Watchtower 自动更新

Watchtower 可以自动更新容器，但需要挂载 Docker Socket：

```text
/var/run/docker.sock
```

这具有较高权限风险。

默认建议选择：

```text
n
```

如果你明确接受该风险，可以选择：

```text
y
```

---

## 部署目录

Linux 脚本默认部署目录为：

```text
/data/docker/sillytavern
```

主要文件：

```text
/data/docker/sillytavern/docker-compose.yaml
/data/docker/sillytavern/config/config.yaml
/data/docker/sillytavern/data
/data/docker/sillytavern/plugins
/data/docker/sillytavern/extensions
```

---

## 默认访问地址

如果开启了外网访问：

```text
http://你的服务器公网IP:8000
```

如果未开启外网访问：

```text
http://127.0.0.1:8000
```

远程访问可使用 SSH 隧道：

```bash
ssh -L 8000:127.0.0.1:8000 root@你的服务器公网IP
```

然后在本地浏览器打开：

```text
http://127.0.0.1:8000
```

---

## 常用管理命令

进入部署目录：

```bash
cd /data/docker/sillytavern
```

查看容器状态：

```bash
docker compose ps
```

查看日志：

```bash
docker compose logs -f
```

重启服务：

```bash
docker compose restart
```

停止服务：

```bash
docker compose down
```

重新拉取镜像并启动：

```bash
docker compose pull
docker compose up -d
```

---

## 卸载 Linux 部署

如果需要停止并删除容器：

```bash
cd /data/docker/sillytavern
docker compose down
```

如果需要删除全部 SillyTavern 数据：

```bash
rm -rf /data/docker/sillytavern
```

> 注意：删除目录会清空配置、角色卡、聊天数据、插件和扩展，请谨慎操作。

---

## Windows 系统安装

### 下载地址

Windows 用户可以从 GitHub Releases 下载：

[Windows 一键安装版本 V1.0.0](https://github.com/mxw13579/silly-tavern-docker-starts/releases/download/v1.0/windows-silly-tavern-deploy.bat)

---

### Windows 安装步骤

1. 下载 `windows-silly-tavern-deploy.bat`
2. 如在中国大陆网络环境，建议开启系统代理或 TUN 模式
3. 右键点击 `.bat` 文件
4. 选择“以管理员身份运行”
5. 按照脚本提示完成安装

---

## Windows 注意事项

如果安装失败，请检查：

- 当前代理是否正常
- 系统代理是否生效
- TUN 模式是否开启
- Docker Desktop 是否正常运行
- IP 地区检测结果是否与当前网络环境一致
- 防火墙是否拦截相关端口

---

## 常见问题

### 1. 安装 Docker 失败

请检查：

```bash
docker version
```

如果 Docker 未安装或未启动，可以查看服务状态：

```bash
systemctl status docker
```

或查看日志：

```bash
journalctl -xeu docker.service --no-pager -n 80
```

---

### 2. 无法访问 `8000` 端口

请检查：

- 是否选择开启外网访问
- 云服务器安全组是否放行 `8000`
- 系统防火墙是否放行 `8000`
- Docker 容器是否正常运行

查看容器状态：

```bash
cd /data/docker/sillytavern
docker compose ps
```

查看日志：

```bash
docker compose logs -f
```

---

### 3. 国内服务器拉取镜像失败

请确认脚本是否检测到服务器位于中国大陆。

如果检测失败，可以尝试重新运行脚本，或手动检查：

```bash
curl -fsSL https://ipinfo.io/country
```

返回：

```text
CN
```

表示检测为中国大陆。

---

### 4. Watchtower 是否必须启用？

不是。

Watchtower 只是用于自动更新容器。

由于它需要挂载 Docker Socket，具有较高权限风险，默认建议不启用。

---

## 项目地址

GitHub 仓库：

```text
https://github.com/mxw13579/silly-tavern-docker-starts
```

---

## 免责声明

本脚本会修改系统软件源、安装 Docker、创建 Docker 容器并写入配置文件。

请在运行前确认脚本内容，并自行承担使用风险。

生产环境建议先在测试服务器验证后再使用。
