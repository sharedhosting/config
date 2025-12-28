#!/bin/bash

# SSH公钥 (请将你的公钥粘贴在这里)
KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHU4I+uqyj6l254xb2LjyO/STXpf2m0lraFGf/8MPFUq"

# 要安装的应用程序 (用空格分隔)
APP="screen apt-transport-https ca-certificates zstd nano curl zip unzip mc"

# .my_aliases 文件的URL
ALIASES_URL="https://raw.githubusercontent.com/petcat/my.config/refs/heads/master/ssh/.my_aliases"

# --- 脚本主体 ---
set -e  # 遇到错误时退出

echo "开始VPS初始化..."

# 1. 系统更新
echo "正在更新系统..."
apt update && apt upgrade -y

# 2. 安装指定的软件
if [ -n "$APP" ]; then
    echo "正在安装软件: $APP"
    apt install -y $APP
fi

# 3. 设置SSH密钥认证
if [ -n "$KEY" ]; then
    echo "配置SSH密钥认证..."
    SSH_DIR="/root/.ssh"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    echo "$KEY" >> "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"

    # 备份并修改SSH配置
    SSH_CONFIG_FILE="/etc/ssh/sshd_config"
    cp "$SSH_CONFIG_FILE" "${SSH_CONFIG_FILE}.bak"
    echo "SSH配置已备份到 ${SSH_CONFIG_FILE}.bak"

    # 启用密钥认证，允许root登录
    sed -i 's/^#*PubkeyAuthentication yes/PubkeyAuthentication yes/' "$SSH_CONFIG_FILE"
    sed -i 's/^#*PermitRootLogin .*/PermitRootLogin yes/' "$SSH_CONFIG_FILE"

    # *只有*在设置了密钥时才禁止密码登录
    sed -i 's/^#*PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG_FILE"

    # 重启SSH服务
    systemctl restart sshd

    echo "SSH配置已更新。密钥登录已启用，密码登录已禁用。"
else
    echo "警告: 未设置SSH公钥，跳过密钥配置。密码登录仍处于启用状态，存在安全风险。"
    # 注意：在这种情况下，我们不修改 PasswordAuthentication 的设置，保持其默认值
fi

# 4. 设置固定的 .profile 内容
echo "设置 .profile..."
cat > /root/.profile << 'EOF'
# ==================================
# 通用Alias: .profile + .my_aliases 
# ==================================
# 基本环境变量
export PATH="$HOME/bin:$PATH"
export HISTSIZE=5000
# 核心 alias (通用)
alias ls='ls -A --color=auto'
alias ll='ls -ahlF --color=auto'
alias lll='ls -lahFR --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias reprofile='. ~/.profile'
alias iprofile='source ~/.profile'
alias ialiases='nano ~/.my_aliases'

# 提示符：绿色用户@主机 + 蓝色路径
# PS1="\033[32m\u@\h:\033[34m\w\033[0m#"
PS1="\033[33m[\t]\033[32m\u@\h:\033[34m\w\033[0m#"
# PS1="\033[31m[\t]\033[33m\u@\h:\033[32m\w\033[0m#"

# 如果存在扩展 alias 文件，就加载它
[ -f ~/.my_aliases ] && . ~/.my_aliases
EOF

# 5. 从URL下载 .my_aliases 文件 (如果URL不为空)
if [ -n "$ALIASES_URL" ]; then
    echo "从 $ALIASES_URL 下载 .my_aliases..."
    if command -v wget >/dev/null 2>&1; then
        wget -O /root/.my_aliases "$ALIASES_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -o /root/.my_aliases "$ALIASES_URL"
    else
        echo "错误: 系统中未找到 wget 或 curl，无法下载 .my_aliases"
        exit 1
    fi
    chmod 644 /root/.my_aliases # 设置权限为可读可写，组和其他用户只读
    echo ".my_aliases 已下载并设置权限。"
else
    echo "未提供 ALIASES_URL，跳过下载 .my_aliases。"
fi

# 6. 开启BBR
echo "启用BBR..."
if [[ $(uname -r) > "4.9" ]]; then
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    sysctl -p
    if lsmod | grep bbr > /dev/null; then
        echo "BBR已成功启用。"
    else
        echo "BBR可能未成功启用。"
    fi
else
    echo "当前内核版本低于4.9，可能不支持BBR。"
fi

# 7. 限制日志占用空间
echo "配置日志限制..."

# 7a. 配置 journald
JOURNALD_CONF="/etc/systemd/journald.conf"
if [ -f "$JOURNALD_CONF" ]; then
    # 备份原配置文件
    cp "$JOURNALD_CONF" "${JOURNALD_CONF}.bak"
    echo "journald配置已备份到 ${JOURNALD_CONF}.bak"

    # 设置日志大小限制
    sed -i 's/^#*SystemMaxUse=.*/SystemMaxUse=32M/' "$JOURNALD_CONF"
    sed -i 's/^#*SystemKeepFree=.*/SystemKeepFree=64M/' "$JOURNALD_CONF"
    sed -i 's/^#*SystemMaxFileSize=.*/SystemMaxFileSize=4M/' "$JOURNALD_CONF"
    sed -i 's/^#*SystemMaxFiles=.*/SystemMaxFiles=5/' "$JOURNALD_CONF"

    # 重新加载systemd-journald服务以应用更改
    systemctl force-reload systemd-journald || systemctl restart systemd-journald
    echo "journald日志限制已设置。"
else
    echo "警告: 未找到 $JOURNALD_CONF，跳过journald配置。"
fi

