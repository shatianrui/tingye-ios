#!/usr/bin/env python3
"""Source/target invariants for the Readium redesign. This is NOT an iOS test or compiler."""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

BASELINE = '18481af8008b27266af661b03bf16cf5b10e07a0'
ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def old(path):
    return git('show', f'{BASELINE}:{path}')


def source_phases(data):
    return {m[1]: set(re.findall(r'\b[A-F0-9]{24}\b', m[2])) for m in re.finditer(
        r'([A-F0-9]{24})(?: /\* Sources \*/)? = \{\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);', data, re.S)}


def verify():
    subprocess.run(['git', '-C', str(ROOT), 'merge-base', '--is-ancestor', BASELINE, 'HEAD'], check=True)
    readium = git('ls-tree', '-r', '--name-only', BASELINE, 'Tingye/Readium').decode().splitlines()
    assert len(readium) == 17
    assert set(readium) == {str(p.relative_to(ROOT)) for p in (ROOT / 'Tingye/Readium').glob('*.swift')}
    protected = [p for p in readium if p != 'Tingye/Readium/ReadiumReaderView.swift']
    protected += ['Tingye/Models.swift', 'Tingye/Services.swift', 'Tingye/OriginalBookView.swift',
                  'Tingye/SpeechPlayer.swift', 'Tingye/DialogueRoles.swift', 'Tingye/Library.swift']
    # Library.swift intentionally changes only the AppLockGate UI. Business APIs remain byte-identical.
    protected.remove('Tingye/Library.swift')
    for path in protected:
        assert (ROOT / path).read_bytes() == old(path), f'Protected engine/data source changed: {path}'
    for path in ['Tingye/Library.swift', 'Tingye/StorageView.swift', 'Tingye/FocusSession.swift']:
        marker = {'Tingye/Library.swift': 'struct AppLockGate', 'Tingye/StorageView.swift': 'enum StorageUsage',
                  'Tingye/FocusSession.swift': 'struct FocusStartView'}[path]
        previous, current = old(path).decode(), (ROOT / path).read_text()
        if path.endswith('StorageView.swift'):
            assert current[current.index(marker):] == previous[previous.index(marker):]
        else:
            assert current[:current.index(marker)] == previous[:previous.index(marker)]
    previous_theme = old('Tingye/Theme.swift').decode()
    current_theme = (ROOT / 'Tingye/Theme.swift').read_text()
    def reader_preferences(text):
        return text[text.index('enum ReaderPaper'):text.index('extension String {', text.index('enum ReaderPaper'))]
    assert reader_preferences(previous_theme) == reader_preferences(current_theme), 'Book palettes/defaults/font mapping changed'
    # Native rendering/page algorithms are preserved, despite redesign of the tool surfaces.
    previous_reader = old('Tingye/ReaderView.swift').decode()
    current_reader = (ROOT / 'Tingye/ReaderView.swift').read_text()
    for begin, end in [('    private var textContent:', '    private var topBar:'),
                       ('struct NativeTextPage:', 'struct ContentsView:')]:
        assert previous_reader[previous_reader.index(begin):previous_reader.index(end)] == current_reader[current_reader.index(begin):current_reader.index(end)], begin
    project = (ROOT / 'Tingye.xcodeproj/project.pbxproj').read_text()
    baseline_project = old('Tingye.xcodeproj/project.pbxproj').decode()
    assert project.replace('CURRENT_PROJECT_VERSION = 143;', 'CURRENT_PROJECT_VERSION = 142;').replace('MARKETING_VERSION = 1.26.0;', 'MARKETING_VERSION = 1.25.0;') == baseline_project, 'Unexpected project mutation beyond version/build'
    assert source_phases(project) == source_phases(baseline_project), 'Target source membership changed'
    assert len(source_phases(project)) == 3
    lock = 'Tingye.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    assert (ROOT / lock).read_bytes() == old(lock), 'Resolved dependencies changed'
    assert len(json.loads((ROOT / lock).read_text())['pins']) == 16
    for product in ['ReadiumShared', 'ReadiumStreamer', 'ReadiumNavigator', 'ReadiumZIPFoundation', 'SwiftSoup', 'SMBClient', 'Pow']:
        assert project.count('productName = ' + product + ';') == baseline_project.count('productName = ' + product + ';'), product
    counts = {'unit_preserved': 0, 'unit_new': 0, 'ui_preserved': 0, 'ui_new': 0}
    tests = git('ls-tree', '-r', '--name-only', BASELINE, 'TingyeTests', 'TingyeUITests').decode().splitlines()
    for path in [p for p in tests if p.endswith('.swift')]:
        before, after = old(path), (ROOT / path).read_bytes()
        assert after.startswith(before), f'Existing test file body edited instead of append-only: {path}'
        methods = lambda data: set(re.findall(rb'\bfunc (test\w+)\s*\(', data))
        assert methods(before).issubset(methods(after))
        prefix = 'ui' if path.startswith('TingyeUITests') else 'unit'
        counts[prefix + '_preserved'] += len(methods(before))
        counts[prefix + '_new'] += len(methods(after) - methods(before))
    assert counts == {'unit_preserved': 174, 'unit_new': 8, 'ui_preserved': 28, 'ui_new': 2}, counts
    for path in [p for p in tests if not p.endswith('.swift')]:
        assert (ROOT / path).read_bytes() == old(path), f'Test fixture changed: {path}'
    scheme = ET.parse(ROOT / 'Tingye.xcodeproj/xcshareddata/xcschemes/Tingye.xcscheme')
    testables = scheme.findall('.//TestableReference')
    assert len(testables) == 2 and all(t.attrib['skipped'] == 'NO' for t in testables)
    assert (ROOT / '.github/workflows/tests.yml').read_bytes() == old('.github/workflows/tests.yml')
    assert set(re.findall(r'MARKETING_VERSION = ([^;]+);', project)) == {'1.26.0'}
    assert set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project)) == {'143'}
    generator = (ROOT / 'create-project.rb').read_text()
    assert "'CURRENT_PROJECT_VERSION' => '143'" in generator and "'MARKETING_VERSION' => '1.26.0'" in generator
    info = plistlib.loads((ROOT / 'Tingye/Info.plist').read_bytes())
    assert info['CFBundleShortVersionString'] == '$(MARKETING_VERSION)' and info['CFBundleVersion'] == '$(CURRENT_PROJECT_VERSION)'
    assert (ROOT / 'Tingye/Info.plist').read_bytes() == old('Tingye/Info.plist')
    shelf = (ROOT / 'Tingye/ShelfView.swift').read_text()
    results = shelf[shelf.index('struct ImportResultsView'):shelf.index('struct ExportedBook')]
    assert 'fileImporter' not in results and 'LocalBookPicker(' not in results and 'bookImporter(' not in results
    assert 'asCopy: true' in shelf and 'multiple = false' in shelf
    assert 'documentPickerWasCancelled' in shelf and 'guard !completed' in shelf
    app = (ROOT / 'Tingye/TingyeApp.swift').read_text()
    assert app.count('LocalBookPicker(multiple: request.multiple)') == 1
    model = (ROOT / 'Tingye/AppModel.swift').read_text()
    assert model.count('try await BookImporter.readCoordinated(url)') == 2
    assert model.count('let secured = url.startAccessingSecurityScopedResource(); defer { if secured { url.stopAccessingSecurityScopedResource() } }') == 2
    workflow = (ROOT / '.github/workflows/build-unsigned-ipa.yml').read_text()
    assert '--target "$SOURCE_SHA"' in workflow and '--require-tests' in workflow and '--clobber' not in workflow
    assert 'expected_sha:' in workflow and 'Tingye-build-provenance.json' in workflow
    assert not (ROOT / 'Design/v30-anthropic').exists()
    return {'baseline': BASELINE, 'readium_source_files': 17, 'unchanged_engine_data_files': len(protected),
            'target_source_phases': 3, 'dependency_pins': 16, **counts,
            'status': 'source invariants passed; iOS compilation/runtime/visual NOT verified'}


if __name__ == '__main__':
    print(json.dumps(verify(), indent=2))
