#!/bin/sh
# 只在完整移除時停服務,升級時不停:rpm 移除時 $1=0(升級 >=1),
# deb 則傳 "remove"/"upgrade"。
case "${1:-}" in
    0|remove)
        if command -v systemctl >/dev/null 2>&1; then
            systemctl stop openresty.service >/dev/null 2>&1 || true
            systemctl disable openresty.service >/dev/null 2>&1 || true
        fi
        ;;
esac
exit 0
