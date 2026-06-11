
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

## SillyTavern Docker 工具箱

`sillytavern-toolkit` 是面向 Linux 服务器的交互式管理工具箱，适合需要反复维护软件源、Docker 环境和 SillyTavern 容器的场景。

### 安装工具箱

国内服务器推荐使用加速地址：

```bash
bash -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/sillytavern-toolkit/install.sh)"
```

国外服务器推荐使用 GitHub 原始地址：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/sillytavern-toolkit/install.sh)"
```

安装器默认将工具箱安装到：

```text
~/sillytavern-toolkit
```

如果目录已存在，会先备份为带时间戳的 `.bak_` 目录。

### 启动工具箱

安装完成后默认会自动进入工具箱菜单。后续也可以手动启动：

```bash
bash ~/sillytavern-toolkit/st-toolkit.sh
```

### 安装参数

`install.sh` 支持以下参数：

- `--no-launch`：只安装或更新工具箱，不在安装完成后自动启动菜单。
- `--yes` 或 `-y`：在中国大陆环境使用 `ghfast.top` 代理下载时，自动确认代理下载风险；适合非交互式环境。
- `--ref <ref>`：安装指定分支、标签或 40 位 commit，适合测试新版、固定版本或回滚。

也可以通过环境变量控制安装行为：

- `ST_TOOLKIT_REF=<ref>`：指定下载分支、标签或 40 位 commit。
- `ST_TOOLKIT_YES=1`：等同于 `--yes`。
- `ST_TOOLKIT_NO_LAUNCH=1`：等同于 `--no-launch`。
- `ST_TOOLKIT_CHECKSUMS_URL=<https-url>`：可选 checksum manifest URL，用于校验代理下载后的工具箱文件。

示例：

```bash
bash install.sh --no-launch
bash install.sh --yes --no-launch
bash install.sh --ref main --no-launch
```

如果直接使用 `bash -c "$(curl ...)"` 方式传参，需要在脚本内容后追加 `--`：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/sillytavern-toolkit/install.sh)" -- --no-launch
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/sillytavern-toolkit/install.sh)" -- --ref main --no-launch
```

非交互安装示例：

```bash
ST_TOOLKIT_YES=1 ST_TOOLKIT_NO_LAUNCH=1 \
bash -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/sillytavern-toolkit/install.sh)"
```

### 菜单能力

工具箱主菜单包含：

- 软件源管理：查看当前软件源状态，切换阿里云、腾讯云、华为云软件源，恢复最近一次备份的软件源。
- Docker 环境管理：安装或修复 Docker 与 Docker Compose，重启 Docker 服务，查看本机 Docker 镜像。
- SillyTavern 应用管理：全新安装、启动、停止容器、停止并移除容器/网络、重启现有容器、应用配置变更、更新镜像并运行、查看实时日志、备份数据、修改访问配置、恢复上一次访问配置、生成诊断报告、运行健康检查、显示部署信息。

工具箱进入主菜单和子菜单时会刷新系统环境、软件源、Docker 与 SillyTavern 状态，可用于快速健康检查。

### Docker 镜像加速器管理

在 `Docker 环境管理 -> Docker 镜像加速器管理` 中可以：

- 查看当前 `/etc/docker/daemon.json` 中的 `registry-mirrors` 配置。
- 对当前镜像加速器进行测速。
- 从测速结果中选择或更换 Docker Hub 镜像加速器。
- 输入自定义 HTTPS 镜像加速器地址。
- 移除已有 `registry-mirrors` 配置。
- 恢复最近一次 `/etc/docker/daemon.json` 备份。

修改 Docker 配置前会备份原 `/etc/docker/daemon.json`，修改后需要重启 Docker 服务才会生效。
恢复 daemon 配置前会校验备份文件是否为合法 JSON；如果恢复后 Docker 重启失败，会尝试回滚到恢复前的配置。

也可以直接调用工具脚本：

