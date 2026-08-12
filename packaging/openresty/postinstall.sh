#!/bin/sh
# rpm($1 = 1|2)與 deb($1 = configure)都會執行這支;
# 以冪等寫法處理,不分別處理兩邊的參數語意。
#
# 一定要建立專用使用者:nginx 內建的預設身分是 nobody:nobody,而
# Debian/Ubuntu 沒有 nobody 這個「群組」(叫 nogroup),master 以 root
# 啟動時會 getgrnam("nobody") 失敗而起不來。
set -e

getent group openresty >/dev/null || groupadd --system openresty
getent passwd openresty >/dev/null || useradd --system --gid openresty \
    --home-dir /usr/local/openresty --no-create-home --shell /sbin/nologin \
    --comment "openresty user" openresty

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
fi
