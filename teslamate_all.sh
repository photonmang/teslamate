#!/bin/bash
clear  # 清屏
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "            TESLAMATE 一键安装脚本            "
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

# 确保以 root 用户运行脚本
if [ "$(id -u)" -ne "0" ]; then
    echo "请以 root 用户运行此脚本。"
    exit 1
fi

# 检查包管理器并安装 Docker 和 Docker Compose
install_dependencies() {
    if command -v apt-get >/dev/null; then
        echo "检测到基于 Debian/Ubuntu 的系统，使用 apt-get 安装..."
        apt-get update
        apt-get install -y docker.io docker-compose
    elif command -v yum >/dev/null; then
        echo "检测到基于 RedHat/CentOS 的系统，使用 yum 安装..."
        yum update -y
        yum install -y docker docker-compose
    elif command -v pacman >/dev/null; then
        echo "检测到基于 Arch Linux 的系统，使用 pacman 安装..."
        pacman -Sy
        pacman -S --noconfirm docker docker-compose
    elif [ -f "/etc/openwrt_release" ]; then
        echo "OpenWrt 系统检测到 - 使用 opkg 安装 Docker 和 Docker Compose..."
        opkg update
        opkg install docker-compose
    else
        echo "未找到支持的包管理器。请手动安装 Docker 和 Docker Compose。"
        exit 1
    fi
}

# 启动 Docker 守护进程
start_docker() {
    if ! pgrep -x "dockerd" > /dev/null; then
        echo "Docker 守护进程未运行，正在启动..."
        dockerd &
        sleep 5  # 等待 Docker 启动
    fi
}

# 显示主菜单
echo "请选择一个选项："
echo "1. 安装 TeslaMate"
echo "2. 备份 TeslaMate"
echo "3. 一键自动还原数据"
echo "4. 退出"

read -p "请输入选项（1-4）: " OPTION

# 处理选项
case $OPTION in
    1)
        echo "正在安装 TeslaMate..."
        # 检测系统架构
        ARCH=$(uname -m)
        if [[ "$ARCH" == "armv7l" || "$ARCH" == "armhf" ]]; then
            echo "检测到您的架构是 32 位 ARM 架构 - 安装英文版本..."
            TESLAMATE_IMAGE="teslamate/teslamate:latest"
            GRAFANA_IMAGE="teslamate/grafana:latest"
        elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
            echo "检测到您的架构是 64 位 ARM 架构 - 安装英文版本..."
            TESLAMATE_IMAGE="teslamate/teslamate:latest"
            GRAFANA_IMAGE="teslamate/grafana:latest"
        else
            echo "检测到您的架构是 $ARCH - 安装中文版..."
            TESLAMATE_IMAGE="ccr.ccs.tencentyun.com/dhuar/teslamate:latest"
            GRAFANA_IMAGE="ccr.ccs.tencentyun.com/dhuar/grafana:latest"
        fi

        # 安装 Docker 和 Docker Compose
        install_dependencies

        # 启动 Docker 守护进程
        start_docker

        # 确保 /opt 目录存在
        if [ ! -d "/opt" ]; then
            echo "创建 /opt 目录..."
            mkdir /opt
        fi

        # 创建 TeslaMate 目录
        if [ ! -d "/opt/teslamate" ]; then
            echo "创建 /opt/teslamate 目录..."
            mkdir /opt/teslamate
        fi

        cd /opt/teslamate

        # 创建 docker-compose.yml 配置文件
        cat <<EOF > docker-compose.yml
version: "3.8"  # 更新为支持的版本

services:
  teslamate:
    image: $TESLAMATE_IMAGE
    restart: always
    environment:
      - ENCRYPTION_KEY=my#encryption&secret
      - DATABASE_USER=teslamate
      - DATABASE_PASS=My#db&secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - MQTT_HOST=mosquitto
    ports:
      - 4000:4000
    volumes:
      - ./import:/opt/app/import
    cap_drop:
      - all

  database:
    image: postgres:14
    restart: always
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=My#db&secret
      - POSTGRES_DB=teslamate
    volumes:
      - teslamate-db:/var/lib/postgresql/data

  grafana:
    image: $GRAFANA_IMAGE
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=My#db&secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
    ports:
      - 3000:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana

  mosquitto:
    image: eclipse-mosquitto:2
    restart: always
    command: mosquitto -c /mosquitto-no-auth.conf
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data

