#!/usr/bin/env bash
# 比對 config/*/build.env 內 pin 的 VERSION 與上游最新版。
# 帶 --update 時改寫 build.env(並把 PKG_RELEASE 重設為 1)。
# 在 GitHub Actions 裡會把 `changed` 與 `summary` 寫進 $GITHUB_OUTPUT。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

# stable 線 = minor 為偶數的最高版本。
latest_nginx() {
    curl -fsSL --retry 3 https://nginx.org/download/ \
        | tr '"' '\n' \
        | sed -n 's/^nginx-\([0-9]*\.[0-9]*\.[0-9]*\)\.tar\.gz$/\1/p' \
        | sort -uV \
        | awk -F. '$2 % 2 == 0' \
        | tail -1
}

# GitHub API 對未認證請求按來源 IP 計 rate limit(60/hr),Actions runner 的
# 出口 IP 是共用的,配額常常在別人手上就被用完 -> 403。有 token 就帶上,
# 額度改為按 repo 計(1000/hr)。本機沒 token 時仍可跑,只是吃共用配額。
latest_openresty() {
    local auth=(-H "Accept: application/vnd.github+json")
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    curl -fsSL --retry 3 "${auth[@]}" \
        https://api.github.com/repos/openresty/openresty/releases/latest \
        | tr ',' '\n' \
        | sed -n 's/.*"tag_name": *"v\([0-9.]*\)".*/\1/p' \
        | head -1
}

current_version() {
    (load_env "$1" && echo "$VERSION")
}

# 換上游版本時套件版次歸 1。
bump_env() { # <product> <new-version>
    set_env_var "$1" VERSION "$2"
    set_env_var "$1" PKG_RELEASE 1
}

changed=()
summary=()
for product in nginx openresty; do
    current="$(current_version "$product")"
    latest="$(latest_"$product")"
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
