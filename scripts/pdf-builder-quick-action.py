#!/usr/bin/env python3
"""Build/install the Finder action that opens selected files in PDF Builder."""
from pathlib import Path
import argparse
import os
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
NAME = 'PDF Builder.workflow'
OUTPUT = ROOT / 'dist' / NAME

# Prefer the installed application over development builds with the same bundle
# identifier. The fallback also supports an application moved to another folder.
COMMAND = '''if (( $# == 0 )); then
    exit 0
fi
if [[ -d "/Applications/PDF Builder.app" ]]; then
    /usr/bin/open -a "/Applications/PDF Builder.app" -- "$@"
elif [[ -d "$HOME/Applications/PDF Builder.app" ]]; then
    /usr/bin/open -a "$HOME/Applications/PDF Builder.app" -- "$@"
else
    /usr/bin/open -b com.joshuan.pdf-builder -- "$@"
fi
'''


def identifier(part):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'pdf-builder/finder-launcher/' + part)).upper()


def build():
    parameters = {'CheckedForUserDefaultShell': True, 'COMMAND_STRING': COMMAND,
                  'inputMethod': 1, 'shell': '/bin/zsh', 'source': ''}
    action = {
        'ActionBundlePath': '/System/Library/Automator/Run Shell Script.action',
        'ActionName': 'Run Shell Script', 'ActionParameters': parameters,
        'AMAccepts': {'Container': 'List', 'Optional': True, 'Types': ['com.apple.cocoa.string']},
        'AMProvides': {'Container': 'List', 'Types': ['com.apple.cocoa.string']},
        'AMActionVersion': '2.0.3', 'CFBundleVersion': '2.0.3',
        'AMParameterProperties': {key: {} for key in parameters},
        'BundleIdentifier': 'com.apple.RunShellScript', 'Class Name': 'RunShellScriptAction',
        'CanShowSelectedItemsWhenRun': False, 'CanShowWhenRun': True,
        'Category': ['AMCategoryUtilities'], 'Keywords': ['Shell', 'Script', 'Run'],
        'InputUUID': identifier('input'), 'OutputUUID': identifier('output'), 'UUID': identifier('action'),
        'isViewVisible': True, 'nibName': 'RunShellScriptAction', 'UnlocalizedApplications': ['Automator'],
    }
    metadata = {
        'workflowTypeIdentifier': 'com.apple.Automator.servicesMenu',
        'serviceInputTypeIdentifier': 'com.apple.Automator.fileSystemObject',
        'serviceOutputTypeIdentifier': 'com.apple.Automator.nothing', 'serviceProcessesInput': False,
        'serviceApplicationBundleID': 'com.apple.finder',
        'serviceApplicationPath': '/System/Library/CoreServices/Finder.app',
        'applicationBundleID': 'com.apple.finder',
        'applicationBundleIDsByPath': {'/System/Library/CoreServices/Finder.app': 'com.apple.finder'},
        'applicationPath': '/System/Library/CoreServices/Finder.app',
        'applicationPaths': ['/System/Library/CoreServices/Finder.app'],
        'inputTypeIdentifier': 'com.apple.Automator.fileSystemObject',
        'outputTypeIdentifier': 'com.apple.Automator.nothing', 'processesInput': False,
        'presentationMode': 15, 'systemImageName': 'NSActionTemplate', 'useAutomaticInputType': False,
    }
    workflow = {
        'AMApplicationBuild': '521.1', 'AMApplicationVersion': '2.10', 'AMDocumentVersion': '2',
        'actions': [{'action': action, 'isViewVisible': True}], 'connectors': {}, 'workflowMetaData': metadata,
    }
    info = {'NSServices': [{
        'NSMenuItem': {'default': 'PDF Builder'}, 'NSMessage': 'runWorkflowAsService',
        'NSRequiredContext': {'NSApplicationIdentifier': 'com.apple.finder'},
        'NSSendFileTypes': ['public.image', 'com.adobe.pdf'],
    }]}
    contents = OUTPUT / 'Contents'
    contents.mkdir(parents=True, exist_ok=True)
    for name, value in [('Info.plist', info), ('document.wflow', workflow)]:
        with (contents / name).open('wb') as file:
            plistlib.dump(value, file, sort_keys=False)
    print(f'Built: {OUTPUT}')


def install():
    services = Path.home() / 'Library' / 'Services'
    services.mkdir(parents=True, exist_ok=True)
    destination = services / NAME
    with tempfile.TemporaryDirectory(prefix='.pdf-builder-install-', dir=services) as temporary:
        staging = Path(temporary) / NAME
        shutil.copytree(OUTPUT, staging)
        backup = None
        if os.path.lexists(destination):
            backup = services / ('.pdf-builder-backup-' + str(uuid.uuid4()))
            destination.rename(backup)
        try:
            staging.rename(destination)
        except OSError:
            if backup:
                backup.rename(destination)
            raise
        if backup:
            print(f'Previous version: {backup}')
    subprocess.run(['/System/Library/CoreServices/pbs', '-update'], check=True)
    print(f'Installed: {destination}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true')
    options = parser.parse_args()
    build()
    if options.install:
        install()
