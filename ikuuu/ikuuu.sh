#!/bin/bash
#### 機場簽到腳本+gotify通知版本 ####

EMAIL="你的邮箱"
PASSWORD="你的密码"
BASE_URL="https://ikuuu.nl"
GOTIFY_URL="https://你的gotify域名/message"
GOTIFY_TOKEN="你的token"

# 登录
curl -s -c cookies.txt \
  -X POST "$BASE_URL/auth/login" \
  -d "email=$EMAIL" \
  -d "passwd=$PASSWORD" \
  -d "remember_me=1" > /dev/null

# 签到
RESULT=$(curl -s -b cookies.txt -X POST "$BASE_URL/user/checkin")

echo "签到结果：$RESULT"

# 判断是否成功获得奖励
if echo "$RESULT" | grep -q '"ret":1' && echo "$RESULT" | grep -Eq 'MB|GB'; then
    exit 0
fi

# 判断是否重复签到
if echo "$RESULT" | grep -q '已经签到'; then
    exit 0
fi

# 其他情况 → 推送失败
curl -s -X POST "$GOTIFY_URL?token=$GOTIFY_TOKEN" \
    -F "title=Ikuuu 签到失败" \
    -F "message=$RESULT" \
    -F "priority=5" > /dev/null
