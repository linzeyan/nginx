#!/bin/sh
# rpm($1 = 1|2)與 deb($1 = configure)都會執行這支;
# 以冪等寫法處理,不分別處理兩邊的參數語意。
set -e

getent group nginx >/dev/null || groupadd --system nginx
getent passwd nginx >/dev/null || useradd --system --gid nginx \
    --home-dir /var/cache/nginx --no-create-home --shell /sbin/nologin \
    --comment "nginx user" nginx

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
fi