```bash
bash ~/sillytavern-toolkit/scripts/docker.sh mirror_menu
bash ~/sillytavern-toolkit/scripts/docker.sh mirror_status
bash ~/sillytavern-toolkit/scripts/docker.sh mirror_speed
bash ~/sillytavern-toolkit/scripts/docker.sh restore_daemon
bash ~/sillytavern-toolkit/scripts/docker.sh images
```

### 备份、恢复与访问配置

在 `SillyTavern 应用管理` 中可以备份 SillyTavern 部署数据。备份文件默认保存到当前用户家目录，文件名类似：

```text
~/sillytavern_backup_20260101_120000.tar.gz
```

访问配置入口用于重新设置：

- 本地访问或外网访问
- Basic Auth 用户名和密码
- Watchtower 自动更新

修改访问配置前，工具箱会自动备份当前 `docker-compose.yaml` 和 `config/config.yaml` 到：

```text
/data/docker/sillytavern/backups/config/
```

如果修改后访问异常，可以通过 `恢复上一次访问配置` 恢复最近一次访问配置备份，并选择是否立即重启 SillyTavern。

### 非交互安装 SillyTavern

工具箱的 SillyTavern 管理脚本支持非交互安装，适合 CI、初始化脚本或自部署平台调用。

本地访问模式示例：

```bash
ST_NON_INTERACTIVE=1 \
ST_ACCESS_MODE=local \
bash ~/sillytavern-toolkit/scripts/sillytavern.sh install
```

外网访问模式示例：

```bash
ST_NON_INTERACTIVE=1 \
ST_ACCESS_MODE=public \
ST_AUTH_USER=myuser \
ST_AUTH_PASS=mypassword \
ST_ENABLE_WATCHTOWER=0 \
bash ~/sillytavern-toolkit/scripts/sillytavern.sh install
```

非交互环境变量：

- `ST_NON_INTERACTIVE=1`：启用非交互模式。
- `ST_ACCESS_MODE=local|public`：选择本地访问或外网访问。
- `ST_AUTH_USER=<username>`：外网访问模式必填。
- `ST_AUTH_PASS=<password>`：外网访问模式必填。
- `ST_ENABLE_WATCHTOWER=1|0`：是否启用 Watchtower。

外网访问模式会先校验用户名和密码，再写入 `docker-compose.yaml` 和 `config/config.yaml`，避免未配置 Basic Auth 时暴露公网端口。

### 诊断报告

`SillyTavern 应用管理 -> 生成诊断报告` 会生成一份 Markdown 诊断报告，便于求助或排查部署状态。报告包含工具箱文件状态、基础系统信息、Docker/Compose 可见性、SillyTavern 部署文件状态、访问配置摘要、Compose `config -q` 校验证据和最近日志。

默认输出到当前用户家目录，文件名类似：

```text
~/sillytavern_doctor_report_20260101_120000.md
```

也可以直接调用：

```bash
bash ~/sillytavern-toolkit/scripts/sillytavern.sh doctor-report
bash ~/sillytavern-toolkit/scripts/sillytavern.sh doctor-report --output ~/st-doctor.md
bash ~/sillytavern-toolkit/scripts/sillytavern.sh doctor-report --stdout --no-logs
bash ~/sillytavern-toolkit/scripts/sillytavern.sh doctor-report --service watchtower --lines 100 --since 30m
bash ~/sillytavern-toolkit/scripts/sillytavern.sh doctor --all-services
```

诊断报告会对常见敏感信息做脱敏，包括认证头、Cookie、URL 用户信息、token/key/secret/password 字段、`ST_AUTH_USER`、`ST_AUTH_PASS`、用户家目录和用户名。生成报告前仍建议自行复核内容。

退出码语义：

- `0`：报告生成成功，报告内部可能记录 WARN/FAIL 诊断项。
- `2`：参数错误、输出路径不可用或报告文件写入失败。

诊断报告是只读入口，不修复、不回滚、不更新、不启动或停止容器；不会运行健康检查脚本，也不会探测公网 IP。

### 健康检查

`SillyTavern 应用管理 -> 运行健康检查` 会执行只读诊断，检查：

- Docker 命令和 Docker daemon
- Docker Compose 可用性
- 部署目录、Compose 文件、配置文件
- SillyTavern 容器状态
- 端口映射与本机监听信息
- 最近 50 行 SillyTavern 日志

