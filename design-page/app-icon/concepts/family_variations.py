# The Stage, the Components Designer and the menu bar item carrying Hatch's sunrise (AI4, AI5). Writes family-variations.html.
import math, pathlib
from make_concepts import tile, grad, svg
from sunrise_variations import sunrise
HERE = pathlib.Path(__file__).parent
FONT = 'font-family="-apple-system, SF Pro Display, Helvetica" font-weight="800"'
LIGHT = dict(sky=("#ffffff", "#e8edf7"), sea=("#4180f0", "#1f49aa"), sun=("#ffd27a", "#ffa01c"), glow=None)
NIGHT = dict(sky=("#18234a", "#f6b48a"), sea=("#24408f", "#0d1a45"), sun=("#ffd27a", "#ffa01c"), glow="#ffb347")
HATCH_LIGHT = sunrise(lines="reflection")
HATCH_DARK = sunrise(sky=NIGHT["sky"], sea=NIGHT["sea"], glow="#ffb347", lines="reflection", border="rgba(255,255,255,.12)")

def scene(p, x0, y0, x1, y1, horizon, cx, r, c, dashes=True):
    """Hatch's sunrise drawn into a box: sky, glow, sun, sea, reflection. The caller clips it."""
    defs = grad(f"{p}sky", *c["sky"], y0, horizon) + grad(f"{p}sea", *c["sea"], horizon, y1) + grad(f"{p}sun", *c["sun"], horizon - r, horizon)
    art = f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{horizon-y0}" fill="url(#{p}sky)"/>'
    if c["glow"]:
        defs += f'<radialGradient id="{p}gl" cx="{cx}" cy="{horizon}" r="{r*2.1}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{c["glow"]}" stop-opacity=".75"/><stop offset=".45" stop-color="{c["glow"]}" stop-opacity=".28"/><stop offset="1" stop-color="{c["glow"]}" stop-opacity="0"/></radialGradient>'
        art += f'<circle cx="{cx}" cy="{horizon}" r="{r*2.1}" fill="url(#{p}gl)"/>'
    art += f'<circle cx="{cx}" cy="{horizon}" r="{r}" fill="url(#{p}sun)"/><rect x="{x0}" y="{horizon}" width="{x1-x0}" height="{y1-horizon}" fill="url(#{p}sea)"/>'
    if dashes:
        depth = y1 - horizon
        for i, (wd, op) in enumerate([(r * 1.5, .95), (r * 1.05, .75), (r * 0.66, .55)]):
            y = horizon + depth * (0.2 + i * 0.2)
            art += f'<path d="M{cx-wd/2:.0f} {y:.0f} H{cx+wd/2:.0f}" stroke="url(#{p}sun)" stroke-opacity="{op}" stroke-width="{max(6, r*0.15-i*r*0.02):.0f}" stroke-linecap="round"/>'
    return defs, art

# ---------- Stage ----------

def stage_loupe(p, tile_colors, ring, handle, lens_colors, number=None, border="rgba(255,255,255,.10)"):
    d, bg, br = tile(p, *tile_colors, border)
    lx, ly, lr = 470, 470, 220
    sdefs, sart = scene(p, lx - lr, ly - lr, lx + lr, ly + lr, ly + 60, lx, 110, lens_colors)
    if number:
        size = {1: 300, 2: 260, 3: 200, 4: 150}.get(len(number), 600 / len(number))
        sart = f'<rect x="{lx-lr}" y="{ly-lr}" width="{2*lr}" height="{2*lr}" fill="#eef3fb"/><rect x="{lx-lr}" y="{ly+120}" width="{2*lr}" height="{lr}" fill="url(#{p}sea)"/>' + \
               f'<text x="{lx}" y="{ly+70}" text-anchor="middle" {FONT} font-size="{size}" letter-spacing="-8" fill="#1f49aa">{number}</text>'
    body = bg + f'''<g clip-path="url(#{p}clip)">
<path d="M{lx+150} {ly+150} L770 770" stroke="url(#{p}hd)" stroke-width="92" stroke-linecap="round"/>
<clipPath id="{p}lens"><circle cx="{lx}" cy="{ly}" r="{lr}"/></clipPath><g clip-path="url(#{p}lens)">{sart}</g>
<circle cx="{lx}" cy="{ly}" r="{lr}" fill="none" stroke="{ring}" stroke-width="34"/></g>'''
    return svg(d + sdefs + grad(f"{p}hd", *handle, 620, 770), body, br)

def stage_over_hatch(p, c, ring="#ffffff"):
    # Hatch's own sunrise as the tile, with a loupe magnifying the sun.
    d, bg, br = tile(p, *c["sky"], "rgba(20,40,90,.16)" if c is LIGHT else "rgba(255,255,255,.12)")
    sdefs, sart = scene(p, 100, 100, 924, 924, 640, 420, 150, c)
    zdefs, zart = scene(p + "z", 400, 150, 860, 610, 470, 620, 210, c, dashes=False)
    body = bg + f'''<g clip-path="url(#{p}clip)">{sart}
<path d="M780 560 L860 640" stroke="{ring}" stroke-width="64" stroke-linecap="round"/>
<clipPath id="{p}lens"><circle cx="630" cy="400" r="200"/></clipPath><g clip-path="url(#{p}lens)">{zart}</g>
<circle cx="630" cy="400" r="200" fill="none" stroke="{ring}" stroke-width="28"/></g>'''
    return svg(d + sdefs + zdefs, body, br)

NAVY = ("#1f2b4f", "#0d1530")
ORANGE = ("#ffc65a", "#ff9a10")
stage = [
    ("A Loupe over the sunrise", "S8 as it is, with Hatch's sunrise in the lens instead of the arch.",
     stage_loupe("sa", NAVY, "#c9d6f0", ORANGE, LIGHT), stage_loupe("sad", NAVY, "#c9d6f0", ORANGE, NIGHT), "recommended"),
    ("A with a ticket number", "The running Stage: the number in the sky of the lens, the sea kept below it.",
     stage_loupe("san", NAVY, "#c9d6f0", ORANGE, LIGHT, "151"), None, ""),
    ("B Light tile", "The same loupe on Hatch's white tile with a blue ring and handle. Closer to Hatch, less its own app.",
     stage_loupe("sb", ("#ffffff", "#e8edf7"), "#2f62d0", ("#4180f0", "#1f49aa"), LIGHT, border="rgba(20,40,90,.16)"),
     stage_loupe("sbd", NAVY, "#4f7fe0", ("#4180f0", "#1f49aa"), NIGHT), ""),
    ("C Dawn in the lens", "The dark scene in the lens in both modes: the Stage as the evening of the family.",
     stage_loupe("sc", NAVY, "#c9d6f0", ORANGE, NIGHT), None, ""),
    ("D Loupe on Hatch's icon", "Hatch's sunrise as the whole tile, a loupe lifting the sun up close. Says \"looking at Hatch's work\".",
     stage_over_hatch("sd", LIGHT), stage_over_hatch("sdd", NIGHT), ""),
]

# ---------- Components Designer ----------

def blueprint_tile(p, dark=False):
    d, bg, br = tile(p, *(("#16224a", "#0a1230") if dark else ("#2a63d8", "#1a3f9e")), "rgba(255,255,255,.14)")
    fine = "".join(f'<path d="M{v} 100 V924 M100 {v} H924" stroke="#fff" stroke-opacity=".08" stroke-width="2"/>' for v in range(132, 924, 32))
    major = "".join(f'<path d="M{v} 100 V924 M100 {v} H924" stroke="#fff" stroke-opacity=".16" stroke-width="3"/>' for v in range(228, 924, 128))
    return d, bg + f'<g clip-path="url(#{p}clip)">{fine}{major}', br

SUN = '<linearGradient id="{p}sun" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffd27a"/><stop offset="1" stop-color="#ffa01c"/></linearGradient>'

def designer_outline(p, dark=False):
    # The sunrise as a drawing: horizon, the sun's circle in outline, dashed reflections, the sun's top half filled.
    d, bg, br = blueprint_tile(p, dark)
    H, R = 590, 210
    art = f'''<clipPath id="{p}up"><rect x="0" y="0" width="1024" height="{H}"/></clipPath>
<circle cx="512" cy="{H}" r="{R}" fill="url(#{p}sun)" clip-path="url(#{p}up)"/>
<circle cx="512" cy="{H}" r="{R+40}" fill="none" stroke="#fff" stroke-width="10"/>
<path d="M140 {H} H884" stroke="#fff" stroke-width="12"/>
<path d="M{512-180} {H+90} H{512+180} M{512-120} {H+160} H{512+120} M{512-70} {H+230} H{512+70}" stroke="#fff" stroke-opacity=".8" stroke-width="10" stroke-dasharray="26 18" stroke-linecap="round"/>
<path d="M{512-R-40} 840 H{512+R+40} M{512-R-40} 820 V860 M{512+R+40} 820 V860" stroke="#fff" stroke-opacity=".7" stroke-width="6"/>'''
    return svg(d + SUN.format(p=p), bg + art + "</g>", br)

def designer_compass(p, dark=False):
    # A compass construction: the whole circle drawn, dashed below the horizon, the centre and radius marked, the top half filled.
    d, bg, br = blueprint_tile(p, dark)
    H, R = 600, 230
    art = f'''<clipPath id="{p}up"><rect x="0" y="0" width="1024" height="{H}"/></clipPath><clipPath id="{p}dn"><rect x="0" y="{H}" width="1024" height="424"/></clipPath>
<circle cx="512" cy="{H}" r="{R}" fill="url(#{p}sun)" clip-path="url(#{p}up)"/>
<circle cx="512" cy="{H}" r="{R}" fill="none" stroke="#fff" stroke-width="8" stroke-dasharray="22 16" clip-path="url(#{p}dn)"/>
<path d="M140 {H} H884" stroke="#fff" stroke-width="12"/>
<path d="M512 {H} L{512+R*math.cos(math.radians(40)):.0f} {H-R*math.sin(math.radians(40)):.0f}" stroke="#fff" stroke-width="8"/>
<circle cx="512" cy="{H}" r="14" fill="#fff"/>
<path d="M512 {H-R-60} V{H-R-20} M492 {H-R-40} H532" stroke="#fff" stroke-opacity=".7" stroke-width="6"/>'''
    return svg(d + SUN.format(p=p), bg + art + "</g>", br)

def designer_framed(p, dark=False):
    # Hatch's sunrise placed on the blueprint as a part being designed: in a frame with selection handles.
    d, bg, br = blueprint_tile(p, dark)
    x0, y0, x1, y1 = 260, 260, 764, 764
    sdefs, sart = scene(p, x0, y0, x1, y1, 560, 512, 140, NIGHT if dark else LIGHT)
    handles = "".join(f'<rect x="{x-20}" y="{y-20}" width="40" height="40" rx="6" fill="#fff" stroke="#ffa01c" stroke-width="8"/>' for x in (x0, x1) for y in (y0, y1))
    art = f'''<clipPath id="{p}f"><rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" rx="60"/></clipPath><g clip-path="url(#{p}f)">{sart}</g>
<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" fill="none" stroke="#ffa01c" stroke-width="8"/>{handles}'''
    return svg(d + sdefs, bg + art + "</g>", br)

def designer_dimensioned(p, dark=False):
    # The sunrise in white line art with its measurements: width of the sun, height of the horizon.
    d, bg, br = blueprint_tile(p, dark)
    H, R = 610, 200
    art = f'''<clipPath id="{p}up"><rect x="0" y="0" width="1024" height="{H}"/></clipPath>
<circle cx="512" cy="{H}" r="{R}" fill="url(#{p}sun)" clip-path="url(#{p}up)"/>
<path d="M200 {H} H824" stroke="#fff" stroke-width="12" stroke-linecap="round"/>
<path d="M{512-R} 330 H{512+R} M{512-R} 310 V350 M{512+R} 310 V350" stroke="#fff" stroke-opacity=".8" stroke-width="7"/>
<path d="M200 {H+40} V820 M180 {H+40} H220 M180 820 H220" stroke="#fff" stroke-opacity=".8" stroke-width="7"/>
<path d="M{512-150} {H+90} H{512+150} M{512-95} {H+160} H{512+95}" stroke="#fff" stroke-opacity=".55" stroke-width="12" stroke-linecap="round"/>'''
    return svg(d + SUN.format(p=p), bg + art + "</g>", br)

designer = [
    ("A Sunrise as a drawing", "D3 with the sunrise in place of the arch: horizon, the sun's outline, dashed reflections and a dimension line, the sun filled orange.",
     designer_outline("da"), designer_outline("dad", True), "recommended"),
    ("B Compass construction", "The sun's whole circle drawn, dashed below the horizon, its centre and radius marked.",
     designer_compass("db"), designer_compass("dbd", True), ""),
    ("C Part in a frame", "Hatch's sunrise placed on the blueprint inside a frame with selection handles, a part being designed.",
     designer_framed("dc"), designer_framed("dcd", True), ""),
    ("D Measured", "Line art with measurements: the sun's width, the horizon's height.",
     designer_dimensioned("dd"), designer_dimensioned("ddd", True), ""),
]

# ---------- Menu bar item (template: one colour, 18 pt; the second drawing is "tickets wait for you") ----------

def g(shapes):
    return f'<svg viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg" fill="currentColor" stroke="currentColor">{shapes}</svg>'

def half(cx, cy, r):
    return f'<path d="M{cx-r} {cy} A{r} {r} 0 0 1 {cx+r} {cy} Z" stroke="none"/>'

HZ = '<path d="M1.5 {y} H16.5" stroke-width="1.5" stroke-linecap="round" fill="none"/>'
menu = [
    ("A The sun comes up", "At rest the sun is half up; when tickets wait for you it has risen most of the way. The signal is the sunrise itself, no badge. Subtle at 18 pt.",
     g(half(9, 11.5, 4.5) + HZ.format(y=11.5) + '<path d="M6.5 14.8 H11.5" stroke-width="1.5" stroke-linecap="round" fill="none"/>'),
     g('<clipPath id="ca"><rect width="18" height="10.4"/></clipPath><circle cx="9" cy="8.2" r="4.6" stroke="none" clip-path="url(#ca)"/>' + HZ.format(y=11.5) + '<path d="M6.5 14.8 H11.5" stroke-width="1.5" stroke-linecap="round" fill="none"/>'), ""),
    ("B Rays when waiting", "A half sun on the horizon and one reflection; rays appear when tickets wait. The clearest change at 18 pt and still reads as a sun.",
     g(half(9, 12, 4.5) + HZ.format(y=12) + '<path d="M6.5 15.5 H11.5" stroke-width="1.5" stroke-linecap="round" fill="none"/>'),
     g(half(9, 12, 4.5) + HZ.format(y=12) + '<path d="M6.5 15.5 H11.5 M9 2.2 V4 M3.6 4.6 L4.9 5.9 M14.4 4.6 L13.1 5.9 M1.8 9.5 H3.4 M16.2 9.5 H14.6" stroke-width="1.5" stroke-linecap="round" fill="none"/>'), "recommended"),
    ("C Outline to filled", "The sun drawn as an outline at rest, filled when tickets wait.",
     g('<path d="M4.5 11.5 A4.5 4.5 0 0 1 13.5 11.5" stroke-width="1.5" fill="none"/>' + HZ.format(y=11.5) + '<path d="M6.5 14.8 H11.5" stroke-width="1.5" stroke-linecap="round" fill="none"/>'),
     g(half(9, 11.5, 4.5) + HZ.format(y=11.5) + '<path d="M6.5 14.8 H11.5" stroke-width="1.5" stroke-linecap="round" fill="none"/>'), ""),
    ("D Mini icon", "A filled rounded square with the sun and horizon cut out, like a tiny app icon; the sun rises when tickets wait.",
     g('<mask id="m1"><rect width="18" height="18" fill="#fff"/><path d="M5.8 11 A3.2 3.2 0 0 1 12.2 11 Z" fill="#000"/><path d="M3 11 H15" stroke="#000" stroke-width="1.4"/></mask><rect x="1.5" y="1.5" width="15" height="15" rx="4" stroke="none" mask="url(#m1)"/>'),
     g('<mask id="m2"><rect width="18" height="18" fill="#fff"/><circle cx="9" cy="7.5" r="3" fill="#000"/><path d="M3 12 H15" stroke="#000" stroke-width="1.4"/></mask><rect x="1.5" y="1.5" width="15" height="15" rx="4" stroke="none" mask="url(#m2)"/>'), ""),
    ("E Wide dome", "A wide, low dome and one reflection; a small dot beside it when tickets wait, as the menu bar usually does.",
     g(half(9, 11, 6) + HZ.format(y=11) + '<path d="M5.5 14.5 H12.5" stroke-width="1.5" stroke-linecap="round" fill="none"/>'),
     g(half(8, 11, 5.5) + '<path d="M1.5 11 H14.5 M4.5 14.5 H11.5" stroke-width="1.5" stroke-linecap="round" fill="none"/><circle cx="15.2" cy="4.2" r="2.3" stroke="none"/>'), ""),
]

def icon_row(name, note, light, dark, tag):
    sizes = "".join(f'<div class="s" style="width:{s}px;height:{s}px">{light}</div>' for s in (192, 64, 32, 16))
    darkpart = f'<div class="pair"><span>Dark</span><div class="s" style="width:96px;height:96px">{dark}</div></div>' if dark else ""
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="sizes">{sizes}{darkpart}</div></section>'

def menu_row(name, note, rest, wait, tag):
    def bar(bgc, fg, glyph):
        return f'<div class="bar" style="background:{bgc};color:{fg}"><span style="width:18px;height:18px">{glyph}</span><span style="width:18px;height:18px;opacity:.85">{WIFI}</span><span class="clock">Mon 5 Oct 14:02</span></div>'
    big = lambda gl: f'<div class="big">{gl}</div>'
    return f'''<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p>
<div class="menu"><div><span class="lab">At rest</span>{bar("#f2f2f4", "#000", rest)}{bar("#2b2b30", "#fff", rest)}{big(rest)}</div>
<div><span class="lab">Tickets wait</span>{bar("#f2f2f4", "#000", wait)}{bar("#2b2b30", "#fff", wait)}{big(wait)}</div></div></section>'''

WIFI = g('<path d="M2 7 Q9 1 16 7 M4.5 9.6 Q9 5.6 13.5 9.6 M7 12.2 Q9 10.6 11 12.2" fill="none" stroke-width="1.6" stroke-linecap="round"/><circle cx="9" cy="14.6" r="1.3" stroke="none"/>')

html = f'''<!doctype html><meta charset="utf-8"><title>Stage, Designer and menu bar</title>
<style>body{{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}} main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(460px,1fr));gap:12px}}
section{{background:#fff;border-radius:14px;padding:14px 18px}} h2{{margin:28px 0 8px}} h3{{margin:0 0 4px;font-weight:600}} p{{margin:0 0 10px;color:#555;min-height:2.6em}}
.sizes{{display:flex;align-items:flex-end;gap:14px}} .s svg{{width:100%;height:100%;display:block}} .pair{{margin-left:auto;text-align:center;color:#888;font-size:12px}}
.tag{{font-size:12px;font-weight:500;color:#b5651d}} .family{{display:flex;gap:24px;flex-wrap:wrap}} .dock{{display:flex;gap:10px;padding:10px 14px;border-radius:20px;width:max-content}} .dock div{{width:72px;height:72px}} .dock svg{{width:100%;height:100%}}
.menu{{display:flex;gap:24px}} .bar{{display:flex;align-items:center;gap:14px;height:26px;padding:0 12px;border-radius:6px;margin-bottom:6px;font-size:13px}} .bar svg{{width:18px;height:18px;display:block}} .clock{{margin-left:4px}}
.big{{width:144px;height:144px;background:repeating-conic-gradient(#f3f3f3 0 25%,#fff 0 50%) 0 0/16px 16px;border-radius:8px;color:#000}} .big svg{{width:100%;height:100%}} .lab{{display:block;font-size:12px;color:#888;margin-bottom:4px}}</style>
<h2>The family, with the recommended picks</h2>
<div class="family"><div class="dock" style="background:linear-gradient(135deg,#dfe6f4,#f6efe9)"><div>{HATCH_LIGHT}</div><div>{stage[0][2]}</div><div>{designer[0][2]}</div></div>
<div class="dock" style="background:linear-gradient(135deg,#1b1f2e,#2c2430)"><div>{HATCH_DARK}</div><div>{stage[0][3]}</div><div>{designer[0][3]}</div></div></div>
<h2>Stage</h2><main>{"".join(icon_row(*v) for v in stage)}</main>
<h2>Components Designer</h2><main>{"".join(icon_row(*v) for v in designer)}</main>
<h2>Menu bar item</h2><main>{"".join(menu_row(*v) for v in menu)}</main>'''
(HERE / "family-variations.html").write_text(html)
print("ok")
