#!/usr/bin/env bash
# 把 stage 好的安裝樹打包成 .deb/.rpm(nfpm 走 docker)與 tar.gz
# (FHS 佈局,解壓到 / 即可)。產物輸出到 dist/。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=${1:?usage: package.sh <nginx|openresty>}
load_env "$PRODUCT"
PKG_ARCH="$(pkg_arch)"

STAGE="$ROOT/build/$PRODUCT/stage"
[[ -d "$STAGE" ]] || die "no staged build at $STAGE — run 'make build-$PRODUCT' first"

mkdir -p "$ROOT/dist"
export VERSION PKG_RELEASE PKG_ARCH

for packager in deb rpm; do
    docker run --rm -v "$ROOT:/work" -w /work \
        -e VERSION -e PKG_RELEASE -e PKG_ARCH \
        goreleaser/nfpm:latest package \
        --config "nfpm/$PRODUCT.yaml" --packager "$packager" --target dist/
done

tar -C "$STAGE" -czf "$ROOT/dist/$PRODUCT-$VERSION-$PKG_RELEASE-linux-$PKG_ARCH.tar.gz" .

echo "packaged $PRODUCT $VERSION-$PKG_RELEASE ($PKG_ARCH):"
ls -lh "$ROOT/dist"
