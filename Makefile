SHELL := /bin/bash

PACKAGE_NAME := agent-runner
VERSION := $(shell tr -d '[:space:]' < VERSION)
DEB_FILE := dist/$(PACKAGE_NAME)_$(VERSION)_all.deb
RPM_FILE := dist/$(PACKAGE_NAME)-$(VERSION)-1.noarch.rpm

.PHONY: build-deb build-rpm install-deb install-rpm release clean

build-deb:
	./build-deb.sh

build-rpm:
	./build-rpm.sh

install-deb: build-deb
	sudo dpkg -i $(DEB_FILE)

install-rpm: build-rpm
	sudo rpm -Uvh $(RPM_FILE)
	
release:
	git add .
	git diff --cached --quiet && { echo "No changes to commit for release."; exit 1; } || true
	git commit -m "v$(VERSION)"
	git push origin HEAD
	git tag v$(VERSION)
	git push origin v$(VERSION)

clean:
	rm -rf build dist