# 7b. 配置 rsyslog (如果存在)
RSYSLOG_CONF="/etc/rsyslog.conf"
if command -v rsyslogd >/dev/null 2>&1 && [ -f "$RSYSLOG_CONF" ]; then
    echo "配置 rsyslog..."
    cp "$RSYSLOG_CONF" "${RSYSLOG_CONF}.bak"
    echo "rsyslog配置已备份到 ${RSYSLOG_CONF}.bak"

    # 可以通过注释掉某些日志行来减少日志记录
    # 例如，减少mail相关的日志: sed -i 's/^\(\*.\*.*\/var\/log\/mail\)/# \1/' "$RSYSLOG_CONF"
    # 这里可以加入更多针对特定日志的规则
    # 例如，注释掉 authpriv 的详细日志 (这会减少登录等信息的记录)
    # sed -i '/authpriv\*\.\*\/var\/log\/secure/s/^/# /' "$RSYSLOG_CONF"

    systemctl restart rsyslog
    echo "rsyslog配置已更新。"
fi

# 7c. 配置 logrotate 以更积极地管理 /var/log
# 不使用通配符，而是创建一个更通用的配置，或者只针对常见的、未被其他配置文件管理的日志
LOGROTATE_DIR="/etc/logrotate.d"
LOGROTATE_VPS_FILE="$LOGROTATE_DIR/vps_optimization"

# 创建一个自定义的logrotate配置文件，但不使用通配符，以避免冲突
# 这里我们只配置一些常见的、可能需要更严格限制的日志
cat > "$LOGROTATE_VPS_FILE" << 'EOF'
# VPS优化: 限制特定日志文件的大小和数量
# 注意：不使用通配符，以避免与现有配置冲突
# 这里可以为特定日志添加规则，例如：
# /var/log/exim4/*.log {
#     daily
#     missingok
#     rotate 2
#     compress
#     delaycompress
#     notifempty
#     maxsize 5M
#     copytruncate
# }
# 或者，创建一个更通用的规则，但排除已知的冲突文件
# 对于大多数标准日志，我们依赖系统默认配置，但可以在此处覆盖特定行为
# 如果需要对大量日志进行统一管理，可以考虑使用 logrotate 的 include 指令
# 但最安全的方式是针对具体文件进行配置
EOF

echo "已创建 logrotate 配置: $LOGROTATE_VPS_FILE (内容为空，以避免冲突)"

# 7d. 立即执行一次 logrotate 以应用新规则并清理现有日志
# 在执行前先测试配置，避免错误
logrotate -d /etc/logrotate.conf 2>&1 | grep -i error || echo "logrotate 配置测试通过或无错误。"
logrotate -f /etc/logrotate.conf

echo "日志限制配置完成。"

# 8. 配置 rc.local 开机启动
echo "配置 rc.local 开机启动脚本..."
RC_LOCAL_FILE="/etc/rc.local"

# 检查是否存在systemd服务来管理rc.local
if systemctl list-unit-files | grep -q rc-local.service; then
    # 如果存在，确保它被启用
    systemctl enable rc-local.service
    echo "rc-local.service 已启用。"
else
    # 如果不存在，我们可能需要创建它或依赖传统方式 (这在较新的系统上可能不工作)
    # 更推荐的方式是创建一个systemd服务单元文件
    echo "警告: 未找到 rc-local.service。将尝试创建一个。"
    SYSTEMD_SERVICE_FILE="/etc/systemd/system/rc-local.service"
    cat > "$SYSTEMD_SERVICE_FILE" << 'EOF'
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload
    systemctl enable rc-local.service
    echo "已创建并启用自定义 rc-local.service。"
fi

# 创建或更新 /etc/rc.local 文件
cat > "$RC_LOCAL_FILE" << 'EOF'
#!/bin/bash
# rc.local
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

# 添加你的开机启动命令
# 例如:
# /usr/local/bin/my_custom_service.sh &
# echo "System started at $(date)" >> /var/log/rc.local.log

exit 0
EOF

chmod +x "$RC_LOCAL_FILE"
echo "rc.local 文件已创建/更新。"

# 9. 替换 /etc/motd (如果motd文件存在)
SCRIPT_DIR=$(dirname -- "$0")
MOTD_FILE="$SCRIPT_DIR/motd"
if [ -f "$MOTD_FILE" ]; then
    echo "替换 /etc/motd..."
    cp "$MOTD_FILE" /etc/motd
    echo "motd文件已更新。"
else
    echo "同目录下未找到 motd 文件，跳过替换。"
fi

# 10. 执行同目录下的其他shell脚本 (放在最后，按文件名排序，出错则报告并继续)
echo "执行同目录下的其他shell脚本..."
# 使用数组和sort来确保脚本按名称排序执行
shopt -s nullglob # 如果没有匹配的文件，模式扩展为空而不是字面量
script_files=("$SCRIPT_DIR"/*.sh)
sorted_scripts=($(printf '%s\n' "${script_files[@]}" | sort))

for script in "${sorted_scripts[@]}"; do
    if [ "$script" != "$0" ]; then
        echo "执行 $script"
        chmod +x "$script"
        # 使用子shell运行，这样即使脚本出错也不会导致主脚本退出 (因为set -e)
        if ! ( "$script" ); then
            echo "警告: 脚本 $script 执行失败，跳过并继续执行下一个脚本。"
            # 不退出，继续循环
        fi
    fi
done

echo "VPS初始化完成！"
if [ -n "$KEY" ]; then
    echo "请确保在断开当前SSH连接前，验证新的SSH密钥登录方式是否有效。"
else
    echo "警告: 由于未配置SSH密钥，密码登录仍然启用。请尽快设置SSH密钥并手动禁用密码登录以提高安全性。"
fi