volumes:
  teslamate-db:
  teslamate-grafana-data:
  mosquitto-conf:
  mosquitto-data:
EOF

        # 启动 TeslaMate
        echo "启动 TeslaMate..."
        docker-compose up -d

        # 检查服务状态
        if lsof -i:4000 > /dev/null && lsof -i:3000 > /dev/null; then
            echo "TeslaMate 和 Grafana 服务启动成功!"
        else
            echo "TeslaMate 或 Grafana 服务启动失败，请检查日志。"
        fi
        ;;

    2)
        echo "正在备份 TeslaMate..."

        # 自定义 TeslaMate 目录
        read -p "请输入 TeslaMate 安装目录 (默认: /opt/teslamate): " TESLAMATE_DIR
        TESLAMATE_DIR=${TESLAMATE_DIR:-/opt/teslamate}

        # 自定义备份目录
        read -p "请输入备份文件存储路径 (默认: /opt/teslamate/): " BACKUP_DIR
        BACKUP_DIR=${BACKUP_DIR:-/opt/teslamate/}

        # 备份文件的完整路径
        BACKUP_PATH="${BACKUP_DIR}teslamate.bck"

        # 创建备份脚本
        cat <<EOF > backup_teslamate.sh
#!/bin/bash
# 切换到 TeslaMate 目录
cd $TESLAMATE_DIR

# 执行备份命令
docker-compose exec -T database pg_dump -U teslamate teslamate > $BACKUP_PATH

# 获取当前时间
CURRENT_TIME=\$(date +"%Y年%m月%d日 %H:%M:%S")

# 获取备份文件大小（以MB为单位，保留两位小数）
BACKUP_SIZE=\$(stat -c%s "$BACKUP_PATH")
BACKUP_SIZE_MB=\$(echo "scale=2; \$BACKUP_SIZE/1024/1024" | bc)

# 记录备份时间和文件大小
echo "备份完成于 \$CURRENT_TIME，备份文件大小为 \${BACKUP_SIZE_MB}M。" >> ${BACKUP_DIR}backup_log.txt
EOF

        # 设置脚本可执行权限
        chmod +x backup_teslamate.sh

        # 提示是否立即执行备份并测试
        read -p "是否立即执行一次备份测试? (y/n): " RUN_TEST
        if [ "$RUN_TEST" == "y" ]; then
            ./backup_teslamate.sh

            # 检查备份文件大小
            BACKUP_SIZE=$(stat -c%s "$BACKUP_PATH")
            echo "备份文件大小: $BACKUP_SIZE bytes"
        else
            echo "备份脚本已创建。请手动运行 ${TESLAMATE_DIR}/backup_teslamate.sh 进行备份。"
        fi
        ;;

    3)
        echo "自动还原数据..."

        # 自定义备份目录
        read -p "请输入备份文件路径 (默认: /opt/teslamate/teslamate.bck): " BACKUP_PATH
        BACKUP_PATH=${BACKUP_PATH:-/opt/teslamate/teslamate.bck}

        # 确保 Docker 正在运行
        start_docker

        # 停止 TeslaMate 容器
        echo "停止 TeslaMate 容器..."
        docker-compose stop teslamate

        # 删除现有数据并重新初始化数据库
        echo "删除现有数据并重新初始化数据库..."
        docker-compose exec -T database psql -U teslamate <<EOF
drop schema public cascade;
create schema public;
create extension cube;
create extension earthdistance;
CREATE OR REPLACE FUNCTION public.ll_to_earth(float8, float8)
    RETURNS public.earth
    LANGUAGE SQL
    IMMUTABLE STRICT
    PARALLEL SAFE
    AS 'SELECT public.cube(public.ll_to_earth(\$1, \$2))';
EOF

        # 从备份还原数据
        echo "从备份文件恢复数据..."
        docker-compose exec -T database psql -U teslamate teslamate < $BACKUP_PATH

        # 启动 TeslaMate 容器
        echo "启动 TeslaMate 容器..."
        docker-compose start teslamate

        echo "数据还原完成！"
        ;;

    4)
        echo "退出脚本。"
        exit 0
        ;;

    *)
        echo "无效的选项，请选择 1-4 之间的数字。"
        exit 1
        ;;
esac
