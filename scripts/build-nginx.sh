#!/usr/bin/env bash
# 編譯 nginx:靜態連結 OpenSSL/PCRE2/zlib/libmaxminddb,並加入
# config/nginx/modules.conf 列出的第三方模組,將安裝樹 stage 出來供打包。
# 預期在 almalinux:8 容器內執行(glibc 2.28 基線,見 Makefile),
# 但在任何有工具鏈的 Linux host 上也能跑。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=nginx
load_env "$PRODUCT"

BUILD="$ROOT/build/$PRODUCT"
SRC="$BUILD/src"
STAGE="$BUILD/stage"
rm -rf "$BUILD"
mkdir -p "$SRC"

install_build_deps

fetch_src "https://nginx.org/download/nginx-${VERSION}.tar.gz" "$SRC"
fetch_src "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" "$SRC"
fetch_src "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz" "$SRC"
fetch_src "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz" "$SRC"
fetch_src "https://github.com/maxmind/libmaxminddb/releases/download/${LIBMAXMINDDB_VERSION}/libmaxminddb-${LIBMAXMINDDB_VERSION}.tar.gz" "$SRC"

build_libmaxminddb "$SRC" "$LIBMAXMINDDB_VERSION"

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

cd "$SRC/nginx-${VERSION}"
./configure "${configure_args[@]}"
make -j"$(nproc)"
make install DESTDIR="$STAGE"

# 改用我們的設定檔佈局,不隨包出貨上游的範例檔。
rm -f "$STAGE/etc/nginx/"*.default
install -m 0644 "$ROOT/packaging/nginx/nginx.conf" "$STAGE/etc/nginx/nginx.conf"
mkdir -p "$STAGE/usr/share/nginx"
mv "$STAGE/etc/nginx/html" "$STAGE/usr/share/nginx/html"

echo "nginx $VERSION staged at $STAGE"