健康检查不会修改系统配置。

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
bash ~/sillytavern-toolkit/scripts/sillytavern.sh logs tail --lines 200
bash ~/sillytavern-toolkit/scripts/sillytavern.sh logs follow --lines 100
bash ~/sillytavern-toolkit/scripts/sillytavern.sh logs since 30m --lines 1000
bash ~/sillytavern-toolkit/scripts/sillytavern.sh logs save --output ~/sillytavern.log
```

重启现有容器（不应用 Compose 配置变更）：

```bash
docker compose restart
```

停止容器（保留 Compose 项目、网络和数据目录）：

```bash
docker compose stop
```

停止并移除 Compose 容器/网络（保留数据目录）：

```bash
docker compose down
```

校验并应用 Compose 配置变更：

```bash
docker compose config -q
docker compose up -d --remove-orphans
```

重新拉取镜像并运行：

```bash
docker compose config -q
docker compose pull
docker compose up -d
```

工具箱脚本也可以直接执行子命令：

```bash
bash ~/sillytavern-toolkit/scripts/sillytavern.sh status
bash ~/sillytavern-toolkit/scripts/sillytavern.sh info
bash ~/sillytavern-toolkit/scripts/sillytavern.sh logs tail --lines 200
bash ~/sillytavern-toolkit/scripts/sillytavern.sh logs follow --lines 100
bash ~/sillytavern-toolkit/scripts/sillytavern.sh logs since 30m --lines 1000
bash ~/sillytavern-toolkit/scripts/sillytavern.sh logs save --output ~/sillytavern.log
bash ~/sillytavern-toolkit/scripts/sillytavern.sh change_access
bash ~/sillytavern-toolkit/scripts/sillytavern.sh self-check
bash ~/sillytavern-toolkit/scripts/sillytavern.sh doctor-report
bash ~/sillytavern-toolkit/scripts/sillytavern.sh doctor-report --output ~/st-doctor.md
bash ~/sillytavern-toolkit/scripts/sillytavern.sh doctor-report --stdout --no-logs
```

`self-check` 是只读诊断入口，用于检查工具箱文件、Bash 语法、基础命令和本机 Docker/Compose 可见性；它不会执行 self-update、下载、`git pull` 或容器生命周期操作。
`doctor-report` 是只读报告入口，用于生成可转交的 Markdown 诊断材料；它会脱敏常见凭据，默认写入 `~/sillytavern_doctor_report_YYYYmmdd_HHMMSS.md`，不会修复、回滚、更新、探测公网 IP 或执行容器生命周期操作。

---

## 开发与验证

本项目没有编译步骤，主要通过 Bash 语法检查、ShellCheck 和 Bats 测试验证。

语法检查：

```bash
bash -n linux-silly-tavern-docker-deploy.sh \
  sillytavern-toolkit/install.sh \
  sillytavern-toolkit/st-toolkit.sh \
  sillytavern-toolkit/scripts/*.sh \
  sillytavern-toolkit/scripts/lib/*.sh \
  sillytavern-toolkit/scripts/docker/*.sh \
  sillytavern-toolkit/scripts/sillytavern/*.sh \
  tests/helpers/*.bash \
  tests/bats/*.bats
```

ShellCheck：

```bash
shellcheck --shell=bash linux-*.sh \
  sillytavern-toolkit/install.sh \
  sillytavern-toolkit/st-toolkit.sh \
  sillytavern-toolkit/scripts/*.sh \
  sillytavern-toolkit/scripts/lib/*.sh \
  sillytavern-toolkit/scripts/docker/*.sh \
  sillytavern-toolkit/scripts/sillytavern/*.sh
```

Bats 测试：

```bash
bats -r tests/bats
```

仓库已提供 `.gitlab-ci.yml`，自部署 GitLab 可以直接运行 `lint:bash_syntax`、`lint:shellcheck` 和 `test:bats`。

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
bash ~/sillytavern-toolkit/scripts/sillytavern.sh logs follow --lines 100
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
