// JavaScript for Automation (JXA), using only frameworks included with macOS.
// Run: /usr/bin/osascript -l JavaScript automator/pdf-to-jpg.js file.pdf ...
ObjC.import('Cocoa');
ObjC.import('PDFKit');

var DPI = 300;
var JPEG_QUALITY = 0.95;
var MAX_PAGE_PIXELS = 24000000;
var MAX_PAGE_EDGE = 6000;
var fm = $.NSFileManager.defaultManager;

function present(value) {
    return value !== undefined && value !== null && ObjC.unwrap(value) !== undefined;
}

function failure(message) {
    // Do not dereference NSError out-pointers: some macOS JXA versions release
    // these before the bridge can read them. Every call supplies its own context.
    return new Error(message);
}

function attributes(url) {
    var error = Ref();
    var result = fm.attributesOfItemAtPathError(url.path, error);
    if (!present(result)) throw failure('Не удалось прочитать файл', error);
    return result;
}

function sourceStamp(attrs) {
    return Number(attrs.objectForKey('NSFileModificationDate').timeIntervalSince1970) + '|' +
        ['NSFileSize', 'NSFileCreationDate',
        'NSFileSystemNumber', 'NSFileSystemFileNumber', 'NSFileType'].map(function (key) {
        return ObjC.unwrap(attrs.objectForKey(key).description);
    }).join('|');
}

function pageName(base, index, count) {
    var digits = Math.max(3, String(count).length);
    return base + '-' + ('0000000000' + (index + 1)).slice(-digits) + '.jpg';
}

function renderPage(document, index, destination) {
    var page = document.pageAtIndex(index);
    if (!present(page)) throw new Error('Не удалось прочитать страницу ' + (index + 1));
    var bounds = page.boundsForBox($.kPDFDisplayBoxCropBox);
    var width = bounds.size.width;
    var height = bounds.size.height;
    if (page.rotation % 180 !== 0) {
        var swap = width;
        width = height;
        height = swap;
    }
    if (!isFinite(width) || !isFinite(height) || width <= 0 || height <= 0) {
        throw new Error('Неверный размер страницы ' + (index + 1));
    }
    // Image-to-PDF tools may write pixel dimensions as PDF points (72 dpi).
    // Fit oversized pages into a bounded bitmap instead of rejecting valid scans
    // or allocating hundreds of megapixels. Keep the whole page and its ratio.
    var scale = Math.min(DPI / 72, MAX_PAGE_EDGE / width, MAX_PAGE_EDGE / height,
        Math.sqrt(MAX_PAGE_PIXELS) / Math.sqrt(width) / Math.sqrt(height));
    var effectiveDPI = scale * 72;
    width = Math.max(1, Math.floor(width * scale));
    height = Math.max(1, Math.floor(height * scale));

    // PDFKit preserves page rotation, crop bounds, annotations and a white background.
    // This renders at the requested pixel size; it does not use a cached preview.
    var image = page.thumbnailOfSizeForBox($.NSMakeSize(width, height), $.kPDFDisplayBoxCropBox);
    if (!present(image)) throw new Error('Не удалось отрисовать страницу ' + (index + 1));
    var bitmap = $.NSBitmapImageRep.imageRepWithData(image.TIFFRepresentation);
    if (!present(bitmap) || bitmap.pixelsWide < 1 || bitmap.pixelsHigh < 1) {
        throw new Error('Не удалось получить изображение страницы ' + (index + 1));
    }
    bitmap.size = $.NSMakeSize(bitmap.pixelsWide * 72 / effectiveDPI, bitmap.pixelsHigh * 72 / effectiveDPI);
    var jpeg = bitmap.representationUsingTypeProperties(
        $.NSBitmapImageFileTypeJPEG, $({NSImageCompressionFactor: JPEG_QUALITY}));
    if (!present(jpeg) || jpeg.length === 0) {
        throw new Error('Не удалось создать JPG страницы ' + (index + 1));
    }
    var error = Ref();
    if (!jpeg.writeToURLOptionsError(destination, $.NSDataWritingAtomic, error)) {
        throw failure('Не удалось сохранить страницу ' + (index + 1), error);
    }
    // Reopen the file from disk before allowing the source to be trashed.
    var check = $.NSBitmapImageRep.imageRepWithContentsOfURL(destination);
    if (!present(check) || check.pixelsWide !== bitmap.pixelsWide ||
        check.pixelsHigh !== bitmap.pixelsHigh || !present(check.CGImage)) {
        throw new Error('Проверка сохранённой страницы ' + (index + 1) + ' не пройдена');
    }
}

function exists(url) {
    // Unlike fileExistsAtPath, lstat-style attributes also detect dangling symlinks.
    return present(fm.attributesOfItemAtPathError(url.path, Ref()));
}

