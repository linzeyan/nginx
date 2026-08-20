#!/usr/bin/env bash
# 比對 config/*/build.env 內 pin 的 VERSION 與上游最新版。
# 帶 --update 時改寫 build.env(並把 PKG_RELEASE 重設為當天日期)。
# 在 GitHub Actions 裡會把 `changed` 與 `summary` 寫進 $GITHUB_OUTPUT。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

PRODUCTS=(nginx-stable nginx-mainline openresty)

# nginx.org 的下載目錄,升冪排序後的所有正式版。
nginx_versions() {
    curl -fsSL --retry 3 https://nginx.org/download/ \
        | tr '"' '\n' \
        | sed -n 's/^nginx-\([0-9]*\.[0-9]*\.[0-9]*\)\.tar\.gz$/\1/p' \
        | sort -uV
}

latest_version() { # <product>
    case "$1" in
        # stable 線 = minor 為偶數的最高版本;mainline = 最高版本。
        nginx-stable) nginx_versions | awk -F. '$2 % 2 == 0' | tail -1 ;;
        nginx-mainline) nginx_versions | tail -1 ;;
        # 刻意不走 GitHub 的 releases API:OpenResty 從 1.29 起只打 git
        # tag、不再發 GitHub Release,`releases/latest` 會一直停在
        # 1.27.1.2。官網下載目錄才是建置實際取用的來源,也不必帶 token。
        openresty)
            curl -fsSL --retry 3 https://openresty.org/download/ \
                | tr '"' '\n' \
                | sed -n 's/^openresty-\([0-9][0-9.]*\)\.tar\.gz$/\1/p' \
                | sort -uV \
                | tail -1
            ;;
        *) die "no upstream version source for product '$1'" ;;
    esac
}

current_version() {
    (load_env "$1" && echo "$VERSION")
}

# 換上游版本時套件版次重設為當天日期。
bump_env() { # <product> <new-version>
    set_env_var "$1" VERSION "$2"
    set_env_var "$1" PKG_RELEASE "$(today)"
}

changed=()
summary=()
for product in "${PRODUCTS[@]}"; do
    current="$(current_version "$product")"
    latest="$(latest_version "$product")"
    [[ -n "$latest" ]] || die "could not determine latest $product version"
    if [[ "$latest" == "$current" ]]; then
        echo "$product: $current (up to date)"
    else
        echo "$product: $current -> $latest"
        changed+=("$product")
        summary+=("$product $current -> $latest")
        if (( UPDATE )); then
            bump_env "$product" "$latest"
        fi
    fi
done

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "changed=${changed[*]:-}" >> "$GITHUB_OUTPUT"
    echo "summary=$(IFS='; '; echo "${summary[*]:-}")" >> "$GITHUB_OUTPUT"
fi
