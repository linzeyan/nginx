#!/usr/bin/env bash
# 用 dist/ 內的產物建立 GitHub release。
# tag 已存在時直接失敗、不覆蓋:同一上游版本重發必須 bump PKG_RELEASE。
# 需要已認證的 `gh`。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=${1:?usage: release.sh <product>}
load_env "$PRODUCT"
TAG="$PRODUCT-$VERSION-$PKG_RELEASE"

if gh release view "$TAG" >/dev/null 2>&1; then
    die "release $TAG already exists — bump PKG_RELEASE in config/$PRODUCT/build.env"
fi

cd "$ROOT/dist"
# 檔名帶的是套件名(FAMILY)而非產品線,再以 VERSION 限定 —— 本地跑過
# make all 之後 dist/ 會同時有 stable 與 mainline 的 nginx 套件,少了
# VERSION 這段就會把兩條線的產物一起發進同一個 release。
# deb 檔名在套件名後接 '_',rpm 與 tar.gz 接 '-'。
files=( "$FAMILY"[_-]"$VERSION"-* )
[[ -f "${files[0]}" ]] || die "no artifacts for $PRODUCT in dist/"

sha256sum "${files[@]}" > SHA256SUMS

notes="$(mktemp)"
# 走 bash 而非直接執行:repo 內的腳本都不帶 executable bit,
# 呼叫方式統一(Makefile 與 clone_modules 的 prep hook 也是這樣)。
bash "$ROOT/scripts/release-notes.sh" "$PRODUCT" > "$notes"
gh release create "$TAG" --title "$TAG" --notes-file "$notes" \
    "${files[@]}" SHA256SUMS

echo "released $TAG"
