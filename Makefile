.PHONY: build test app run install smoke check

build:
	swift build

test:
	swift test

app:
	scripts/bundle.sh

run: app
	pkill -x shotX || true
	open build/shotX.app

install: app
	mkdir -p ~/Applications
	rm -rf ~/Applications/shotX.app
	cp -R build/shotX.app ~/Applications/

smoke:
	scripts/smoke.sh

# Warnings are errors via Package.swift (treatAllWarnings), so build == zero-warning build.
check: build test
	@find Sources -name '*.swift' -exec wc -l {} + | awk '$$2 != "total" && $$1 > 400 { print "too long (>400 lines): " $$2 " (" $$1 ")"; bad = 1 } END { exit bad }'
	@echo "check OK"
