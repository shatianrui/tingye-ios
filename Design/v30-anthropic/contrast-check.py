#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""听页 · v30「Claude · Anthropic」配色对比度校验。

对照 Anthropic 官方品牌色与 Claude 设计系统（CDS）令牌，逐对计算 WCAG 对比度。

用色口径（三条纪律）：
  1. 页面底永远是奶油画布，白只用于卡片与输入框；
  2. 陶土是「面」不是「字」——陶土上的文字用 onClay 压住，另有 clayText 一档用于小字；
  3. 所有灰色都是暖中性，系统冷灰一律不用。

规则：
  正文 / 关键文字 ≥ 4.5:1
  极次级文字与图标类 ≥ 3:1
判定：PASS / FAIL
"""

def srgb_to_lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def luminance(hex_str: str) -> float:
    h = hex_str.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * srgb_to_lin(r) + 0.7152 * srgb_to_lin(g) + 0.0722 * srgb_to_lin(b)

def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def mix(fg: str, bg: str, alpha: float) -> str:
    """模拟 alpha 叠色，返回合成后的十六进制。"""
    hf, hb = fg.lstrip('#'), bg.lstrip('#')
    out = []
    for i in (0, 2, 4):
        f = int(hf[i:i + 2], 16)
        b = int(hb[i:i + 2], 16)
        out.append(round(f * alpha + b * (1 - alpha)))
    return '#%02X%02X%02X' % tuple(out)


# ── Anthropic / Claude 设计系统令牌 ──────────────────────────────────────
LIGHT = {
    'canvas':        '#FAF9F5',   # Anthropic 奶油画布
    'surface':       '#FFFFFF',   # 浮起卡面
    'surfaceSubtle': '#F0EFE6',   # 分段轨道 / 沉底
    'ink':           '#141413',   # 标题墨
    'inkStrong':     '#1F1E1D',   # 正文主色
    'ink2':          '#3D3D3A',   # 正文副色
    'ink3':          '#6E6D66',   # 说明文字（较官方 #73726C 加深一档）
    'ink4':          '#8E8C84',   # 极次级：时间戳、页脚
    'line':          '#E7E6E1',   # 发丝线
    'clay':          '#D97757',   # 陶土（品牌色，只做面）
    'clayEmph':      '#C6613F',   # 陶土按下态
    'clayText':      '#A34E2B',   # 陶土文字（小字语义，≥4.5:1）
    'claySoft':      '#F5E7DF',   # 陶土淡底
    'onClay':        '#141413',   # 压在陶土面上的字
    'danger':        '#B53333',
    'focus':         '#2D7FD8',   # 唯一的冷色：焦点环（较官方 #3898EC 加深）
    'onDark':        '#FFFFFF',   # 压在墨底上的字
}

DARK = {
    'canvas':        '#141413',
    'surface':       '#1F1E1D',
    'surfaceSubtle': '#2A2926',
    'ink':           '#FAF9F5',
    'inkStrong':     '#EFEDE6',
    'ink2':          '#C2C0B6',
    'ink3':          '#98968E',
    'ink4':          '#73726C',
    'line':          '#2C2C33',
    'clay':          '#D97757',
    'clayEmph':      '#E08C6E',
    'clayText':      '#F0AD88',
    'claySoft':      '#472E25',
    'onClay':        '#141413',
    'danger':        '#FF9FAD',
    'focus':         '#5AA9F0',
    'onDark':        '#141413',
}

# (前景令牌, 背景令牌, 最低对比度, 说明)
PAIRS = [
    ('ink',        'canvas',        4.5, '标题墨 / 画布'),
    ('ink',        'surface',       4.5, '标题墨 / 卡面'),
    ('inkStrong',  'canvas',        4.5, '正文主色 / 画布'),
    ('inkStrong',  'surface',       4.5, '正文主色 / 卡面'),
    ('ink2',       'canvas',        4.5, '正文副色 / 画布'),
    ('ink2',       'surface',       4.5, '正文副色 / 卡面'),
    ('ink2',       'surfaceSubtle', 4.5, '正文副色 / 沉底'),
    ('ink3',       'canvas',        4.5, '说明文字 / 画布'),
    ('ink3',       'surface',       4.5, '说明文字 / 卡面'),
    ('ink3',       'surfaceSubtle', 4.5, '说明文字 / 沉底'),
    ('ink4',       'canvas',        3.0, '极次级 / 画布'),
    ('ink4',       'surface',       3.0, '极次级 / 卡面'),
    ('clayText',   'canvas',        4.5, '陶土文字 / 画布'),
    ('clayText',   'surface',       4.5, '陶土文字 / 卡面'),
    ('clayText',   'surfaceSubtle', 4.5, '陶土文字 / 沉底'),
    ('onClay',     'clay',          4.5, '陶土面上的字 / 陶土面'),
    ('onClay',     'clayEmph',      4.5, '陶土面上的字 / 陶土按下面'),
    ('danger',     'canvas',        4.5, '危险色 / 画布'),
    ('danger',     'surface',       4.5, '危险色 / 卡面'),
    ('focus',      'canvas',        3.0, '焦点环 / 画布'),
]

def run(name, tokens, invert_button=False):
    print(f'\n── {name} ──')
    failures = 0
    for fg, bg, need, label in PAIRS:
        c = contrast(tokens[fg], tokens[bg])
        ok = c >= need
        if not ok:
            failures += 1
        mark = 'PASS' if ok else 'FAIL'
        print(f'  [{mark:4s}] {label:<26s} {tokens[fg]} on {tokens[bg]}  {c:5.2f}:1  (需 ≥{need})')
    # 主按钮：墨底 + 纸字
    if invert_button:
        fg, bg, label = 'ink', 'surface', '深色模式主按钮文字 / 纸底按钮'
    else:
        fg, bg, label = 'onDark', 'ink', '主按钮文字 / 墨底按钮'
    c = contrast(tokens[fg], tokens[bg])
    ok = c >= 4.5
    if not ok:
        failures += 1
    print(f'  [{"PASS" if ok else "FAIL":4s}] {label:<26s} {tokens[fg]} on {tokens[bg]}  {c:5.2f}:1  (需 ≥4.5)')
    return failures


f1 = run('日间模式', LIGHT)
f2 = run('深色模式', DARK, invert_button=True)

# ── 陶土淡底（跟读铺底 / 选中行）上的文字 ────────────────────────────────
print('\n── 陶土淡底上的文字（跟读带 / 选中态）──')
for mode, t in (('日间', LIGHT), ('深色', DARK)):
    wash = mix(t['clay'], t['canvas'], 0.14) if mode == '日间' else mix(t['clay'], t['canvas'], 0.26)
    c1 = contrast(t['ink'], wash)
    c2 = contrast(t['clayText'], wash)
    print(f'  {mode} 铺底 {wash}：ink {c1:.2f}:1  clayText {c2:.2f}:1')

# ── 发丝线与卡面分离度（非文字，靠面差分层）──
print('\n── 面差分离度（非文字要求 ≥1.05）──')
for mode, t in (('日间', LIGHT), ('深色', DARK)):
    print(f'  {mode} line {t["line"]} on canvas {t["canvas"]}: {contrast(t["line"], t["canvas"]):.2f}:1')
    print(f'  {mode} surface {t["surface"]} on canvas {t["canvas"]}: {contrast(t["surface"], t["canvas"]):.2f}:1')

print(f'\n合计不达标项：{f1 + f2}')
print('结论：', '全部通过 ✅' if f1 + f2 == 0 else '需要调整 ❌')
