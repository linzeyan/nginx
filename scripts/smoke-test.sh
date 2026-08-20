#!/usr/bin/env bash
# 在乾淨的發行版容器內安裝剛打包好的套件,驗證服務啟得起來、
# HTTP 回應正常。這是每次 release 前的守門測試。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=${1:?usage: smoke-test.sh <product>}
load_env "$PRODUCT"
PKG_ARCH="$(pkg_arch)"
RPM_ARCH="$(rpm_arch)"

DEB_IMAGES=(ubuntu:24.04 debian:12)
RPM_IMAGES=(rockylinux:9 almalinux:8)

# 檔名與待驗證的指令都跟著套件名(FAMILY)走,不是產品線:
# nginx-stable 與 nginx-mainline 出的都是套件 nginx。
DEB="${FAMILY}_${VERSION}-${PKG_RELEASE}_${PKG_ARCH}.deb"
RPM="${FAMILY}-${VERSION}-${PKG_RELEASE}.${RPM_ARCH}.rpm"
[[ -f "$ROOT/dist/$DEB" ]] || die "missing dist/$DEB — run 'make package-$PRODUCT' first"
[[ -f "$ROOT/dist/$RPM" ]] || die "missing dist/$RPM — run 'make package-$PRODUCT' first"

case "$FAMILY" in
    nginx)
        CHECK='nginx -V && nginx -t && nginx && sleep 1 \
            && curl -fsS http://127.0.0.1/ >/dev/null && echo SMOKE_OK'
        ;;
    openresty)
        CHECK='export PATH=/usr/local/openresty/bin:$PATH \
            && openresty -V && openresty -t && openresty && sleep 1 \
            && curl -fsS http://127.0.0.1/ >/dev/null \
            && resty -e "print(\"resty ok\")" && echo SMOKE_OK'
        ;;
esac

for image in "${DEB_IMAGES[@]}"; do
    echo "=== $image ==="
    docker run --rm -v "$ROOT/dist:/dist:ro" "$image" bash -c \
        "export DEBIAN_FRONTEND=noninteractive \
         && apt-get update -qq \
         && apt-get install -qq -y curl /dist/$DEB >/dev/null \
         && $CHECK"
done

for image in "${RPM_IMAGES[@]}"; do
    echo "=== $image ==="
    docker run --rm -v "$ROOT/dist:/dist:ro" "$image" bash -c \
        "dnf -y -q install /dist/$RPM \
         && { command -v curl >/dev/null || dnf -y -q install curl; } \
         && $CHECK"
done

echo "smoke tests passed: $PRODUCT $VERSION-$PKG_RELEASE ($PKG_ARCH)"
