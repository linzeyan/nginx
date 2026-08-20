# nginx / OpenResty 安裝包工廠

自動建置 nginx 與 OpenResty 的 `.deb` / `.rpm` / `.tar.gz` 安裝包,
透過 GitHub Actions 定時偵測上游新版並發佈到 GitHub Releases。
Docker 映像檔(root / rootless 兩種變體)供本地建置使用。

- 在 AlmaLinux 8 容器內編譯(glibc 2.28 基線),每個架構一顆 binary,
  可跑在 **RHEL 8+、Debian 11+、Ubuntu 20.04+**。
- OpenSSL / PCRE2 / zlib / libmaxminddb **靜態連結** —— 套件幾乎零外部
  依賴;OpenSSL 安全更新透過重發套件出貨。
- 支援架構:`amd64` 與 `arm64`(原生 runner 編譯,不走 QEMU)。

## 產品線與套件名

三條產品線各自獨立 pin 版本、獨立發 release:

| 產品線(`<product>`) | 家族(`<family>`) | 上游來源 | 套件名 | release tag |
| --- | --- | --- | --- | --- |
| `nginx-stable` | `nginx` | nginx.org,minor 為偶數的最高版 | `nginx` | `nginx-stable-<ver>-<rel>` |
| `nginx-mainline` | `nginx` | nginx.org,最高版 | `nginx` | `nginx-mainline-<ver>-<rel>` |
| `openresty` | `openresty` | openresty.org/download 最高版 | `openresty` | `openresty-<ver>-<rel>` |

`<product>` 決定 config 目錄、build 目錄、release tag 與 workflow;
`<family>`(寫在 `build.env` 的 `FAMILY`)決定共用的 build script、
nfpm 設定、`packaging/`、`docker/` 資產,同時也是 deb/rpm 的套件名。

兩條 nginx 產品線出的套件都叫 `nginx`,和 nginx.org 官方 repo 的做法一致
(同名、分 repo),只靠版本號區分。好處是切換產品線就是一次普通升級,
不必先移除再安裝;代價是**同一台機器只能裝其中一條線**。

## 內含模組

三條產品線的模組清單刻意對齊,讓同一份 `nginx.conf` 到哪邊都通用。

| 模組 | 形式 | 說明 |
| --- | --- | --- |
| brotli | 靜態 | `brotli on;`、`brotli_static on;` |
| headers-more | 靜態 | `more_set_headers` / `more_clear_headers`(OpenResty 已內建) |
| njs | 靜態 | nginx JavaScript。刻意關閉 libxslt/zlib/QuickJS 選配功能,避免主 binary 產生外部依賴 |
| geoip2 | 靜態 | libmaxminddb 一併靜態連結,不需要 EPEL |
| xslt、image_filter | **dynamic** | 需自行 `load_module`,且系統要有 libxslt / libgd |

`--with-http_perl_module` **不納入**:它會連結建置容器的
`libperl.so.5.26`,而各發行版的 perl soname 都不同,同一顆 `.so`
不可能跨發行版通用。需要腳本能力請改用 njs 或 OpenResty 的 Lua。

dynamic module 的載入方式(放進 `main.d/`,因為 `load_module` 必須在
main context 生效):

```sh
echo 'load_module modules/ngx_http_xslt_filter_module.so;' \
  > /etc/nginx/main.d/xslt.conf
apt-get install -y libxslt1.1   # 或 dnf install libxslt
```

## 要改什麼,動哪裡

| 想做的事 | 修改位置 | 改完執行 |
| --- | --- | --- |
| 增減 nginx 模組 | `config/<product>/modules.conf` | `make bump-release-<product>` |
| 調整 configure 參數 | `config/<product>/configure-args.conf` | `make bump-release-<product>` |
| 升級 OpenSSL/PCRE2/zlib/libmaxminddb | `config/<product>/build.env` | `make bump-release-<product>` |
| 純粹想重新發一次(同一上游版本) | — | `make bump-release-<product>` |
| 預設 nginx.conf、systemd 單元、logrotate、安裝腳本 | `packaging/<family>/` | 兩條 nginx 線都要 `make bump-release-<product>` |
| 套件 metadata(依賴、描述、檔案佈局) | `nfpm/<family>.yaml` | 同上 |
| Docker 映像檔變體 | `docker/<family>/Dockerfile.root`、`Dockerfile.rootless` | 不需要,映像檔不進 release |
| OpenResty 的 OpenSSL patch | `config/openresty/openssl-patches/` | `make bump-release-openresty` |

