#!/usr/bin/env python3
"""Build a portable Automator Quick Action with its JXA script embedded."""
from pathlib import Path
import plistlib
import uuid

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'dist' / 'PDF to JPG.workflow' / 'Contents'
OUTPUT.mkdir(parents=True, exist_ok=True)
script = (ROOT / 'automator' / 'pdf-to-jpg.js').read_text()
command = "/usr/bin/osascript -l JavaScript - \"$@\" <<'PDF_TO_JPG_JXA'\n" + script + '\nPDF_TO_JPG_JXA\n'

def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'pdf-builder/pdf-to-jpg/' + name)).upper()

action = {
    'ActionBundlePath': '/System/Library/Automator/Run Shell Script.action',
    'ActionName': 'Run Shell Script',
    'ActionParameters': {
        'CheckedForUserDefaultShell': True, 'COMMAND_STRING': command,
        'inputMethod': 1, 'shell': '/bin/zsh', 'source': '',
    },
    'AMAccepts': {'Container': 'List', 'Optional': True, 'Types': ['com.apple.cocoa.string']},
    'AMProvides': {'Container': 'List', 'Types': ['com.apple.cocoa.string']},
    'AMActionVersion': '2.0.3', 'CFBundleVersion': '2.0.3',
    'AMParameterProperties': {name: {} for name in
        ['CheckedForUserDefaultShell', 'COMMAND_STRING', 'inputMethod', 'shell', 'source']},
    'BundleIdentifier': 'com.apple.RunShellScript', 'Class Name': 'RunShellScriptAction',
    'CanShowSelectedItemsWhenRun': False, 'CanShowWhenRun': True,
    'Category': ['AMCategoryUtilities'], 'Keywords': ['Shell', 'Script', 'Run'],
    'InputUUID': identifier('input'), 'OutputUUID': identifier('output'), 'UUID': identifier('action'),
    'isViewVisible': True, 'nibName': 'RunShellScriptAction',
    'UnlocalizedApplications': ['Automator'],
}
workflow = {
    'AMApplicationBuild': '521.1', 'AMApplicationVersion': '2.10', 'AMDocumentVersion': '2',
    'actions': [{'action': action, 'isViewVisible': True}], 'connectors': {},
    'workflowMetaData': {
        'workflowTypeIdentifier': 'com.apple.Automator.servicesMenu',
        'serviceInputTypeIdentifier': 'com.apple.Automator.fileSystemObject.PDF',
        'serviceOutputTypeIdentifier': 'com.apple.Automator.nothing',
        'serviceProcessesInput': False,
        'serviceApplicationBundleID': 'com.apple.finder', 'serviceApplicationPath': '/System/Library/CoreServices/Finder.app',
        'applicationBundleID': 'com.apple.finder',
        'applicationBundleIDsByPath': {'/System/Library/CoreServices/Finder.app': 'com.apple.finder'},
        'applicationPath': '/System/Library/CoreServices/Finder.app',
        'applicationPaths': ['/System/Library/CoreServices/Finder.app'],
        'inputTypeIdentifier': 'com.apple.Automator.fileSystemObject.PDF',
        'outputTypeIdentifier': 'com.apple.Automator.nothing',
        'processesInput': False, 'presentationMode': 15,
        'systemImageName': 'NSActionTemplate', 'useAutomaticInputType': False,
    },
}
info = {'NSServices': [{
    'NSMenuItem': {'default': 'PDF to JPG'},
    'NSMessage': 'runWorkflowAsService',
    'NSRequiredContext': {'NSApplicationIdentifier': 'com.apple.finder'},
    'NSSendFileTypes': ['com.adobe.pdf'],
}]}
for name, content in [('Info.plist', info), ('document.wflow', workflow)]:
    with (OUTPUT / name).open('wb') as output:
        plistlib.dump(content, output, sort_keys=False)
print(OUTPUT.parent)
