SHELL := /bin/bash

.PHONY: build dev start test check lint format docs-list package dmg install release appcast

build:
	swift build

dev start:
	./Scripts/compile_and_run.sh

test:
	swift test

check: format lint test

lint:
	./Scripts/lint.sh lint

format:
	./Scripts/lint.sh format

docs-list:
	node Scripts/docs-list.mjs

package:
	./Scripts/package_app.sh release

dmg: package
	./Scripts/build_dmg.sh

install:
	./Scripts/install_local.sh

release:
	./Scripts/sign-and-notarize.sh

appcast:
	./Scripts/make_appcast.sh $(ARTIFACT)
