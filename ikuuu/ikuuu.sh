#!/bin/bash
# ===== 配置 =====
EMAIL="你的邮箱"
PASSWORD="你的密码"
BASE_URL="https://ikuuu.nl"
# ===== 登录，保存 Cookie =====
curl -s -c cookies.txt \
  -X POST "$BASE_URL/auth/login" \
  -d "email=$EMAIL" \
  -d "passwd=$PASSWORD" \
  -d "remember_me=1" > /dev/null

# ===== 签到 =====
RESULT=$(curl -s -b cookies.txt -X POST "$BASE_URL/user/checkin")

echo "签到结果：$RESULT"
