#!/bin/bash

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "            TESLAMATE 一键安装脚本            "
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

# 显示主菜单
echo "请选择一个选项："
echo "1. 安装 TeslaMate"
echo "2. 备份 TeslaMate"
echo "3. 安装 TeslaMate 并创建自动备份"
echo "4. 一键自动还原数据"
echo "5. 退出"

read -p "请输入选项（1-5）: " OPTION

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
        else
            echo "检测到您的架构是 $ARCH - 安装中文版..."
            TESLAMATE_IMAGE="ccr.ccs.tencentyun.com/dhuar/teslamate:latest"
            GRAFANA_IMAGE="ccr.ccs.tencentyun.com/dhuar/grafana:latest"
        fi

        # 安装 Docker 和 Docker Compose
        apt-get update
        if [ ! -f "/usr/bin/docker" ]; then
            echo "安装 Docker..."
            apt install -y docker.io
        else
            echo "Docker 已安装!"
        fi

        if [ ! -f "/usr/local/bin/docker-compose" ]; then
            echo "安装 Docker Compose..."
            apt install -y docker-compose
        else
            echo "Docker Compose 已安装!"
        fi

        # 创建目录
        if [ ! -d "/opt/teslamate" ]; then
            mkdir /opt/teslamate
        else
            rm -rf /opt/teslamate
            mkdir /opt/teslamate
        fi
        cd /opt/teslamate

        # 创建 docker-compose.yml 配置文件
        cat <<EOF > docker-compose.yml
version: "3"

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
            if [ "$BACKUP_SIZE" -gt 0 ]; then
                echo "备份测试成功！文件大小为 ${BACKUP_SIZE} 字节。"
            else
                echo "备份测试失败，请检查 TeslaMate 的目录路径是否正确。"
            fi
        else
            echo "备份脚本已创建，但未执行备份测试。"
        fi

        # 自动添加到定时任务
        read -p "请输入定时任务时间（格式为：每天备份，请输入 '0 1 * * *'，每小时备份，请输入 '0 * * * *'，每周备份，请输入 '0 0 * * 0'）： " CRON_TIME
        (crontab -l 2>/dev/null; echo "$CRON_TIME /bin/bash $BACKUP_DIR/backup_teslamate.sh") | crontab -
        echo "定时任务已设置，备份时间为 $CRON_TIME。"
        ;;

    3)
        echo "正在安装 TeslaMate 并创建自动备份..."

        # 调用选项1（安装 TeslaMate）
        # 检测系统架构
        ARCH=$(uname -m)
        if [[ "$ARCH" == "armv7l" || "$ARCH" == "armhf" ]]; then
            echo "检测到您的架构是 32 位 ARM 架构 - 安装英文版本..."
            TESLAMATE_IMAGE="teslamate/teslamate:latest"
            GRAFANA_IMAGE="teslamate/grafana:latest"
        else
            echo "检测到您的架构是 $ARCH - 安装中文版..."
            TESLAMATE_IMAGE="ccr.ccs.tencentyun.com/dhuar/teslamate:latest"
            GRAFANA_IMAGE="ccr.ccs.tencentyun.com/dhuar/grafana:latest"
        fi

        # 安装 Docker 和 Docker Compose
        apt-get update
        if [ ! -f "/usr/bin/docker" ]; then
            echo "安装 Docker..."
            apt install -y docker.io
        else
            echo "Docker 已安装!"
        fi

        if [ ! -f "/usr/local/bin/docker-compose" ]; then
            echo "安装 Docker Compose..."
            apt install -y docker-compose
        else
            echo "Docker Compose 已安装!"
        fi

        # 创建目录
        if [ ! -d "/opt/teslamate" ]; then
            mkdir /opt/teslamate
        else
            rm -rf /opt/teslamate
            mkdir /opt/teslamate
        fi
        cd /opt/teslamate

        # 创建 docker-compose.yml 配置文件
        cat <<EOF > docker-compose.yml
version: "3"

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

        # 创建备份脚本
        cat <<EOF > backup_teslamate.sh
#!/bin/bash
# 切换到 TeslaMate 目录
cd /opt/teslamate

# 执行备份命令
docker-compose exec -T database pg_dump -U teslamate teslamate > /opt/teslamate/teslamate.bck

# 获取当前时间
CURRENT_TIME=\$(date +"%Y年%m月%d日 %H:%M:%S")

# 获取备份文件大小（以MB为单位，保留两位小数）
BACKUP_SIZE=\$(stat -c%s "/opt/teslamate/teslamate.bck")
BACKUP_SIZE_MB=\$(echo "scale=2; \$BACKUP_SIZE/1024/1024" | bc)

# 记录备份时间和文件大小
echo "备份完成于 \$CURRENT_TIME，备份文件大小为 \${BACKUP_SIZE_MB}M。" >> /opt/teslamate/backup_log.txt
EOF

        # 设置脚本可执行权限
        chmod +x backup_teslamate.sh

        # 自动添加到定时任务
        read -p "请输入定时任务时间（格式为：每天备份，请输入 '0 1 * * *'，每小时备份，请输入 '0 * * * *'，每周备份，请输入 '0 0 * * 0'）： " CRON_TIME
        (crontab -l 2>/dev/null; echo "$CRON_TIME /bin/bash /opt/teslamate/backup_teslamate.sh") | crontab -
        echo "定时任务已设置，备份时间为 $CRON_TIME。"
        ;;

    4)
        echo "正在还原 TeslaMate 数据..."

        # 自定义 TeslaMate 目录
        read -p "请输入 TeslaMate 安装目录 (默认: /opt/teslamate): " TESLAMATE_DIR
        TESLAMATE_DIR=${TESLAMATE_DIR:-/opt/teslamate}

        # 自定义备份文件路径
        read -p "请输入备份文件路径 (默认: /opt/teslamate/teslamate.bck): " BACKUP_PATH
        BACKUP_PATH=${BACKUP_PATH:-/opt/teslamate/teslamate.bck}

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
    AS 'SELECT public.cube(public.cube(public.cube(public.earth()*cos(radians(\$1))*cos(radians(\$2))),public.earth()*cos(radians(\$1))*sin(radians(\$2))),public.earth()*sin(radians(\$1)))::public.earth';
EOF

        # 恢复数据
        echo "恢复数据..."
        docker-compose exec -T database psql -U teslamate -d teslamate < $BACKUP_PATH

        # 重启 TeslaMate 容器
        echo "重新启动 TeslaMate 容器..."
        docker-compose start teslamate

        echo "数据还原完成!"
        ;;

    5)
        echo "退出脚本"
        exit 0
        ;;

    *)
        echo "无效选项，请重新选择。"
        ;;
esac
