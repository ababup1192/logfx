.PHONY: check check-jargon test consume examples doc pkg release clean

# The Flix compiler jar is borrowed from a devbox profile; bin/flix resolves it.
check:
	bin/flix check

test:
	bin/flix test

# Watch the Japanese prose for words the denylist has a replacement for.
check-jargon:
	scripts/check-jargon.sh

# Pull it into a blank project and run it (the same thing CI does).
consume:
	ci/consume.sh local

# Build and run examples/ against the .fpkg built from the current source.
examples:
	ci/example.sh

# Build the published reference (flix doc) into build/doc/.
# On a tag, .github/workflows/pages.yml runs the same script and puts it on GitHub Pages.
doc:
	ci/doc.sh

# Build the distributable .fpkg.
# WhyNot: test/ is not packed in. Running TestLogfx on the calling side means nothing, and it
# would take one more module name from them.
PKG_DIR = build/logfx

pkg:
	rm -rf $(PKG_DIR)
	mkdir -p $(PKG_DIR)
	cp flix.toml $(PKG_DIR)/flix.toml
	cp -R src $(PKG_DIR)/src
	cd $(PKG_DIR) && $(CURDIR)/bin/flix build-pkg
	@ls -l $(PKG_DIR)/artifact/

# Attach the .fpkg and flix.toml to a GitHub release.
# The calling side writes "github:ababup1192/logfx" = "<version>" under [dependencies].
# WhyNot: the tag is not chosen by hand. Flix takes the .fpkg from the release tagged v<version>,
# so a tag that drifts from the version in flix.toml makes resolution fail.
VERSION = $(shell sed -n 's/^version *= *"\(.*\)"/\1/p' flix.toml)

# WhyNot: the notes are not just the version string. The README tells the reader that a 0.x minor
# may break them and to read the release notes; one line saying "logfx 0.3.0" empties that promise.
NOTES = docs/release-notes/v$(VERSION).md

release: pkg
	@test -f $(NOTES) || { echo "$(NOTES) is missing. Write what changed in this version before releasing."; exit 1; }
	gh release create v$(VERSION) \
		$(PKG_DIR)/artifact/logfx.fpkg $(PKG_DIR)/artifact/flix.toml \
		--title "v$(VERSION)" --notes-file $(NOTES)

clean:
	rm -rf build
