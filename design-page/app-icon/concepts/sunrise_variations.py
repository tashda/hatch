# Variations on H5 Sunrise, Hatch's new icon. Writes sunrise-variations.html.
import math, pathlib
from make_concepts import tile, grad, svg
from stage_round2 import loupe
from make_concepts import designer_blueprint
HERE = pathlib.Path(__file__).parent
n = 0

def sunrise(sky=("#ffffff", "#e8edf7"), sea=("#4180f0", "#1f49aa"), sun=("#ffd27a", "#ffa01c"), horizon=590, r=200, cx=512,
            lines="bars", glow=None, rays=False, halo=False, border="rgba(20,40,90,.16)", wave=False, bands=None, line_color="#ffffff"):
    global n
    n += 1
    p = f"v{n}"
    d, bg, br = tile(p, sky[0], sky[1], border)
    defs = d + grad(f"{p}sea", sea[0], sea[1], horizon, 924) + grad(f"{p}sun", sun[0], sun[1], horizon - r, horizon)
    art = ""
    if glow:
        defs += f'<radialGradient id="{p}glow" cx="{cx}" cy="{horizon}" r="{r*2.1}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{glow}" stop-opacity=".75"/><stop offset=".45" stop-color="{glow}" stop-opacity=".28"/><stop offset="1" stop-color="{glow}" stop-opacity="0"/></radialGradient>'
        art += f'<circle cx="{cx}" cy="{horizon}" r="{r*2.1}" fill="url(#{p}glow)"/>'
    if halo:
        art += "".join(f'<circle cx="{cx}" cy="{horizon}" r="{r+k*56}" fill="{sun[1]}" opacity="{0.16-k*0.05:.2f}"/>' for k in (1, 2))
    if rays:
        for a in range(15, 180, 22):
            x1, y1 = cx + (r + 40) * math.cos(math.radians(a)), horizon - (r + 40) * math.sin(math.radians(a))
            x2, y2 = cx + (r + 130) * math.cos(math.radians(a)), horizon - (r + 130) * math.sin(math.radians(a))
            art += f'<path d="M{x1:.0f} {y1:.0f} L{x2:.0f} {y2:.0f}" stroke="{sun[1]}" stroke-width="26" stroke-linecap="round"/>'
    art += f'<circle cx="{cx}" cy="{horizon}" r="{r}" fill="url(#{p}sun)"/>'
    if wave:
        w = f"M100 {horizon} " + " ".join(f"Q{100+i*103+51} {horizon-(22 if i%2==0 else -22)} {100+(i+1)*103} {horizon}" for i in range(8)) + " V924 H100 Z"
        art += f'<path d="{w}" fill="url(#{p}sea)"/>'
    elif bands:
        h = (924 - horizon) / len(bands)
        art += "".join(f'<rect x="100" y="{horizon+i*h:.0f}" width="824" height="{h+1:.0f}" fill="{c}"/>' for i, c in enumerate(bands))
    else:
        art += f'<rect x="100" y="{horizon}" width="824" height="{924-horizon}" fill="url(#{p}sea)"/>'
    depth = 924 - horizon
    if lines == "bars":
        art += f'<path d="M{cx-182} {horizon+100} H{cx+182} M{cx-112} {horizon+180} H{cx+112}" stroke="{line_color}" stroke-opacity=".35" stroke-width="28" stroke-linecap="round"/>'
    elif lines == "reflection":
        # The sun's reflection, broken into shorter and shorter orange dashes.
        for i, (wd, op) in enumerate([(r * 1.5, .95), (r * 1.05, .75), (r * 0.66, .55), (r * 0.36, .4)]):
            y = horizon + depth * (0.17 + i * 0.17)
            art += f'<path d="M{cx-wd/2:.0f} {y:.0f} H{cx+wd/2:.0f}" stroke="url(#{p}sun)" stroke-opacity="{op}" stroke-width="{30-i*4}" stroke-linecap="round"/>'
    elif lines == "split":
        # Reflection dashes broken in two, like light on small waves.
        for i, wd in enumerate([r * 1.6, r * 1.15, r * 0.75]):
            y = horizon + depth * (0.2 + i * 0.22)
            g = 34 - i * 6
            art += f'<path d="M{cx-wd/2:.0f} {y:.0f} H{cx-g:.0f} M{cx+g:.0f} {y:.0f} H{cx+wd/2:.0f}" stroke="url(#{p}sun)" stroke-opacity="{.95-i*.2:.2f}" stroke-width="26" stroke-linecap="round"/>'
    elif lines == "waves":
        for i, wd in enumerate([320, 220]):
            y = horizon + depth * (0.3 + i * 0.28); x0 = cx - wd / 2; seg = wd / 4
            path = f"M{x0:.0f} {y:.0f} " + " ".join(f"q{seg/2:.0f} {-18 if k%2==0 else 18} {seg:.0f} 0" for k in range(4))
            art += f'<path d="{path}" fill="none" stroke="{line_color}" stroke-opacity=".4" stroke-width="24" stroke-linecap="round"/>'
    elif lines == "left":
        art += f'<path d="M190 {horizon+100} H520 M190 {horizon+180} H400" stroke="{line_color}" stroke-opacity=".35" stroke-width="28" stroke-linecap="round"/>'
    body = bg + f'<g clip-path="url(#{p}clip)">{art}</g>'
    return svg(defs, body, br)

