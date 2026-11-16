#!/usr/bin/env python3
"""Fail-closed release provenance. Read-only until the workflow's explicit publish step."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile

BASELINE = '18481af8008b27266af661b03bf16cf5b10e07a0'
REPOSITORY = 'shatianrui/tingye-ios'


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def project_version():
    project = Path('Tingye.xcodeproj/project.pbxproj').read_text()
    versions = set(re.findall(r'MARKETING_VERSION = ([^;]+);', project))
    builds = set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project))
    if len(versions) != 1 or len(builds) != 1:
        raise ValueError('Project configurations disagree about version/build')
    version, build = versions.pop(), builds.pop()
    if version == '1.25.0' or not build.isdigit() or int(build) <= 142:
        raise ValueError('Refusing old marketing version or reused build 142')
    return version, build


def remote_tag_commit(output, tag):
    refs = dict(line.split()[::-1] for line in output.splitlines() if line.strip())
    return refs.get(f'refs/tags/{tag}^{{}}', refs.get(f'refs/tags/{tag}'))


def verify_tag(tag, source):
    if not re.fullmatch(r'unsigned-[A-Za-z0-9][A-Za-z0-9._-]*', tag):
        raise ValueError('Invalid unsigned release tag')
    subprocess.run(['git', 'check-ref-format', 'refs/tags/' + tag], check=True)
    output = run('git', 'ls-remote', '--tags', 'origin', f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}')
    actual = remote_tag_commit(output, tag)
    if actual is not None and actual != source:
        raise ValueError(f'Remote tag {tag} targets {actual}, expected {source}')
    exists = subprocess.run(['git', 'show-ref', '--verify', '--quiet', f'refs/tags/{tag}']).returncode == 0
    local = run('git', 'rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}') if exists else None
    if local is not None and local != source:
        raise ValueError('Local tag differs from checked-out source')


def successful_test_run(runs, source):
    return next((r for r in runs if r.get('head_sha') == source
                 and r.get('status') == 'completed' and r.get('conclusion') == 'success'), None)


def verify_tests(source):
    result = json.loads(run('gh', 'api', f'repos/{REPOSITORY}/actions/workflows/tests.yml/runs?head_sha={source}&per_page=100'))
    passed = successful_test_run(result['workflow_runs'], source)
    if passed is None:
        raise ValueError('No successful Tests workflow exists for this exact source SHA')
    jobs = json.loads(run('gh', 'api', f'repos/{REPOSITORY}/actions/runs/{passed["id"]}/jobs?per_page=100'))['jobs']
    required = {'Unit tests (TingyeTests)', 'UI tests (TingyeUITests)'}
    successful = {j['name'] for j in jobs if j.get('conclusion') == 'success'}
    if not required.issubset(successful):
        raise ValueError('Required unit/UI jobs have not both passed; skipped jobs do not count')
    return passed['id']


def require_fresh_build(release_names, build):
    used = [int(n) for n in re.findall(r'\((\d+)\)', release_names)]
    if used and int(build) <= max(used):
        raise ValueError('Build number has already been used or is below the published maximum')


def verify_unused_build(build):
    names = run('gh', 'api', f'repos/{REPOSITORY}/releases', '--paginate', '--jq', '.[].name')
    require_fresh_build(names, build)


def validate_verified_build(releases, source, version, build, read_manifest):
    matching = [r for r in releases if re.search(r'\(' + re.escape(build) + r'\)', r.get('name', ''))]
    if not matching:
        raise ValueError('Verified stage requires the earlier untested release of this build')
    untested = False
    for release in matching:
        asset = next((a for a in release.get('assets', []) if a['name'] == 'Tingye-build-provenance.json'), None)
        if asset is None:
            raise ValueError('Existing build lacks provenance; refusing build reuse')
        manifest = read_manifest(asset)
        expected = dict(source_sha=source, version=version, build=build)
        if any(manifest.get(k) != v for k, v in expected.items()):
            raise ValueError('Build was issued for a different source/version; refusing reuse')
        if release.get('prerelease') and ('UNTESTED' in release.get('name', '') or '测试未完成' in release.get('name', '')):
            untested = True
    if not untested:
        raise ValueError('No matching untested prerelease exists')


def verify_stage_build(stage, source, version, build):
    if stage == 'untested':
        verify_unused_build(build)
        return
    raw = run('gh', 'api', f'repos/{REPOSITORY}/releases', '--paginate')
    decoder = json.JSONDecoder()
    releases = []
    while raw.strip():
        page, end = decoder.raw_decode(raw.lstrip())
        releases.extend(page)
        raw = raw.lstrip()[end:]
    def read_manifest(asset):
        return json.loads(run('gh', 'api', f'repos/{REPOSITORY}/releases/assets/{asset["id"]}', '-H', 'Accept: application/octet-stream'))
    validate_verified_build(releases, source, version, build, read_manifest)


def verify_ipa(path, source, version, build):
    with zipfile.ZipFile(path) as archive:
        plists = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', n)]
        if len(plists) != 1:
            raise ValueError('IPA must contain exactly one app Info.plist')
        info = plistlib.loads(archive.read(plists[0]))
    expected = {'CFBundleShortVersionString': version, 'CFBundleVersion': build, 'TingyeSourceCommit': source}
    if any(info.get(k) != v for k, v in expected.items()):
        raise ValueError('Packaged source/version/build does not match checkout')
    manifest = json.loads(Path(path).with_name('Tingye-build-provenance.json').read_text())
    if any(manifest.get(k) != v for k, v in {'source_sha': source, 'version': version, 'build': build}.items()):
        raise ValueError('Artifact provenance sidecar differs from checkout')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-sha', required=True)
    parser.add_argument('--require-tests', action='store_true')
    parser.add_argument('--release-stage', choices=['untested', 'verified'])
    parser.add_argument('--tag')
    parser.add_argument('--ipa')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.expected_sha):
        raise ValueError('A full expected 40-character commit SHA is required')
    source = run('git', 'rev-parse', 'HEAD')
    if source != args.expected_sha:
        raise ValueError('Checked-out HEAD differs from explicitly expected source SHA')
    event_sha = os.environ.get('GITHUB_SHA')
    if event_sha and run('git', 'rev-parse', event_sha + '^{commit}') != source:
        raise ValueError('Workflow event SHA differs from checkout')
    if os.environ.get('GITHUB_REPOSITORY', REPOSITORY) != REPOSITORY:
        raise ValueError('Wrong repository')
    subprocess.run(['git', 'merge-base', '--is-ancestor', BASELINE, source], check=True)
    try:
        subprocess.run(['git', 'diff', '--exit-code', '--quiet'], check=True)
        subprocess.run(['git', 'diff', '--cached', '--exit-code', '--quiet'], check=True)
    except subprocess.CalledProcessError:
        # Name the offending paths before failing so the build log shows
        # exactly what dirtied the worktree (e.g. a file-mode change).
        status = subprocess.run(['git', 'status', '--porcelain'],
                                capture_output=True, text=True)
        print('error: worktree is not clean; changed paths:\n' + status.stdout,
              file=sys.stderr)
        raise
    version, build = project_version()
    if args.tag:
        verify_tag(args.tag, source)
    tests = verify_tests(source) if args.require_tests else None
    if args.release_stage == 'verified' and not args.require_tests:
        raise ValueError('Verified stage must require actual same-source unit and UI success')
    if args.release_stage:
        verify_stage_build(args.release_stage, source, version, build)
    if args.ipa:
        verify_ipa(args.ipa, source, version, build)
    print(json.dumps({'source_sha': source, 'version': version, 'build': build, 'tests_run_id': tests}))


if __name__ == '__main__':
    main()
