#!/usr/bin/env bash
# 把 config/<product>/build.env 的 PKG_RELEASE 設成當天日期。
# 用於上游 VERSION 沒變、但建置內容改了(模組、configure 參數、
# 依賴版本)而需要重新發佈套件的情況。
# 同一天再發一次就接上 .2、.3:tag 必須唯一,而 rpm 與 deb 都把
# 20260820.2 排在 20260820 之後,升級路徑仍然正確。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=${1:?usage: bump-release.sh <product>}
load_env "$PRODUCT"

date="$(today)"
case "$PKG_RELEASE" in
    "$date") next="$date.2" ;;
    "$date".*) next="$date.$(( ${PKG_RELEASE##*.} + 1 ))" ;;
    *) next="$date" ;;
esac

set_env_var "$PRODUCT" PKG_RELEASE "$next"
echo "$PRODUCT: PKG_RELEASE $PKG_RELEASE -> $next (VERSION $VERSION)"
