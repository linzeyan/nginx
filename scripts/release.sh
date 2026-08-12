#!/usr/bin/env bash
# 用 dist/ 內的產物建立 GitHub release。
# tag 已存在時直接失敗、不覆蓋:同一上游版本重發必須 bump PKG_RELEASE。
# 需要已認證的 `gh`。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=${1:?usage: release.sh <nginx|openresty>}
load_env "$PRODUCT"
TAG="$PRODUCT-$VERSION-$PKG_RELEASE"

if gh release view "$TAG" >/dev/null 2>&1; then
    die "release $TAG already exists — bump PKG_RELEASE in config/$PRODUCT/build.env"
fi

cd "$ROOT/dist"
# deb 檔名在產品名後接 '_',rpm 與 tar.gz 接 '-'。
files=( "$PRODUCT"[_-]* )
[[ -f "${files[0]}" ]] || die "no artifacts for $PRODUCT in dist/"

sha256sum "${files[@]}" > SHA256SUMS

notes="$(mktemp)"
"$ROOT/scripts/release-notes.sh" "$PRODUCT" > "$notes"
gh release create "$TAG" --title "$TAG" --notes-file "$notes" \
    "${files[@]}" SHA256SUMS

echo "released $TAG"
