#!/usr/bin/env bash
# ngx_brotli 的 config 不會自己編 brotli:它直接以
# -L deps/brotli/out -lbrotlienc -lbrotlicommon 連結,期待該目錄下已有
# 編好的靜態庫。少了這步,nginx 連結階段會出現 cannot find -lbrotlienc。
# 執行時的工作目錄是模組 clone 出來的根目錄。
set -euo pipefail

# 不加 -march=native:產物要能在所有同架構的機器上執行,
# 不能綁定 CI runner 的 CPU 特性。
mkdir -p deps/brotli/out
cd deps/brotli/out
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_C_FLAGS=-O2 .. >/dev/null
# brotlienc 會連帶把它依賴的 brotlicommon 一起編出來。
make -j"$(nproc)" brotlienc >/dev/null
