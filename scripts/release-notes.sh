#!/usr/bin/env bash
# 從 config 產生 markdown release notes,讓每個 release 都完整記錄
# 這次建置的實際內容(依賴版本、模組、configure 參數)。
# 變數一律用 ${} 包住:後面直接接中文標點時,部分 bash 會把多位元組
# 字元的首個 byte 併進變數名而解析失敗。
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PRODUCT=${1:?usage: release-notes.sh <nginx|openresty>}
load_env "$PRODUCT"

cat <<EOF
## ${PRODUCT} ${VERSION} (package release ${PKG_RELEASE})

靜態連結:OpenSSL ${OPENSSL_VERSION}、PCRE2 ${PCRE2_VERSION}、zlib ${ZLIB_VERSION}、libmaxminddb ${LIBMAXMINDDB_VERSION}。
於 AlmaLinux 8 建置(glibc 2.28 基線):可執行於 RHEL 8+、Debian 11+、Ubuntu 20.04+。

### 第三方模組
EOF

has_modules=0
while read -r name url ref subdir || [[ -n "$name" ]]; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    echo "- \`${name}\`: ${url} @ \`${ref}\`"
    has_modules=1
done < "$ROOT/config/$PRODUCT/modules.conf"
if (( ! has_modules )); then
    echo "(無)"
fi

# 先取值再展開:命令替換若直接寫在 heredoc 裡,read_args 失敗只會讓那一段
# 變空白而 cat 依然成功 —— release notes 少一整段卻沒人發現。
args="$(read_args "$ROOT/config/$PRODUCT/configure-args.conf")"

cat <<EOF

### configure 參數
\`\`\`
${args}
\`\`\`
EOF
