#!/usr/bin/env bash
# 編譯 OpenResty:靜態連結 OpenSSL/PCRE2/zlib/libmaxminddb,並加入
# config/openresty/modules.conf 列出的額外模組,將安裝樹 stage 出來供打包。
# 預期在 almalinux:8 容器內執行(glibc 2.28 基線,見 Makefile),
# 但在任何有工具鏈的 Linux host 上也能跑。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=openresty
load_env "$PRODUCT"

BUILD="$ROOT/build/$PRODUCT"
SRC="$BUILD/src"
STAGE="$BUILD/stage"
rm -rf "$BUILD"
mkdir -p "$SRC"

install_build_deps

fetch_src "https://openresty.org/download/openresty-${VERSION}.tar.gz" "$SRC"
fetch_src "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" "$SRC"
fetch_src "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz" "$SRC"
fetch_src "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz" "$SRC"
fetch_src "https://github.com/maxmind/libmaxminddb/releases/download/${LIBMAXMINDDB_VERSION}/libmaxminddb-${LIBMAXMINDDB_VERSION}.tar.gz" "$SRC"

build_libmaxminddb "$SRC" "$LIBMAXMINDDB_VERSION"

# OpenResty 進階 SSL Lua API 需要官方的 OpenSSL patch,
# 見 config/openresty/openssl-patches/README.md。
shopt -s nullglob
for p in "$ROOT/config/$PRODUCT/openssl-patches/"*.patch; do
    echo "applying $(basename "$p")"
    patch -d "$SRC/openssl-${OPENSSL_VERSION}" -p1 < "$p"
done
shopt -u nullglob

# njs 預設會偵測並連結 libxslt、系統 zlib 與 QuickJS,那會讓主 binary
# 產生執行期外部依賴;這裡明確關掉,只保留純靜態的核心功能。
export NJS_LIBXSLT=NO NJS_ZLIB=NO NJS_QUICKJS=NO

configure_args=()
while IFS= read -r arg; do
    configure_args+=("$arg")
done < <(read_args "$ROOT/config/$PRODUCT/configure-args.conf")

configure_args+=(
    "--with-openssl=$SRC/openssl-${OPENSSL_VERSION}"
    "--with-pcre=$SRC/pcre2-${PCRE2_VERSION}"
    "--with-zlib=$SRC/zlib-${ZLIB_VERSION}"
)

while IFS= read -r mod; do
    configure_args+=("--add-module=$mod")
done < <(clone_modules "$ROOT/config/$PRODUCT/modules.conf" "$SRC/modules")

cd "$SRC/openresty-${VERSION}"
./configure "${configure_args[@]}"
make -j"$(nproc)"
make install DESTDIR="$STAGE"

# 不隨包出貨上游的範例檔。nginx.conf 與 conf.d/ 交給 nfpm 以
# config|noreplace 加入,升級時才不會覆蓋使用者改過的設定 ——
# 留在這個 tree 裡的檔案都會被當成一般檔案處理。
CONF="$STAGE/usr/local/openresty/nginx/conf"
rm -f "$CONF/"*.default "$CONF/nginx.conf"

echo "openresty $VERSION staged at $STAGE"