改完連同 `build.env` 一起 push 到 `main`,對應的建置 workflow 就會跑完
並發出新的 release。動到 `packaging/nginx/` 或 `nfpm/nginx.yaml` 會同時
觸發 `nginx-stable` 與 `nginx-mainline` 兩條線,兩邊的 `PKG_RELEASE`
都要記得推。

`modules.conf` 的行格式是 `<name> <git-url> <git-ref> [subdir]`,
`<git-ref>` 可以是 tag、branch 或 commit SHA;`[subdir]` 用在模組的
`config` 檔不在 repo 根目錄時(例如 njs 要指到 `nginx/`)。

有些模組在 `--add-module` 之前需要先編好自己的依賴。這種情況在
`scripts/module-prep/<name>.sh` 放一支腳本,取得原始碼後會在該模組目錄
內自動執行。目前只有 `brotli` 需要:ngx_brotli 直接以
`-L deps/brotli/out -lbrotlienc -lbrotlicommon` 連結,那些靜態庫得先用
CMake 編出來。

## 版本與套件版次:VERSION 與 PKG_RELEASE

`config/<product>/build.env` 裡有兩個版本欄位,發佈的 tag 與檔名都是
`<VERSION>-<PKG_RELEASE>` 這個組合:

| 欄位 | 意義 | 誰來改 |
| --- | --- | --- |
| `VERSION` | 上游的 nginx / OpenResty 版本 | 每日 `check-versions` workflow 自動改;抓到新版時會把 `PKG_RELEASE` 一併設為當天日期 |
| `PKG_RELEASE` | 這次打包的日期,`YYYYMMDD`(UTC) | 你手動改,用 `make bump-release-<product>` |

需要推 `PKG_RELEASE` 的原因,是 release tag(`nginx-stable-1.30.4-20260820`)
必須唯一 —— `scripts/release.sh` 偵測到 tag 已存在會直接失敗而不覆蓋。
所以上游版本沒變、但建置內容變了(加了模組、改了 configure 參數、
升了 OpenSSL)時,就靠這個欄位區分新舊套件,套件管理員也才認得這是
一次可升級的更新。

用日期而不是流水號,是為了讓「這顆套件是什麼時候建的」直接寫在檔名上 ——
靜態連結 OpenSSL 的情況下,這是判斷手上的套件有沒有含某個 CVE 修補最快的
依據。日期在 rpm 與 deb 的版本比較規則下都是遞增的,升級路徑不受影響。

```sh
make bump-release-nginx-stable   # PKG_RELEASE -> 20260820,VERSION 不動
```

同一天要再發一次就會接上流水號(`20260820` → `20260820.2` → `20260820.3`),
rpm 與 deb 一樣把它們排在當天第一次之後。

日期值寫進 `build.env` 而不是打包時現算:`amd64` 與 `arm64` 是兩台 runner
並行建置,現算會在跨午夜時給出不同日期,release 步驟就湊不齊同一組檔案。

## 設定檔佈局

主設定檔會 include 三個目錄,職責分開:

| 目錄 | 用途 |
| --- | --- |
| `main.d/` | 需要在 main context 生效的設定,主要是 `load_module` |
| `conf.d/` | http context 的共用設定,套件附一個 `default.conf` |
| `sites-enabled/` | 各站台的 vhost |

nginx 位於 `/etc/nginx/`,OpenResty 位於
`/usr/local/openresty/nginx/conf/`。兩份主設定檔內容一致(只有路徑與
執行身分不同),存取日誌預設輸出 JSON 格式。

## 本地使用

需要 docker 與 bash;`make release-*` 另需已認證的 `gh`。

```sh
make nginx-stable        # 編譯 + 打包 + 煙霧測試(當前架構)
make nginx-mainline
make openresty
make image-nginx-stable  # 建 root/rootless 映像檔(從 GitHub Releases 抓 .deb)
make check-versions
make bump-versions
make clean
```

