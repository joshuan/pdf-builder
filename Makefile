VERSION ?= 1.0.0
BUILD ?= 1
SIGN_IDENTITY ?= -
CODESIGN_FLAGS ?= --options runtime

export VERSION BUILD SIGN_IDENTITY CODESIGN_FLAGS

.PHONY: build test install package clean

build:
	./scripts/build-app.sh

test:
	./scripts/test.sh

install: build
	./scripts/install.sh

package: build
	rm -f dist/PDFBuilder.zip
	ditto -c -k --keepParent "dist/PDF Builder.app" dist/PDFBuilder.zip
	@echo "Packaged dist/PDFBuilder.zip ($(VERSION), build $(BUILD))"

clean:
	swift package clean
	rm -rf dist
