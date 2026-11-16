#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""听页 · v30 Swift 侧静态验收。

本仓库环境没有 Xcode / Swift 工具链，代码无法编译，因此用静态检查尽量逼近
「能编译、能编译后表现正确」：

  1. 括号配平：去字符串与注释后检查 {} () [] 是否平衡（每个文件）
  2. 令牌完整性：所有跨文件引用的 Theme.xxx 必须在 Theme.swift 里有定义
  3. 公共 API 表面：Theme.swift 导出的令牌与组件是否齐全（对照 v29 基线）
  4. 风格纪律：页面里是否残留写死的圆角 / 阴影 / 按压缩放
  5. 硬编码颜色：Tingye/ 下是否残留写死的 hex（应全部走令牌）

用法：python3 Design/v30-anthropic/verify-swift.py
退出码 0 = 通过；1 = 有阻断项。
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SWIFT_DIR = os.path.join(ROOT, 'Tingye')
THEME = os.path.join(SWIFT_DIR, 'Theme.swift')
BASELINE = os.path.join(os.path.dirname(ROOT), 'baseline')   # 可选：v29 基线副本

# v29 基线里 Theme.swift 公开的令牌名（用于 API 表面回归检查）
BASELINE_TOKENS = {
    'bg', 'surface', 'surface2', 'ink', 'ink2', 'ink3', 'line', 'rulePaint', 'onInk',
    'cardEdge', 'accent', 'accentSoft', 'onAccent', 'clay', 'onClay', 'link', 'marker',
    'onMarker', 'readingHighlight', 'hero', 'heroInk', 'forest', 'onForest', 'wash',
    'danger', 'warm', 'onWarm', 'gold', 'goldSoft', 'jade', 'jadeSoft', 'indigo',
    'indigoSoft', 'ochre', 'plum', 'amberOnDark', 'auroraGradient', 'accentGradient',
    'heroGradient', 'heroButtonInk', 'inset', 'pageWidth', 'radius', 'heroRadius',
    'radiusSmall', 'buttonRadius', 'buttonRadiusSmall', 'buttonHeight', 'iconButtonSize',
    'ruleHeavy', 'ruleMedium', 'rule', 'pressSpring', 'smoothSpring', 'serifName',
    'masthead', 'kicker', 'coverUIColor', 'coverForeground',
}

BASELINE_FUNCS = {
    'serif', 'serifSemibold', 'serifBold', 'sans', 'display', 'headline',
    'coverColor', 'coverGradient',
}

BASELINE_VIEW_EXT = {
    'scaledFont', 'respectReducedMotion', 'glassSurface', 'glassCard', 'columnRule',
    'softCardShadow', 'floatingPanel', 'serifEmbolden', 'serifHeavy', 'paperBackground',
    'markerHighlight',
}


def strip_swift(src: str) -> str:
    """去注释与字符串字面量。

    必须处理 Swift 原始字符串（井号包裹的引号字符串，含多行变体）：
    里面的引号不是字符串终止符，否则括号计数会全部错位。
    """
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        # 原始字符串：#" ... "#（可多井号，可多行）
        if c == '#':
            j = i
            while j < n and src[j] == '#':
                j += 1
            hashes = j - i
            if j < n and src[j] == '"':
                if src[j:j + 3] == '"""':
                    close = '"""' + '#' * hashes
                    end = src.find(close, j + 3)
                    i = (end + len(close)) if end != -1 else n
                else:
                    close = '"' + '#' * hashes
                    end = src.find(close, j + 1)
                    i = (end + len(close)) if end != -1 else n
                out.append('""')
                continue
            out.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
        elif c == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                i += 1
            i += 2
        elif c == '"':
            if src[i:i + 3] == '"""':
                i += 3
                while i + 2 < n and src[i:i + 3] != '"""':
                    i += 1
                i += 3
            else:
                i += 1
                while i < n:
                    if src[i] == '\\':
                        i += 2
                        continue
                    if src[i] == '"':
                        i += 1
                        break
                    i += 1
            out.append('""')
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def bracket_check(src: str):
    pairs = {'}': '{', ')': '(', ']': '['}
    stack, line, bad = [], 1, []
    for ch in src:
        if ch == '\n':
            line += 1
        elif ch in '{([':
            stack.append((ch, line))
        elif ch in '})]':
            if not stack or stack[-1][0] != pairs[ch]:
                bad.append((line, ch))
            else:
                stack.pop()
    return stack, bad