DAWN = ("#fff4e6", "#ffdcc0")
NIGHT = ("#18234a", "#f6b48a")
variants = [
    ("Today's H5", "White sky, blue sea, two white bars.", sunrise(), ""),
    ("Reflection", "The bars become the sun's reflection: orange dashes that get shorter towards you.", sunrise(lines="reflection"), "recommended"),
    ("Broken reflection", "Each dash broken in the middle, like light on small waves.", sunrise(lines="split"), ""),
    ("Soft glow", "A warm glow behind the sun on a white sky.", sunrise(glow="#ffb347"), ""),
    ("Dawn sky", "A peach sky, glow, and the reflection. Warmer and more of a morning.", sunrise(sky=DAWN, glow="#ff9f43", lines="reflection"), ""),
    ("Big sun, low horizon", "More sky, the sun almost a dome.", sunrise(horizon=660, r=250, lines="reflection"), ""),
    ("Small sun, high horizon", "The sun just peeking, a lot of sea.", sunrise(horizon=520, r=140, lines="bars"), ""),
    ("Waves", "A wavy horizon and wavy lines.", sunrise(wave=True, lines="waves"), ""),
    ("Halo", "Two flat rings around the sun instead of a soft glow.", sunrise(halo=True, lines="reflection"), ""),
    ("Rays", "Short rays around the sun.", sunrise(rays=True, r=170, lines="bars"), ""),
    ("Bands", "The sea as three bands of blue, lighter to darker. No lines.", sunrise(bands=["#5b93f5", "#3a6fdc", "#2350b8"], lines="none"), ""),
    ("Bare", "Only the sun and the sea.", sunrise(lines="none"), ""),
    ("Off centre", "The sun on the right third, the lines from the left.", sunrise(cx=640, r=170, lines="left"), ""),
    ("Night to dawn", "A navy sky warming to peach at the horizon, a deep sea, the glowing sun. Hatch's dark tile.", sunrise(sky=NIGHT, sea=("#24408f", "#0d1a45"), glow="#ffb347", lines="reflection", border="rgba(255,255,255,.12)"), ""),
    ("Teal and coral", "Another palette: a cream sky, a coral sun, a teal sea.", sunrise(sky=("#fffaf2", "#f4ece0"), sea=("#22a59a", "#0d6f6a"), sun=("#ff9a7a", "#f2603f"), lines="reflection"), ""),
    ("Deep blue", "A darker, richer sea and a golden sun.", sunrise(sea=("#2a4fb5", "#101f5c"), sun=("#ffe08a", "#ffb000"), glow="#ffd27a", lines="split"), ""),
]

def card(name, note, art, tag):
    sizes = "".join(f'<div class="s" style="width:{s}px;height:{s}px">{art}</div>' for s in (192, 64, 32, 16))
    dock = f'<div class="dock"><div>{art}</div><div>{loupe()}</div><div>{designer_blueprint()}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="sizes">{sizes}</div><div class="dockwrap">{dock}</div></section>'

html = f'''<!doctype html><meta charset="utf-8"><title>Sunrise variations</title>
<style>body{{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}} main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:12px}}
section{{background:#fff;border-radius:14px;padding:14px 18px}} h3{{margin:0 0 4px;font-weight:600}} p{{margin:0 0 10px;color:#555;min-height:2.6em}}
.sizes{{display:flex;align-items:flex-end;gap:14px}} .s svg{{width:100%;height:100%;display:block}}
.dockwrap{{margin-top:12px;padding:12px;border-radius:12px;background:linear-gradient(135deg,#6a7fb5,#c9a7a0)}} .dock{{display:flex;gap:8px;padding:8px 12px;border-radius:18px;background:rgba(255,255,255,.55);width:max-content}} .dock div{{width:56px;height:56px}} .dock svg{{width:100%;height:100%}}
.tag{{font-size:12px;font-weight:500;color:#b5651d}}</style>
<h2>Sunrise, variations</h2><main>{"".join(card(*v) for v in variants)}</main>'''
(HERE / "sunrise-variations.html").write_text(html)
print("ok")
