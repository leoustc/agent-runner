SHELL := /bin/bash

PACKAGE_NAME := agent-runner
VERSION := $(shell tr -d '[:space:]' < VERSION)
DEB_FILE := dist/$(PACKAGE_NAME)_$(VERSION)_all.deb

.PHONY: build install clean

build:
	./build-deb.sh

install: build
	sudo dpkg -i $(DEB_FILE)

clean:
	rm -rf build dist
