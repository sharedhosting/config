import requests

EMAIL = "你的邮箱"
PASSWORD = "你的密码"
BASE_URL = "https://ikuuu.nl"

session = requests.Session()

# 登录
login_data = {
    "email": EMAIL,
    "passwd": PASSWORD,
    "remember_me": "1"
}

session.post(f"{BASE_URL}/auth/login", data=login_data)

# 签到
res = session.post(f"{BASE_URL}/user/checkin")
print("签到结果：", res.text)
