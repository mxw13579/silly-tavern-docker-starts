#!/bin/bash
# SillyTavern Toolkit 主菜单

# 设置工作目录为脚本所在目录
cd "$(dirname "$0")"

# 引入通用脚本，它会执行环境检测
source ./scripts/common.sh

while true; do
    # 调用各个模块的status函数来获取状态
    clear
    echo "=========================================================="
    echo "======          SillyTavern 一键部署工具箱          ======"
    echo "======          FuFu API (群1019836466) 提供         ======"
    echo "=========================================================="
    echo
    echo "--- 系统环境状态 (每次进入菜单时刷新) ---"
    # 直接调用并显示状态
     ./scripts/sources.sh status
     ./scripts/docker.sh status
     ./scripts/sillytavern.sh status
    echo "----------------------------------------------------------"
    echo
    echo "--- 主菜单 ---"
    echo "   推荐新手按 1 -> 2 -> 3 的顺序操作"
    echo
    echo "   1. 软件源管理 (加速系统软件包下载)"
    echo "   2. Docker 环境管理 (部署应用的基础)"
    echo "   3. SillyTavern 应用管理 (核心功能)"
    echo
    echo "   0. 退出脚本"
    echo "----------------------------------------------------------"

    read -p "请输入选项 [0-3]: " main_choice

    case $main_choice in
        1)
            # 软件源管理子菜单
            while true; do
                clear
                echo "--- 软件源管理 ---"
                echo "为您的操作系统切换下载源，可以大幅提升后续安装速度。"
                echo "如果您在海外，无需操作。如果在中国大陆，推荐选择一个。"
                echo "---------------------------------------------------"
                 ./scripts/sources.sh status
                echo "---------------------------------------------------"
                echo "   1. 切换为 [阿里云] 软件源"
                echo "   2. 切换为 [腾讯云] 软件源"
                echo "   3. 切换为 [华为云] 软件源"
                echo "   4. 恢复为 [系统默认] 软件源 (如果切换后出现问题)"
                echo "   0. 返回主菜单"
                echo "---------------------------------------------------"
                read -p "请输入选项 [0-4]: " sources_choice
                case $sources_choice in
                    1)  ./scripts/sources.sh set aliyun ;;
                    2)  ./scripts/sources.sh set tencent ;;
                    3)  ./scripts/sources.sh set huawei ;;
                    4)  ./scripts/sources.sh restore ;;
                    0) break ;;
                    *) msg_error "无效选项" ;;
                esac
                [[ "$sources_choice" != "0" ]] && pause_to_continue
            done
            ;;
        2)
            # Docker管理子菜单
            while true; do
                clear
                echo "--- Docker 环境管理 ---"
                echo "Docker是运行SillyTavern的容器技术，必须安装。"
                echo "---------------------------------------------------"
                 ./scripts/docker.sh status
                echo "---------------------------------------------------"
                echo "   1. 安装 Docker (若未安装)"
                echo "   2. 配置 Docker 国内镜像加速器 (在中国大陆必做)"
                echo "   3. 重启 Docker 服务 (排错用)"
                echo "   4. 查看已下载的 Docker 镜像 (管理用)"
                echo "   0. 返回主菜单"
                echo "---------------------------------------------------"
                read -p "请输入选项 [0-4]: " docker_choice
                case $docker_choice in
                    1)  ./scripts/docker.sh install ;;
                    2)  ./scripts/docker.sh config_mirror ;;
                    3)  ./scripts/docker.sh restart_service ;;
                    4)  ./scripts/docker.sh list_images ;;
                    0) break ;;
                    *) msg_error "无效选项" ;;
                esac
                [[ "$docker_choice" != "0" ]] && pause_to_continue
            done
            ;;
        3)
            # SillyTavern管理子菜单
            while true; do
                clear
                echo "--- SillyTavern 应用管理 ---"
                echo "在这里安装、启动、更新您的SillyTavern酒馆。"
                echo "---------------------------------------------------"
                 ./scripts/sillytavern.sh status
                echo "---------------------------------------------------"
                echo "   1. 全新安装 SillyTavern (第一步)"
                echo "   2. 启动 SillyTavern"
                echo "   3. 停止 SillyTavern"
                echo "   4. 重启 SillyTavern"
                echo "   5. 更新 SillyTavern (拉取最新版)"
                echo "   6. 查看 SillyTavern 实时日志 (排错用)"
                echo "   7. 备份 SillyTavern 数据 (重要！)"
                echo "   8. 修改/设置 SillyTavern 访问密码"
                echo "   0. 返回主菜单"
                echo "---------------------------------------------------"
                read -p "请输入选项 [0-8]: " st_choice
                case $st_choice in
                    1) ./scripts/sillytavern.sh install ;;
                    2) ./scripts/sillytavern.sh start ;;
                    3) ./scripts/sillytavern.sh stop ;;
                    4) ./scripts/sillytavern.sh restart ;;
                    5) ./scripts/sillytavern.sh update ;;
                    6) ./scripts/sillytavern.sh logs ;;
                    7) ./scripts/sillytavern.sh backup ;;
                    8) ./scripts/sillytavern.sh change_password ;;
                    0) break ;;
                    *) msg_error "无效选项" ;;
                esac
                [[ "$st_choice" != "0" ]] && pause_to_continue
            done
            ;;
        0)
            echo "感谢使用，再见！"
            exit 0
            ;;
        *)
            msg_error "无效的主菜单选项，请输入 0-3 之间的数字。"
            pause_to_continue
            ;;
    esac
done
