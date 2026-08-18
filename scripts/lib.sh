#!/usr/bin/env bash
# build/package/release 腳本共用的輔助函式,任何錯誤都直接失敗。
# 刻意不依賴外部工具(純 bash + coreutils),host 與 almalinux:8
# 建置容器內都能執行。
# -E:讓下面的 ERR trap 也在函式、subshell 與 $(...) 內生效,
# 否則大多數失敗(它們都發生在函式裡)不會被回報。
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# GitHub Actions annotation:讓失敗直接顯示在 job 摘要,不必展開 log。
# 非 CI 環境是 no-op。訊息裡的 % 與換行必須照 Actions 的規則跳脫。
ci_error() { # <file> <line> <message>
    [[ -n "${GITHUB_ACTIONS:-}" ]] || return 0
    local msg=${3//'%'/%25}
    msg=${msg//$'\r'/%0D}
    msg=${msg//$'\n'/%0A}
    printf '::error file=%s,line=%s::%s\n' "${1#"$ROOT"/}" "$2" "$msg" >&2
}

# 沒有這個 trap 時,CI log 只會留下 make 轉述的 exit code
# (例:`make: *** [Makefile:46] Error 22`),看不出是哪支腳本的哪一行、
# 哪個指令掛掉 —— 尤其 set -e 會在 die() 之前就中止,自訂訊息根本印不到。
# 這裡補上失敗指令與呼叫堆疊,失敗一次就足以定位,不用重跑。
on_err() { # <status> <failed-command>
    local status=$1 cmd=$2 i
    echo "error: command failed (exit $status): $cmd" >&2
    for (( i = 1; i < ${#FUNCNAME[@]}; i++ )); do
        echo "  at ${FUNCNAME[i]} (${BASH_SOURCE[i]##*/}:${BASH_LINENO[i-1]})" >&2
    done
    ci_error "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "exit $status: $cmd"
    # set -e 本來就會在這之後中止,提早 exit 只是不讓同一個錯誤沿著呼叫鏈
    # 逐層再觸發一次 trap(每層都會重印一份堆疊與 annotation)。
    exit "$status"
}
trap 'on_err $? "$BASH_COMMAND"' ERR

die() {
    echo "error: $*" >&2
    ci_error "${BASH_SOURCE[1]:-$0}" "${BASH_LINENO[0]:-0}" "$*"
    exit 1
}

# 載入 config/<product>/build.env(VERSION、PKG_RELEASE、依賴版本)。
# 先自己檢查檔案:source 是 POSIX special builtin,開檔失敗會讓 shell
# 立刻結束而跳過 ERR trap,失敗就只剩一行 bash 內建訊息、沒有 annotation。
load_env() {
    local file="$ROOT/config/$1/build.env"
    [[ -f "$file" ]] || die "unknown product '$1': $file not found"
    # shellcheck source=/dev/null
    source "$file"
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
# 若 scripts/module-prep/<name>.sh 存在,會在模組目錄內執行,供需要
# 事前編譯依賴的模組使用(見該目錄)。
clone_modules() {
    local conf=$1 dest=$2 name url ref subdir target prep
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

        prep="$ROOT/scripts/module-prep/$name.sh"
        if [[ -f "$prep" ]]; then
            echo "preparing module $name" >&2
            ( cd "$target" && bash "$prep" ) >&2
        fi

        echo "$target${subdir:+/$subdir}"
    done < "$conf"
}
