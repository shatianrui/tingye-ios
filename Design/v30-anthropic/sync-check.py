#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""听页 · v30 令牌同步校验。

仓库 v29 定下的纪律是「事实来源冻结」：代码与 JSON 任一改动，另一处同提交更新。
本脚本把这条纪律变成可执行检查：

  Tingye/Theme.swift            ↔  Design/v30-anthropic/colors_and_type.css
  ↔  Design/v30-anthropic/SWIFT-TOKENS.md
  ↔  Design/v30-anthropic/DESIGN.md

用法：python3 Design/v30-anthropic/sync-check.py
退出码 0 = 全部一致；1 = 存在漂移。
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))

THEME = os.path.join(ROOT, 'Tingye', 'Theme.swift')
CSS = os.path.join(HERE, 'colors_and_type.css')
TOKENS_MD = os.path.join(HERE, 'SWIFT-TOKENS.md')
DESIGN_MD = os.path.join(HERE, 'DESIGN.md')

# Swift 令牌 → CSS 变量
MAP = [
    ('bg',          '--ty-canvas'),
    ('surface',     '--ty-surface'),
    ('surface2',    '--ty-surface-subtle'),
    ('surfaceSunken', '--ty-surface-sunken'),
    ('ink',         '--ty-ink'),
    ('ink2',        '--ty-ink-2'),
    ('ink3',        '--ty-ink-3'),
    ('ink4',        '--ty-ink-4'),
    ('line',        '--ty-line'),
    ('clay',        '--ty-clay'),
    ('clayEmph',    '--ty-clay-emph'),
    ('accent',      '--ty-clay-text'),
    ('claySoft',    '--ty-clay-soft'),
    ('onClay',      '--ty-on-clay'),
    ('danger',      '--ty-danger'),
    ('focus',       '--ty-focus'),
]

# CSS 变量 → (Swift 名, 中文名)
CSS_TO_SWIFT = {
    '--ty-canvas': 'Theme.bg',
    '--ty-surface': 'Theme.surface',
    '--ty-surface-subtle': 'Theme.surface2',
    '--ty-surface-sunken': 'Theme.surfaceSunken',
    '--ty-ink': 'Theme.ink',
    '--ty-ink-2': 'Theme.ink2',
    '--ty-ink-3': 'Theme.ink3',
    '--ty-ink-4': 'Theme.ink4',
    '--ty-line': 'Theme.line',
    '--ty-clay': 'Theme.clay',
    '--ty-clay-emph': 'Theme.clayEmph',
    '--ty-clay-text': 'Theme.accent',
    '--ty-clay-soft': 'Theme.claySoft',
    '--ty-on-clay': 'Theme.onClay',
    '--ty-danger': 'Theme.danger',
    '--ty-focus': 'Theme.focus',
}


def parse_swift(path):
    """取 Theme.swift 中 dynamic(0xLIGHT, 0xDARK) 形式的两色令牌。"""
    src = open(path, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'static\s+let\s+([A-Za-z_]\w*)\s*=\s*dynamic\(\s*0x([0-9A-Fa-f]{6})\s*,\s*0x([0-9A-Fa-f]{6})\s*\)', src):
        name, light, dark = m.group(1), m.group(2).upper(), m.group(3).upper()
        out[name] = ('#' + light, '#' + dark)
    return out


def parse_css(path):
    """取 CSS 中 :root 与 .dark 两段的十六进制变量。"""
    src = open(path, encoding='utf-8').read()
    root = src.split(':root {')[1].split('\n}')[0]
    dark = src.split('.dark {')[1].split('\n}')[0]
    out = {}
    for scope, block in (('light', root), ('dark', dark)):
        for m in re.finditer(r'(--ty-[a-z0-9-]+)\s*:\s*(#[0-9A-Fa-f]{6})\s*;', block):
            out.setdefault(m.group(1), {})[scope] = m.group(2).upper()
    return out


def main():
    swift = parse_swift(THEME)
    css = parse_css(CSS)
    tokens_md = open(TOKENS_MD, encoding='utf-8').read()
    design_md = open(DESIGN_MD, encoding='utf-8').read()

    drift = []
    print('=== Swift ↔ CSS 令牌一致性 ===')
    for swift_name, css_var in MAP:
        if swift_name not in swift:
            drift.append(f'Swift 缺令牌 Theme.{swift_name}')
            print(f'  [FAIL] Theme.{swift_name:16s} 未定义')
            continue
        if css_var not in css:
            drift.append(f'CSS 缺变量 {css_var}')
            print(f'  [FAIL] {css_var:22s} 未定义')
            continue
        s_light, s_dark = swift[swift_name]
        c_light, c_dark = css[css_var]['light'], css[css_var]['dark']
        ok = (s_light == c_light) and (s_dark == c_dark)
        if not ok:
            drift.append(f'{swift_name} ↔ {css_var}: Swift {s_light}/{s_dark} vs CSS {c_light}/{c_dark}')
        mark = 'PASS' if ok else 'FAIL'
        print(f'  [{mark}] {swift_name:16s} ↔ {css_var:22s} {s_light}/{s_dark}  vs  {c_light}/{c_dark}')

    print('\n=== SWIFT-TOKENS.md 收录完整性 ===')
    for css_var, swift_ref in CSS_TO_SWIFT.items():
        if swift_ref not in tokens_md:
            drift.append(f'SWIFT-TOKENS.md 未收录 {swift_ref}')
            print(f'  [FAIL] 未收录 {swift_ref}')
        elif css_var not in tokens_md:
            drift.append(f'SWIFT-TOKENS.md 未收录 {css_var}')
            print(f'  [FAIL] 未收录 {css_var}')
        else:
            print(f'  [PASS] {swift_ref:24s} ↔ {css_var}')

    print('\n=== DESIGN.md 与实现取值一致 ===')
    for css_var, swift_ref in CSS_TO_SWIFT.items():
        if css_var not in css:
            continue
        vals = set(css[css_var].values())
        for v in vals:
            if v not in design_md:
                drift.append(f'DESIGN.md 未出现 {v}（{css_var}）')
                print(f'  [FAIL] DESIGN.md 未出现 {v}（{css_var}）')
            else:
                print(f'  [PASS] {v} 已记录')

    print()
    if drift:
        print(f'❌ 发现 {len(drift)} 处漂移：')
        for d in drift:
            print('   -', d)
        return 1
    print('✅ 三处令牌完全一致，无漂移。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