function publishPages(staging, parent, base, count) {
    for (var suffix = 1; suffix < 10000; suffix++) {
        var outputBase = base + (suffix === 1 ? '' : ' (' + suffix + ')');
        var targets = [];
        for (var index = 0; index < count; index++) {
            targets.push(parent.URLByAppendingPathComponent(pageName(outputBase, index, count)));
        }
        if (targets.some(exists)) continue;
        var moved = 0;
        try {
            for (; moved < count; moved++) {
                var page = staging.URLByAppendingPathComponent(pageName(base, moved, count));
                // Native move refuses to overwrite, even if a name was taken
                // after the availability check above.
                if (!fm.moveItemAtURLToURLError(page, targets[moved], Ref())) {
                    throw new Error('Не удалось разместить JPG рядом с PDF; исходник сохранён');
                }
            }
            return targets;
        } catch (error) {
            for (var previous = moved - 1; previous >= 0; previous--) {
                var original = staging.URLByAppendingPathComponent(pageName(base, previous, count));
                if (!fm.moveItemAtURLToURLError(targets[previous], original, Ref())) {
                    error.keepStaging = true;
                }
            }
            if (error.keepStaging) {
                error.message += '. Часть JPG осталась рядом с PDF; временные страницы: ' + ObjC.unwrap(staging.path);
            }
            throw error;
        }
    }
    throw new Error('Не удалось подобрать свободные имена JPG');
}

function convertPDF(source) {
    var before = attributes(source);
    if (ObjC.unwrap(before.objectForKey('NSFileType')) !== ObjC.unwrap($.NSFileTypeRegular)) {
        throw new Error('Выберите обычный PDF-файл, а не папку или символическую ссылку');
    }
    var stamp = sourceStamp(before);
    var data = $.NSData.dataWithContentsOfURL(source);
    if (!present(data)) throw new Error('Не удалось прочитать PDF');
    var document = $.PDFDocument.alloc.initWithData(data);
    if (!present(document)) throw new Error('Файл не является читаемым PDF');
    if (document.isLocked) throw new Error('PDF защищён паролем; исходник сохранён');
    var count = Number(document.pageCount);
    if (count < 1) throw new Error('PDF не содержит страниц');
    var parent = source.URLByDeletingLastPathComponent;
    var base = ObjC.unwrap(source.URLByDeletingPathExtension.lastPathComponent);
    var staging = parent.URLByAppendingPathComponent('.pdf-to-jpg-' + ObjC.unwrap($.NSUUID.UUID.UUIDString));
    var error = Ref();
    if (!fm.createDirectoryAtURLWithIntermediateDirectoriesAttributesError(staging, false, $(), error)) {
        throw failure('Не удалось создать временную папку рядом с PDF', error);
    }
    var keepStaging = false;
    try {
        for (var index = 0; index < count; index++) {
            renderPage(document, index, staging.URLByAppendingPathComponent(pageName(base, index, count)));
        }
        if (sourceStamp(attributes(source)) !== stamp) {
            throw new Error('PDF изменился во время конвертации; исходник сохранён');
        }
        publishPages(staging, parent, base, count);
        if (sourceStamp(attributes(source)) !== stamp) {
            throw new Error('PDF изменился во время конвертации; JPG готовы, исходник сохранён');
        }
        error = Ref();
        if (!fm.trashItemAtURLResultingItemURLError(source, Ref(), error)) {
            throw failure('JPG готовы рядом с PDF, но исходник не удалось переместить в корзину', error);
        }
        return count;
    } catch (error) {
        keepStaging = error.keepStaging === true;
        throw error;
    } finally {
        // Only our temporary output is disposable. Published JPGs stay
        // in place if Trash is unavailable. Never delete the original with removeItem.
        if (!keepStaging) fm.removeItemAtURLError(staging, Ref());
    }
}

function run(argv) {
    if (!argv.length) throw new Error('Выделите один или несколько PDF-файлов в Finder');
    var seen = Object.create(null);
    var errors = [];
    var files = 0;
    var pages = 0;
    for (var index = 0; index < argv.length; index++) {
        var source = $.NSURL.fileURLWithPath(String(argv[index])).URLByStandardizingPath;
        var path = ObjC.unwrap(source.path);
        if (seen[path]) continue;
        seen[path] = true;
        try {
            if (ObjC.unwrap(source.pathExtension).toLowerCase() !== 'pdf') {
                throw new Error('Выберите PDF-файл');
            }
            pages += convertPDF(source);
            files++;
        } catch (error) {
            errors.push(ObjC.unwrap(source.lastPathComponent) + ': ' + error.message);
        }
    }
    var summary = 'Обработано PDF: ' + files + '. Сохранено JPG: ' + pages + '.';
    if (errors.length) throw new Error(summary + '\n\n' + errors.join('\n'));
    try {
        var app = Application.currentApplication();
        app.includeStandardAdditions = true;
        app.displayNotification(summary + ' Исходники в корзине.', {withTitle: 'PDF → JPG'});
    } catch (_) {
        // Notification permissions do not affect successful conversion.
    }
    return summary;
}
