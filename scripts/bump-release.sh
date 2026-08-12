#!/usr/bin/env bash
# 把 config/<product>/build.env 的 PKG_RELEASE +1。
# 用於上游 VERSION 沒變、但建置內容改了(模組、configure 參數、
# 依賴版本)而需要重新發佈套件的情況。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=${1:?usage: bump-release.sh <nginx|openresty>}
load_env "$PRODUCT"

set_env_var "$PRODUCT" PKG_RELEASE "$(( PKG_RELEASE + 1 ))"
echo "$PRODUCT: PKG_RELEASE $PKG_RELEASE -> $(( PKG_RELEASE + 1 )) (VERSION $VERSION)"
