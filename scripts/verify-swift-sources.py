#!/usr/bin/env python3
"""Verify disk Swift files through target → Sources → BuildFile → FileReference.

Read-only, uses no git or third-party packages. Resolves PBXGroup paths instead of
accepting a filename mentioned in a comment or an unused PBXBuildFile entry.
"""
from collections import Counter
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def parse_project(text):
    tokens = iter(re.findall(
        r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text, re.S))
    tokens = iter(t for t in tokens if not t.startswith(('/*', '//')))

    def scalar(token):
        return json.loads(token) if token.startswith('"') else token

    def value(token):
        if token == '{':
            result = {}
            while (key := next(tokens)) != '}':
                assert next(tokens) == '='
                result[scalar(key)] = value(next(tokens))
                assert next(tokens) == ';'
            return result
        if token == '(':
            result = []
            while (item := next(tokens)) != ')':
                result.append(value(item))
                assert next(tokens) == ','
            return result
        return scalar(token)

    return value(next(tokens))


def verify():
    project = parse_project((ROOT / 'Tingye.xcodeproj/project.pbxproj').read_text())
    objects = project['objects']
    file_paths = {}

    def visit(identifier, parent):
        obj = objects[identifier]
        tree = obj.get('sourceTree', '<group>')
        if tree not in ('<group>', 'SOURCE_ROOT'):
            return
        base = ROOT if tree == 'SOURCE_ROOT' else parent
        path = base / obj.get('path', '')
        if obj['isa'] == 'PBXGroup':
            for child in obj['children']:
                visit(child, path)
        elif obj['isa'] == 'PBXFileReference':
            file_paths[identifier] = path.resolve()

    visit(objects[project['rootObject']]['mainGroup'], ROOT)
    counts = {}
    memberships = {}
    for obj in objects.values():
        if obj['isa'] != 'PBXNativeTarget':
            continue
        target = obj['name']
        members = []
        for phase_id in obj['buildPhases']:
            phase = objects[phase_id]
            if phase['isa'] != 'PBXSourcesBuildPhase':
                continue
            for build_id in phase['files']:
                build_file = objects[build_id]
                assert build_file['isa'] == 'PBXBuildFile', build_id
                path = file_paths[build_file['fileRef']]
                if path.suffix == '.swift':
                    assert path.is_file(), f'Missing source: {path}'
                    members.append(path)
        assert all(n == 1 for n in Counter(members).values()), f'Duplicate source in {target}'
        counts[target] = len(members)
        for path in members:
            memberships.setdefault(path, set()).add(target)

    disk_files = sorted(p.resolve() for p in ROOT.rglob('*.swift') if '.git' not in p.parts)
    target_files = []
    standalone = []
    for path in disk_files:
        relative = path.relative_to(ROOT)
        expected = relative.parts[0]
        if expected == 'Design':
            assert path not in memberships, f'Design tooling compiled into app: {relative}'
            standalone.append(relative)
            continue
        assert expected in counts, f'No owning target rule: {relative}'
        target_files.append(path)
        assert memberships.get(path) == {expected}, (
            f'{relative}: expected {expected}, actual {memberships.get(path, set())}')
        print(f'PASS {expected}: {relative}')
    assert set(memberships) == set(target_files), 'Disk/Sources mismatch'
    print(f'PASS {len(target_files)} target Swift files; ' + ', '.join(f'{k}={v}' for k, v in sorted(counts.items())))
    for path in standalone:
        print(f'TOOL (no Xcode target): {path}')
    print(f'INFO {len(standalone)} standalone Design tools excluded from app/test Sources')


if __name__ == '__main__':
    verify()
