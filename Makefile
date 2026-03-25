SHELL := /bin/bash

PACKAGE_NAME := agent-runner
VERSION := $(shell tr -d '[:space:]' < VERSION)
DEB_FILE := dist/$(PACKAGE_NAME)_$(VERSION)_all.deb

.PHONY: build install release clean

build:
	./build-deb.sh

install: build
	sudo dpkg -i $(DEB_FILE)

release: build
	git add .
	git diff --cached --quiet && { echo "No changes to commit for release."; exit 1; } || true
	git commit -m "v$(VERSION)"
	git push origin HEAD
	git tag v$(VERSION)
	git push origin v$(VERSION)

clean:
	rm -rf build dist
