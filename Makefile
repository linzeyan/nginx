# 建置、打包、測試與發佈 nginx/OpenResty 安裝包。
# 編譯一律在 BUILD_IMAGE 容器內進行(glibc 2.28 基線),同一顆 binary
# 可跑在 RHEL 8+、Debian 11+、Ubuntu 20.04+。

BUILD_IMAGE ?= almalinux:8

.PHONY: all nginx-stable nginx-mainline openresty check-versions bump-versions clean

all: nginx-stable nginx-mainline openresty

# 每條產品線的完整本地流程:編譯 -> deb/rpm/tar.gz -> 乾淨發行版容器內
# 安裝煙霧測試。
nginx-stable: build-nginx-stable package-nginx-stable test-nginx-stable
nginx-mainline: build-nginx-mainline package-nginx-mainline test-nginx-mainline
openresty: build-openresty package-openresty test-openresty

# build script 掛在 FAMILY 底下(nginx 的 stable 與 mainline 共用同一支),
# 所以要先讀 build.env 才知道跑哪支;產品線名稱以參數傳進去。
build-%:
	. config/$*/build.env; \
	docker run --rm -v $(CURDIR):/work -w /work $(BUILD_IMAGE) \
		bash scripts/build-$$FAMILY.sh $*

package-%:
	bash scripts/package.sh $*

test-%:
	bash scripts/smoke-test.sh $*

# 建置 root/rootless 映像檔(僅本地使用,CI 不建置映像檔)。
# .deb 由 Dockerfile 直接從 GitHub Releases 下載,因此該版本必須已發佈;
# 若要用本地尚未發佈的套件,請改跑 make test-$* 驗證。
image-%:
	. config/$*/build.env; \
	docker build -f docker/$$FAMILY/Dockerfile.root docker/$$FAMILY \
		--build-arg PRODUCT=$* \
		--build-arg VERSION=$$VERSION --build-arg PKG_RELEASE=$$PKG_RELEASE \
		-t $*:$$VERSION-$$PKG_RELEASE -t $*:latest; \
	docker build -f docker/$$FAMILY/Dockerfile.rootless docker/$$FAMILY \
		--build-arg PRODUCT=$* \
		--build-arg VERSION=$$VERSION --build-arg PKG_RELEASE=$$PKG_RELEASE \
		-t $*:$$VERSION-$$PKG_RELEASE-rootless -t $*:rootless

# CI 使用;需要已認證的 gh 與 dist/ 內的 artifacts。
release-%:
	bash scripts/release.sh $*

check-versions:
	bash scripts/check-versions.sh

# 把 config/*/build.env 改寫成上游最新版本。
bump-versions:
	bash scripts/check-versions.sh --update

# 上游版本沒變、但建置內容變了(模組/configure 參數/依賴版本)時,
# 用這個把套件版次推到當天日期,否則 release tag 會撞名而發不出去。
bump-release-%:
	bash scripts/bump-release.sh $*

clean:
	rm -rf build dist
