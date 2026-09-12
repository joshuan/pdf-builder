# PDF Builder

PDF Builder is a small native macOS utility for turning selected images and PDFs into one PDF with a single confirmation.

## Features

- Natural filename ordering, so `page2` comes before `page10`.
- Page thumbnails with drag-and-drop reordering, arrow controls, and removal.
- Exact A4 pages or an automatic size that follows each source aspect ratio.
- Thumbnails reflect the selected output page size, orientation, and whitespace.
- Automatic A4 selection when at least 80% of the sources are close to the A4 ratio.
- Per-page portrait or landscape A4 orientation.
- PNG, JPEG, HEIC, TIFF, and other image formats supported by macOS.
- Existing PDFs expand into individual pages.
- Finder **Open With**, Finder Services, file picker, and drag-and-drop entry points.
- An editable output file name, defaulting to the first page name, saved in the same folder as that page.
- Source files move to the system Trash only after the PDF has been rendered successfully; an enabled-by-default checkbox lets you keep them instead.
- Completion arrives as a macOS notification rather than another confirmation dialog.
- Automatic update checks backed by GitHub Releases.

## Build

PDF Builder requires macOS 13 or later and the Xcode Command Line Tools.

```sh
make test
make build
```

`make test` runs the core and Finder open-event checks without Xcode or an external test framework. The release application is written to `dist/PDF Builder.app`.

Create the distributable archive with a specific version and build number:

```sh
make package VERSION=1.2.3 BUILD=42
```

This produces `dist/PDFBuilder.zip`, the asset expected by the updater.

## Install a local build

```sh
make install
```

The local development installer uses `~/Applications` by default. Override it when needed:

```sh
PDF_BUILDER_INSTALL_DIR=/Applications make install
```

## Installing

```sh
curl -fsSL https://raw.githubusercontent.com/joshuan/pdf-builder/main/install.sh | sh
```

This downloads the latest [release](https://github.com/joshuan/pdf-builder/releases), puts `PDF Builder.app` in `/Applications` when possible, and registers it with Finder so **Open With** and the Services entry work immediately. If `/Applications` is not writable, the script uses `~/Applications` instead. To install a specific release, pass its tag to the shell running the installer:

```sh
curl -fsSL https://raw.githubusercontent.com/joshuan/pdf-builder/main/install.sh | PDF_BUILDER_VERSION=v1.2.3 sh
```

## Finder workflow

Select several files in Finder and use either:

1. **Open With → PDF Builder**.
2. **Services / Quick Actions → Build PDF…**.

If the service is hidden, enable it in **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders**.

Finder opens all selected files in one PDF Builder window, even when macOS delivers them as separate open events. Opening more files adds them to the current list without replacing the pages already there; repeated files are ignored.

Check the page order and format in the window, then press Return. The result appears next to the first page. After a successful write, a macOS notification reports completion and the application quits automatically. If saving fails, the window stays open and shows the error.

Drag a page to a new position in the list, or use its arrow buttons. The **File name** field follows the first page until you edit it; a custom name stays unchanged when you reorder pages. Use the reset button beside the field to return to the first page name. The field edits only the base name; the `.pdf` extension is fixed and shown beside it.

The **Удалить исходники** (Delete source files) checkbox above the file name is enabled by default. Clear it to keep all source files in place. When keeping a source PDF whose name matches the output, choose a different output name; the app blocks saving over a source that should be kept.

## Page sizing

- **A4** uses exact A4 dimensions. Each page independently chooses portrait or landscape orientation, and the source is fitted without cropping.
- **Auto** gives each page the source aspect ratio and normalizes its long edge to the long edge of A4. This avoids enormous PDF page dimensions caused by image DPI metadata.

## Source-file safety

The PDF is first rendered completely into a temporary file beside its destination. Only after that succeeds are the source files moved to the Trash, if source deletion is enabled. An existing output PDF moves to the Trash before replacement. When source deletion is disabled, an output that would replace a source is rejected. If final placement fails, PDF Builder attempts to restore everything it already moved.

## Updates

PDF Builder checks the latest GitHub Release silently at launch, at most once every 24 hours. Nothing is shown when the installed version is current or when an automatic check fails. When a newer release exists, a notification offers **Install** and **Later**. The application menu also contains **Check for Updates…** for an immediate check that always reports its result.

Installing an update downloads `PDFBuilder.zip`, verifies its bundle identifier, version, and code signature, stages it on the same volume, atomically replaces the running copy, and relaunches it. A failure leaves the installed copy untouched and points to the release page as a fallback.

## Publishing a release

Publish a GitHub Release from a version tag such as `v1.2.3`. The release workflow runs the checks, stamps the bundle version, builds and signs the application, and attaches `PDFBuilder.zip` to the release.

When the repository contains `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`, `AC_API_KEY_P8`, `AC_API_KEY_ID`, and `AC_API_ISSUER_ID`, the workflow signs with Developer ID and notarizes the application. Without those secrets it publishes an ad-hoc signed build that remains installable through `install.sh`.
