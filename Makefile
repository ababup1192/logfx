.PHONY: check test consume examples doc pkg release clean

# Flix コンパイラは flix_game_engine の devbox が持つ jar を借りる（bin/flix が解決する）。
check:
	bin/flix check

test:
	bin/flix test

# まっさらなプロジェクトから取り込んで動かす（CI と同じ物）。
consume:
	ci/consume.sh local

# examples/ を、今のソースから作った .fpkg に対してビルドして走らせる。
examples:
	ci/example.sh

# 公開するリファレンス（flix doc）を build/doc/ に作る。
# tag を打つと .github/workflows/pages.yml が同じ script を走らせて GitHub Pages に置く。
doc:
	ci/doc.sh

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

# WhyNot: notes を版の文字列だけにしない。README は「0.x の minor は壊す事があるので
# release note を読め」と書いている。読む物が「logfx 0.3.0」の 1 行だと、その約束が空になる。
NOTES = docs/release-notes/v$(VERSION).md

release: pkg
	@test -f $(NOTES) || { echo "$(NOTES) が無い。この版で何が変わったかを書いてから release する"; exit 1; }
	gh release create v$(VERSION) \
		$(PKG_DIR)/artifact/logfx.fpkg $(PKG_DIR)/artifact/flix.toml \
		--title "v$(VERSION)" --notes-file $(NOTES)

clean:
	rm -rf build