def main():
    blocking = []
    warnings = []
    files = sorted(glob.glob(os.path.join(SWIFT_DIR, '*.swift')))

    # ── 1. 括号配平 ──
    print('=== 1. 括号配平 ===')
    for f in files:
        src = open(f, encoding='utf-8').read()
        stack, bad = bracket_check(strip_swift(src))
        name = os.path.basename(f)
        if stack or bad:
            blocking.append(f'{name}: 括号不平衡（未闭合 {stack[:3]}，错配 {bad[:3]}）')
            print(f'  [FAIL] {name}')
        else:
            print(f'  [PASS] {name}')
    print(f'  —— {len(files)} 个文件')

    # ── 2. 令牌完整性 ──
    print('\n=== 2. Theme 令牌引用完整性 ===')
    theme_src = open(THEME, encoding='utf-8').read()
    defined = set(re.findall(r'\bstatic\s+(?:let|var)\s+([A-Za-z_]\w*)', theme_src))
    defined |= set(re.findall(r'\bstatic\s+func\s+([A-Za-z_]\w*)', theme_src))
    ext_defined = set(re.findall(r'\n\s{4}func\s+([A-Za-z_]\w*)', theme_src))
    missing = {}
    for f in files:
        if f == THEME:
            continue
        src = open(f, encoding='utf-8').read()
        for name in set(re.findall(r'Theme\.([A-Za-z_]\w*)', src)):
            if name not in defined:
                missing.setdefault(name, []).append(os.path.basename(f))
    print(f'  Theme.swift 定义令牌/函数：{len(defined)} 个')
    if missing:
        for k, v in sorted(missing.items()):
            blocking.append(f'Theme.{k} 未定义 ← {sorted(set(v))}')
            print(f'  [FAIL] Theme.{k} ← {sorted(set(v))}')
    else:
        print('  [PASS] 所有跨文件引用的 Theme 令牌均已定义')

    # ── 3. 公共 API 表面回归 ──
    print('\n=== 3. v29 公共 API 表面回归 ===')
    lost_tokens = sorted(t for t in BASELINE_TOKENS if t not in defined)
    lost_funcs = sorted(t for t in BASELINE_FUNCS if t not in defined)
    lost_ext = sorted(t for t in BASELINE_VIEW_EXT if t not in ext_defined)
    if lost_tokens or lost_funcs or lost_ext:
        blocking.append(f'v29 API 丢失：令牌 {lost_tokens} 函数 {lost_funcs} 扩展 {lost_ext}')
        print(f'  [FAIL] 丢失 令牌{lost_tokens} 函数{lost_funcs} 扩展{lost_ext}')
    else:
        print('  [PASS] v29 的全部令牌 / 函数 / 视图扩展均保留')
    icon_body = ''
    m = re.search(r'enum Icon \{', theme_src)
    if m:
        icon_body = theme_src[m.end():]
    icon_members = set(re.findall(r'\bstatic\s+let\s+([A-Za-z_]\w*)', icon_body))
    added = sorted(t for t in defined
                   if t not in BASELINE_TOKENS and t not in BASELINE_FUNCS
                   and t not in icon_members)
    print(f'  新增主题令牌：{added}')

    # ── 4. 风格纪律 ──
    print('\n=== 4. 风格纪律（写死圆角 / 阴影 / 按压缩放）===')
    radius_hits, shadow_hits, press_hits = [], [], []
    for f in files:
        src = open(f, encoding='utf-8').read()
        name = os.path.basename(f)
        for m in re.finditer(r'cornerRadius:\s*(\d+(?:\.\d+)?)', src):
            radius_hits.append(f'{name}:{m.group(1)}')
        for m in re.finditer(r'\.shadow\(', src):
            shadow_hits.append(f'{name}')
        for m in re.finditer(r'PressButtonStyle\(scale:\s*0\.', src):
            press_hits.append(f'{name}')
    print(f'  写死 cornerRadius：{len(radius_hits)} 处 {radius_hits[:8]}')
    print(f'  自写 .shadow()：{len(shadow_hits)} 处 {sorted(set(shadow_hits))}')
    print(f'  PressButtonStyle(scale:)：{len(press_hits)} 处 {sorted(set(press_hits))}')

    # 图形装饰豁免：细竖条的端帽圆角、目录条目的描边 —— 它们不是「组件圆角」。
    RADIUS_EXEMPT = {
        ('NotesUnifiedView.swift', '1.5'): '竖向标记条端帽（2.5pt 宽细条）',
        ('ReaderAnnotations.swift', '1.5'): '竖向标记条端帽（2.5pt 宽细条）',
        ('ReaderView.swift', '4'): '目录条目描边，小容器固定圆角',
    }
    unexempt = []
    for hit in radius_hits:
        fname, val = hit.rsplit(':', 1)
        reason = RADIUS_EXEMPT.get((fname, val))
        if reason:
            print(f'  [PASS] {hit} — 图形装饰豁免：{reason}')
        else:
            unexempt.append(hit)
    if unexempt:
        blocking.append(f'仍有写死圆角（未豁免）：{unexempt}')
        print(f'  [FAIL] 未豁免的写死圆角：{unexempt}')
    else:
        print('  [PASS] 所有写死圆角均为已登记的图形装饰')

    if press_hits:
        blocking.append(f'仍有按压缩放残留：{sorted(set(press_hits))}')
        print('  [FAIL] 按压缩放应全部改为 PressButtonStyle()')
    else:
        print('  [PASS] 无按压位移残留')

    # ── 5. 硬编码颜色 ──
    print('\n=== 5. 硬编码颜色残留 ===')
    hex_hits = []
    for f in files:
        if f == THEME:
            continue
        src = open(f, encoding='utf-8').read()
        name = os.path.basename(f)
        for m in re.finditer(r'(?:Color|color)\s*[:(]\s*0x([0-9A-Fa-f]{6})', src):
            hex_hits.append(f'{name}:0x{m.group(1)}')
    if hex_hits:
        warnings.append(f'仍有写死色值：{hex_hits}')
        print(f'  [WARN] {len(hex_hits)} 处 {hex_hits[:10]}')
    else:
        print('  [PASS] 屏幕代码无写死色值')

    print()
    if blocking:
        print(f'❌ 阻断项 {len(blocking)}：')
        for b in blocking:
            print('   -', b)
        return 1
    print('✅ Swift 侧静态验收全部通过（不含编译）。')
    for w in warnings:
        print('   ⚠️', w)
    return 0


if __name__ == '__main__':
    sys.exit(main())
