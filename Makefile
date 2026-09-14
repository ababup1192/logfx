.PHONY: check test consume pkg release clean

# Flix コンパイラは flix_game_engine の devbox が持つ jar を借りる（bin/flix が解決する）。
check:
	bin/flix check

test:
	bin/flix test

# まっさらなプロジェクトから取り込んで動かす（CI と同じ物）。
consume:
	ci/consume.sh local

# 配布用の .fpkg を作る。
# WhyNot: test/ を詰めない。利用側で TestLogfx が走る意味が無く、モジュール名を 1 つ余計に取る。
PKG_DIR = build/logfx

pkg:
	rm -rf $(PKG_DIR)
	mkdir -p $(PKG_DIR)
	cp flix.toml $(PKG_DIR)/flix.toml
	cp -R src $(PKG_DIR)/src
	cd $(PKG_DIR) && $(CURDIR)/bin/flix build-pkg
	@ls -l $(PKG_DIR)/artifact/

# GitHub の release に .fpkg と flix.toml を付ける。
# 利用側は flix.toml の [dependencies] に "github:ababup1192/logfx" = "<version>" と書く。
# WhyNot: tag を手で決めない。Flix は tag v<version> の release から .fpkg を取るので、
# flix.toml の version とずれると解決に失敗する。
VERSION = $(shell sed -n 's/^version *= *"\(.*\)"/\1/p' flix.toml)

release: pkg
	gh release create v$(VERSION) \
		$(PKG_DIR)/artifact/logfx.fpkg $(PKG_DIR)/artifact/flix.toml \
		--title "v$(VERSION)" --notes "logfx $(VERSION)"

clean:
	rm -rf build
