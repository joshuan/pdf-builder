#!/usr/bin/env python3
"""Exercise the actual JXA converter with disposable PDF fixtures on macOS."""
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def pdf(path, rotations=(0, 90), boxes=None):
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
               ('<< /Type /Pages /Kids [' + ' '.join(f'{3 + i * 2} 0 R' for i in range(len(rotations))) +
                f'] /Count {len(rotations)} >>').encode()]
    for i, rotation in enumerate(rotations):
        stream = b'1 0 0 rg 0 0 72 72 re f\n0 0 1 rg 144 216 72 72 re f'
        box = boxes[i] if boxes else '/MediaBox [0 0 216 288]'
        objects += [f'<< /Type /Page /Parent 2 0 R {box} /Rotate {rotation} /Resources << >> /Contents {len(objects) + 2} 0 R >>'.encode(),
                    f'<< /Length {len(stream)} >>\nstream\n'.encode() + stream + b'\nendstream']
    data = bytearray(b'%PDF-1.4\n')
    offsets = [0]
    for i, obj in enumerate(objects, 1):
        offsets.append(len(data))
        data.extend(f'{i} 0 obj\n'.encode() + obj + b'\nendobj\n')
    xref = len(data)
    data.extend(f'xref\n0 {len(objects) + 1}\n0000000000 65535 f \n'.encode())
    for offset in offsets[1:]:
        data.extend(f'{offset:010d} 00000 n \n'.encode())
    data.extend(f'trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
    path.write_bytes(data)


HARNESS = r'''
var originalRun = run;
run = function(argv) {
    var mode = argv.shift();
    var nativeFM = fm;
    fm = {};
    ['attributesOfItemAtPathError', 'createDirectoryAtURLWithIntermediateDirectoriesAttributesError',
     'removeItemAtURLError', 'moveItemAtURLToURLError'].forEach(function(name) {
        fm[name] = function() { return nativeFM[name].apply(nativeFM, arguments); };
    });
    fm.trashItemAtURLResultingItemURLError = function(source) {
        if (mode === 'trash-failure') return false;
        var parent = source.URLByDeletingLastPathComponent;
        var trash = parent.URLByAppendingPathComponent('test-trash');
        nativeFM.createDirectoryAtURLWithIntermediateDirectoriesAttributesError(trash, true, $(), Ref());
        // The test Trash operation must only happen after every JPG is present.
        var doc = $.PDFDocument.alloc.initWithURL(source);
        var base = ObjC.unwrap(source.URLByDeletingPathExtension.lastPathComponent);
        var anyCompleteSet = false;
        for (var suffix = 1; suffix < 5; suffix++) {
            var candidate = base + (suffix === 1 ? '' : ' (' + suffix + ')');
            var complete = true;
            for (var index = 0; index < Number(doc.pageCount); index++) {
                complete = complete && exists(parent.URLByAppendingPathComponent(pageName(candidate, index, Number(doc.pageCount))));
            }
            anyCompleteSet = anyCompleteSet || complete;
        }
        if (!anyCompleteSet) throw new Error('TEST: trash before publication');
        return nativeFM.moveItemAtURLToURLError(source, trash.URLByAppendingPathComponent(source.lastPathComponent), Ref());
    };
    if (mode === 'publish-failure') {
        var moves = 0;
        fm.moveItemAtURLToURLError = function(from, to, error) {
            if (++moves === 2) return false;
            return nativeFM.moveItemAtURLToURLError(from, to, error);
        };
    }
    if (mode === 'render-failure') {
        var render = renderPage;
        renderPage = function(doc, index, destination) {
            if (index === 1) throw new Error('TEST: render failure');
            return render(doc, index, destination);
        };
    }
    if (mode === 'source-change') {
        var render = renderPage;
        renderPage = function(doc, index, destination) {
            render(doc, index, destination);
            if (index === 1) $('modified PDF').writeToFileAtomicallyEncodingError(argv[0], true, $.NSUTF8StringEncoding, Ref());
        };
    }
    return originalRun(argv);
};
'''


def main():
    with tempfile.TemporaryDirectory(prefix='pdf-to-jpg-checks-') as temp:
        work = Path(temp)
        script = work / 'runner.js'
        script.write_text((ROOT / 'automator/pdf-to-jpg.js').read_text() + HARNESS)

        def run(mode, *inputs, success=True):
            result = subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript', str(script), mode, *map(str, inputs)],
                                    capture_output=True, text=True, timeout=60)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            assert result.returncode >= 0, f'Native crash: {result.returncode}'
            return result.stdout + result.stderr

        def fresh(name):
            folder = work / name
            folder.mkdir()
            return folder

        batch = fresh('batch')
        a = batch / 'Документ с пробелами.pdf'
        b = batch / "Кавычки '$()` и\nперенос.PDF"
        pdf(a)
        pdf(b, (180, 270))
        text = run('normal', a, b, a)
        assert 'Обработано PDF: 2. Сохранено JPG: 4.' in text, text
        assert not a.exists() and not b.exists()
        assert len(list(batch.glob('*.jpg'))) == 4
        info = subprocess.check_output(['/usr/bin/sips', '-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'dpiWidth',
                                        str(batch / 'Документ с пробелами-001.jpg'),
                                        str(batch / 'Документ с пробелами-002.jpg')], text=True)
        assert 'pixelWidth: 900' in info and 'pixelWidth: 1200' in info and info.count('dpiWidth: 300.000') == 2
        print('PASS: multiple PDFs, duplicate selection, Unicode/quotes/newlines, 4 rotations, 300 dpi')

        collision = fresh('collision')
        original = collision / 'input.pdf'
        pdf(original)
        (collision / 'input-002.jpg').write_bytes(b'existing image')
        run('normal', original)
        assert (collision / 'input-002.jpg').read_bytes() == b'existing image'
        assert (collision / 'input (2)-001.jpg').exists() and (collision / 'input (2)-002.jpg').exists()
        assert not (collision / 'input-001.jpg').exists()
        print('PASS: existing JPG preserved; consistent suffix for the full set')

        for mode in ['render-failure', 'publish-failure', 'trash-failure', 'source-change']:
            folder = fresh(mode)
            source = folder / 'input.pdf'
            pdf(source)
            run(mode, source, success=False)
            assert source.exists(), mode
            assert len(list(folder.glob('*.jpg'))) == (2 if mode == 'trash-failure' else 0), mode
            assert not list(folder.glob('.pdf-to-jpg-*')), mode
        print('PASS: render/publication/Trash errors and changed source preserve the PDF; rollback works')

        invalid = fresh('invalid')
        bad = invalid / 'broken.pdf'
        good = invalid / 'good.pdf'
        bad.write_text('not a PDF')
        pdf(good, (0,))
        run('normal', bad, good, success=False)
        assert bad.exists() and not good.exists() and (invalid / 'good-001.jpg').exists()
        folder = invalid / 'folder.pdf'
        folder.mkdir()
        symlink = invalid / 'link.pdf'
        symlink.symlink_to(bad)
        empty = invalid / 'empty.pdf'
        pdf(empty, ())
        run('normal', folder, symlink, empty, invalid / 'missing.pdf', success=False)
        assert all(p.exists() for p in [folder, symlink, empty])
        assert not list(invalid.glob('.pdf-to-jpg-*'))
        print('PASS: invalid/empty/missing PDFs and symlinks; valid files in mixed batches still finish')

        oversized = fresh('oversized')
        scan = oversized / 'scan.pdf'
        pdf(scan, (270,), ['/MediaBox [0 0 3264 2448]'])
        huge = oversized / 'huge.pdf'
        pdf(huge, (0,), ['/MediaBox [0 0 10000 10000]'])
        wide = oversized / 'wide.pdf'
        pdf(wide, (0,), ['/MediaBox [0 0 12000 2000]'])
        run('normal', scan, huge, wide)
        for name, ratio in [('scan', 2448 / 3264), ('huge', 1), ('wide', 6)]:
            result = subprocess.check_output(['/usr/bin/sips', '-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'dpiWidth',
                                               str(oversized / f'{name}-001.jpg')], text=True)
            values = dict(line.strip().split(': ', 1) for line in result.splitlines()[1:] if ': ' in line)
            width, height = int(values['pixelWidth']), int(values['pixelHeight'])
            assert width <= 6000 and height <= 6000 and width * height <= 24000000, result
            assert abs(width / height - ratio) < 0.01, result
            assert 0 < float(values['dpiWidth']) < 300, result
            assert not (oversized / f'{name}.pdf').exists()
        print('PASS: 72-dpi photo scans, giant pages and panoramas convert within bounds with correct rotation/ratio/dpi')

        readonly = fresh('readonly')
        source = readonly / 'input.pdf'
        pdf(source)
        readonly.chmod(0o555)
        try:
            run('normal', source, success=False)
            assert source.exists() and not list(readonly.glob('*.jpg'))
        finally:
            readonly.chmod(0o755)

        locked = invalid / 'locked.pdf'
        encrypt = work / 'encrypt.js'
        encrypt.write_text('''ObjC.import('Cocoa'); ObjC.import('PDFKit');
function run(args) {
    var doc = $.PDFDocument.alloc.initWithURL($.NSURL.fileURLWithPath(args[0]));
    var options = $.NSMutableDictionary.alloc.init;
    options.setObjectForKey('owner-secret', $.PDFDocumentOwnerPasswordOption);
    options.setObjectForKey('reader-secret', $.PDFDocumentUserPasswordOption);
    if (!doc.writeToURLWithOptions($.NSURL.fileURLWithPath(args[1]), options)) throw new Error('Cannot encrypt fixture');
}''')
        subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript', str(encrypt), str(source), str(locked)],
                       check=True, capture_output=True)
        message = run('normal', locked, success=False)
        assert 'защищён паролем' in message and locked.exists()
        print('PASS: read-only output directory and password-protected PDF preserve originals')

        with (ROOT / 'dist/PDF to JPG.workflow/Contents/document.wflow').open('rb') as f:
            workflow = plistlib.load(f)
        parameters = workflow['actions'][0]['action']['ActionParameters']
        assert parameters['inputMethod'] == 1
        assert workflow['workflowMetaData']['serviceInputTypeIdentifier'] == 'com.apple.Automator.fileSystemObject.PDF'
        assert (ROOT / 'automator/pdf-to-jpg.js').read_text() in parameters['COMMAND_STRING']
        shell = work / 'action.zsh'
        shell.write_text(parameters['COMMAND_STRING'])
        subprocess.run(['/bin/zsh', '-n', str(shell)], check=True)
        # Execute the exact embedded shell command with a real, invalid input so
        # the CLI argument transport is checked without touching system Trash.
        result = subprocess.run(['/bin/zsh', str(shell), str(bad)], capture_output=True, text=True)
        assert result.returncode != 0 and 'broken.pdf' in result.stderr and bad.exists()
        print('PASS: portable workflow embeds the current script and forwards Finder arguments')


if __name__ == '__main__':
    main()