產物輸出到 `dist/`,檔名帶的是**套件名**而非產品線:
`<family>_<ver>-<rel>_<arch>.deb`、`<family>-<ver>-<rel>.<arch>.rpm`、
`<family>-<ver>-<rel>-linux-<arch>.tar.gz`(FHS 佈局,解壓到 `/`)。
兩條 nginx 線的產物靠 `<ver>` 區分,`make all` 之後會同時留在 `dist/` 裡。

## CI workflows

| Workflow | 觸發 | 內容 |
| --- | --- | --- |
| `check-versions` | 每日 cron / 手動 | 比對三條產品線 pin 的版本與上游;有新版就 commit bump 並 dispatch 對應的建置 workflow |
| `build-nginx-stable` | push 到監看路徑 / 手動 | 建置矩陣(amd64 + arm64)→ 煙霧測試 → GitHub release `nginx-stable-<ver>-<rel>`,附 `SHA256SUMS` |
| `build-nginx-mainline` | 同上 | 同上,tag 為 `nginx-mainline-<ver>-<rel>` |
| `build-openresty` | 同上 | 同上,tag 為 `openresty-<ver>-<rel>` |

上游版本一律從發行方的下載目錄解析(`nginx.org/download/`、
`openresty.org/download/`),不走 GitHub 的 releases API —— OpenResty
從 1.29 起只打 git tag、不再發 GitHub Release,`releases/latest` 會停在
1.27.1.2 而永遠偵測不到新版。

煙霧測試會把套件安裝進乾淨的 `ubuntu:24.04`、`debian:12`、
`rockylinux:9`、`almalinux:8` 容器,驗證 `-V`、`-t` 與實際 HTTP 回應;
測試失敗就不會發 release。

release 步驟不覆蓋既有 tag:同一 `VERSION` 重發必須 bump `PKG_RELEASE`。

## Docker 映像檔(僅本地建置,CI 不建置)

每個家族兩個獨立 Dockerfile,基底都是 `debian:12-slim`,`.deb` 由
Dockerfile 直接從 GitHub Releases 下載(`ARG REPO`,預設
`linzeyan/nginx`),因此**該版本必須已經發佈**:

| Dockerfile | 執行身分 | 監聽埠 |
| --- | --- | --- |
| `docker/<family>/Dockerfile.root` | root(master) | 80 |
| `docker/<family>/Dockerfile.rootless` | 服務使用者 | 8080 |

映像檔名用的是產品線,兩條 nginx 線因此各有自己的 `latest`:

```sh
# 產生 nginx-stable:<ver>-<rel>、nginx-stable:latest 與對應的 -rootless
make image-nginx-stable
make image-nginx-mainline
```

## 已知限制

- 靜態連結 OpenSSL 代表 CVE 修補只能靠這條 pipeline 出貨;版本監看
  只涵蓋 nginx/OpenResty,OpenSSL 升級需手動改 `build.env`。
- rpm 有一個外部依賴 `libcrypt.so.1()(64bit)`,來自 auth_basic 的
  `crypt_r()`;宣告 soname 而非套件名,是因為 EL8 由 `libxcrypt` 提供、
  EL9 拆到預設不安裝的 `libxcrypt-compat`。deb 端由 essential 套件提供。
- xslt 與 image_filter 以 dynamic module 出貨,套件不宣告 libxslt/libgd
  依賴;沒安裝就 `load_module` 會在啟動時明確報找不到 shared object。
- 預設 `nginx.conf` 不設 `ssl_dhparam`,因此 DHE 系列 cipher 不可用
  (只保留 ECDHE)。要用 DHE 需自行產生 dhparam.pem 並補設定。
- OpenResty 的 HTTP/3 已確認**可以編譯進去**,但 OpenResty 上游並未
  官方支援 HTTP/3,Lua 與 HTTP/3 的組合未經上游測試。
- OpenResty 少數進階 SSL Lua API 需要 OpenResty 官方 patch,見
  `config/openresty/openssl-patches/README.md`。
- configure 參數逐行取字面值,不解析 shell quoting。
