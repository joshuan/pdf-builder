.PHONY: build test install clean

build:
	./scripts/build-app.sh

test:
	./scripts/test.sh

install: build
	./scripts/install.sh

clean:
	swift package clean
	rm -rf "dist/PDF Builder.app"
