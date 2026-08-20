#!/usr/bin/env bash
# 把 stage 好的安裝樹打包成 .deb/.rpm(nfpm 走 docker)與 tar.gz
# (FHS 佈局,解壓到 / 即可)。產物輸出到 dist/。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=${1:?usage: package.sh <product>}
load_env "$PRODUCT"
PKG_ARCH="$(pkg_arch)"

STAGE="$ROOT/build/$PRODUCT/stage"
[[ -d "$STAGE" ]] || die "no staged build at $STAGE — run 'make build-$PRODUCT' first"

mkdir -p "$ROOT/dist"
# 產物與 nfpm 設定都掛在 FAMILY 底下:nginx 的 stable 與 mainline 兩條線
# 出的是同一個套件 nginx(可互相升級),只有 VERSION 不同。
export VERSION PKG_RELEASE PKG_ARCH

# 這條產品線的安裝樹掛到固定的 /stage,nfpm 設定就不必知道是哪條線。
# 不用環境變數是因為 nfpm 只對 version/release 那類欄位做展開,
# contents 的 src 會原封不動地拿 `${PRODUCT}` 去 glob 而失敗。
for packager in deb rpm; do
    docker run --rm -v "$ROOT:/work" -v "$STAGE:/stage:ro" -w /work \
        -e VERSION -e PKG_RELEASE -e PKG_ARCH \
        goreleaser/nfpm:latest package \
        --config "nfpm/$FAMILY.yaml" --packager "$packager" --target dist/
done

tar -C "$STAGE" -czf "$ROOT/dist/$FAMILY-$VERSION-$PKG_RELEASE-linux-$PKG_ARCH.tar.gz" .

echo "packaged $PRODUCT $VERSION-$PKG_RELEASE ($PKG_ARCH):"
ls -lh "$ROOT/dist"
