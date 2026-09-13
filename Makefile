VERSION ?= 1.0.0
BUILD ?= 1
SIGN_IDENTITY ?= -
CODESIGN_FLAGS ?= --options runtime

export VERSION BUILD SIGN_IDENTITY CODESIGN_FLAGS

.PHONY: build test install package clean pdf-to-jpg install-pdf-to-jpg test-pdf-to-jpg pdf-builder-action install-pdf-builder-action

build:
	./scripts/build-app.sh

test:
	./scripts/test.sh

install: build
	./scripts/install.sh

package: build pdf-to-jpg pdf-builder-action
	rm -f dist/PDFBuilder.zip dist/PDFBuilder.workflow.zip dist/PDFtoJPG.workflow.zip
	ditto -c -k --keepParent "dist/PDF Builder.app" dist/PDFBuilder.zip
	ditto -c -k --keepParent "dist/PDF Builder.workflow" dist/PDFBuilder.workflow.zip
	ditto -c -k --keepParent "dist/PDF to JPG.workflow" dist/PDFtoJPG.workflow.zip
	@echo "Packaged app and Finder Quick Actions ($(VERSION), build $(BUILD))"

pdf-to-jpg:
	python3 scripts/build-pdf-to-jpg-workflow.py

install-pdf-to-jpg: pdf-to-jpg
	bash scripts/install-pdf-to-jpg.sh

test-pdf-to-jpg: pdf-to-jpg
	python3 scripts/test-pdf-to-jpg.py

pdf-builder-action:
	python3 scripts/pdf-builder-quick-action.py

install-pdf-builder-action:
	python3 scripts/pdf-builder-quick-action.py --install

clean:
	swift package clean
	rm -rf dist
