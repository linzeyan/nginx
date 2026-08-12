#!/usr/bin/env bash
# build/package/release 腳本共用的輔助函式,任何錯誤都直接失敗。
# 刻意不依賴外部工具(純 bash + coreutils),host 與 almalinux:8
# 建置容器內都能執行。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
    echo "error: $*" >&2
    exit 1
}

# 載入 config/<product>/build.env(VERSION、PKG_RELEASE、依賴版本)。
load_env() {
    # shellcheck source=/dev/null
    source "$ROOT/config/$1/build.env"
}

# 就地改寫 config/<product>/build.env 內某個變數的值,
# 保留檔案其餘內容(註解、順序)不動。
set_env_var() { # <product> <key> <value>
    local file="$ROOT/config/$1/build.env" tmp line
    tmp="$(mktemp)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$2="* ]]; then
            echo "$2=$3"
        else
            echo "$line"
        fi
    done < "$file" > "$tmp"
    mv "$tmp" "$file"
}

# deb 風格架構名,用於套件 metadata 與產物檔名。
pkg_arch() {
    case "$(uname -m)" in
        x86_64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) die "unsupported arch: $(uname -m)" ;;
    esac
}

# rpm 風格架構名,只用來定位 nfpm 輸出的 rpm 檔名。
rpm_arch() {
    case "$(uname -m)" in
        x86_64) echo x86_64 ;;
        aarch64 | arm64) echo aarch64 ;;
        *) die "unsupported arch: $(uname -m)" ;;
    esac
}

# almalinux:8 建置容器的工具鏈;其他環境視為已具備工具、直接跳過,
# 讓建置腳本也能在一般 Linux host 上執行。
install_build_deps() {
    command -v dnf >/dev/null 2>&1 || return 0

    dnf -y -q install dnf-plugins-core >/dev/null
    # libxslt-devel 與 gd-devel 在 EL8 屬於 PowerTools,預設關閉;
    # 各衍生版的 repo 名稱大小寫不一致,兩種都試。
    dnf -y -q config-manager --set-enabled powertools >/dev/null 2>&1 \
        || dnf -y -q config-manager --set-enabled PowerTools >/dev/null 2>&1 \
        || true

    dnf -y -q install gcc gcc-c++ make perl perl-IPC-Cmd git tar gzip \
        patch findutils diffutils cmake automake autoconf libtool \
        libxml2-devel libxslt-devel gd-devel >/dev/null
}

# 下載 .tar.gz 原始碼並解壓到 $2。
fetch_src() {
    local url=$1 dest=$2
    echo "fetching $url"
    curl -fsSL --retry 3 -o "$dest/$(basename "$url")" "$url"
    tar -xzf "$dest/$(basename "$url")" -C "$dest"
}

# 以靜態形式建置 libmaxminddb 並裝進系統預設搜尋路徑,讓 geoip2 模組的
# -lmaxminddb 連到 .a。這樣 geoip2 就不會替套件帶進執行期依賴 ——
# EL 系的 libmaxminddb 只在 EPEL,對使用者是額外負擔。
# libdir 寫死 lib64:建置容器固定是 almalinux:8,x86_64 與 aarch64 皆然。
build_libmaxminddb() {
    local src=$1 version=$2
    echo "building static libmaxminddb $version"
    cd "$src/libmaxminddb-$version"
    ./configure --prefix=/usr --libdir=/usr/lib64 \
        --disable-shared --enable-static >/dev/null
    make -j"$(nproc)" >/dev/null
    make install >/dev/null
    cd - >/dev/null
}

# 輸出 configure-args.conf 內容:一行一個參數(取字面值),
# 空行與 '#' 行跳過。
read_args() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
        echo "$line"
    done < "$1"
}

# 逐一取得 modules.conf($1)列出的模組到 $2,每行輸出一個可直接餵給
# --add-module 的目錄。行格式:<name> <git-url> <git-ref> [subdir]。
# 用 fetch 而非 clone --branch,因為後者不接受 commit SHA。
clone_modules() {
    local conf=$1 dest=$2 name url ref subdir target
    mkdir -p "$dest"
    while read -r name url ref subdir || [[ -n "$name" ]]; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        [[ -n "$url" && -n "$ref" ]] || die "malformed line in $conf: '$name $url $ref'"
        echo "fetching module $name ($url @ $ref)" >&2
        target="$dest/$name"
        git init -q "$target" >&2
        git -C "$target" remote add origin "$url" >&2
        git -C "$target" fetch -q --depth 1 origin "$ref" >&2
        git -C "$target" checkout -q FETCH_HEAD >&2
        git -C "$target" submodule update -q --init --depth 1 --recursive >&2
        echo "$target${subdir:+/$subdir}"
    done < "$conf"
}
