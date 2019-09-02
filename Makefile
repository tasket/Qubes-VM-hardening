VERSION := $(shell cat version)

install: install-vm

install-vm:
	bash ./install
	bash ./configure-sudo-prompt --force
