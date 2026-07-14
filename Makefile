.PHONY: build test app run install

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open "dist/Model Meter.app"

install:
	./scripts/install.sh
