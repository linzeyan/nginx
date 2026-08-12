# OpenResty OpenSSL patches

OpenResty 的進階 SSL Lua API(例如在 `ssl_session_fetch_by_lua*` 內
yield)需要在原版 OpenSSL 上套用 OpenResty 官方的 patch。不套 patch
一樣能正常編譯與執行,只有那些特定 API 會受限。

要啟用時,把 `*.patch` 檔放進這個目錄。`scripts/build-openresty.sh`
會在 OpenSSL 原始碼目錄內依檔名順序以 `patch -p1` 套用。

請到下列位置取得與 `../build.env` 內 `OPENSSL_VERSION` 對應版本的 patch:
https://github.com/openresty/openresty/tree/master/patches
