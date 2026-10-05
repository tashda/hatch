# Second round for the Components Designer's icon and the menu bar item, with Hatch's sunrise. Writes designer-menubar.html.
import math, pathlib
from make_concepts import tile, grad, svg
from family_variations import scene, LIGHT, NIGHT, HATCH_LIGHT, HATCH_DARK, stage, g, half
HERE = pathlib.Path(__file__).parent
STAGE_L, STAGE_D = stage[0][2], stage[0][3]
SUNG = '<linearGradient id="{p}sun" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffd27a"/><stop offset="1" stop-color="#ffa01c"/></linearGradient>'

def base(p, dark):
    if dark:
        return tile(p, "#1f2b4f", "#0d1530", "rgba(255,255,255,.12)")
    return tile(p, "#ffffff", "#e8edf7", "rgba(20,40,90,.16)")

def toggle(p, dark=False):
    # A switch, the most recognisable UI part there is: the track is Hatch's sea and sky, the knob is the sun.
    d, bg, br = base(p, dark)
    x0, x1, cy, h = 170, 854, 512, 340
    colors = NIGHT if dark else dict(LIGHT, sky=("#d5e1f7", "#bccdef"))
    sdefs, sart = scene(p, x0, cy - h / 2, x1, cy + h / 2, cy + 30, 684, 130, colors, dashes=False)
    body = bg + f'''<g clip-path="url(#{p}clip)">
<clipPath id="{p}tr"><rect x="{x0}" y="{cy-h/2}" width="{x1-x0}" height="{h}" rx="{h/2}"/></clipPath><g clip-path="url(#{p}tr)">{sart}{''.join(f'<path d="M{x} {cy+80+i*44} H{x+w}" stroke="#fff" stroke-opacity=".35" stroke-width="18" stroke-linecap="round"/>' for i, (x, w) in enumerate([(250, 260), (300, 160)]))}</g>
<rect x="{x0}" y="{cy-h/2}" width="{x1-x0}" height="{h}" rx="{h/2}" fill="none" stroke="{'#ffffff' if dark else '#1f49aa'}" stroke-opacity=".30" stroke-width="8"/>
<circle cx="684" cy="{cy}" r="140" fill="url(#{p}sun)" stroke="#fff" stroke-width="16"/></g>'''
    return svg(d + sdefs + SUNG.format(p=p), body, br)

def swatches(p, dark=False):
    # A fan of colour swatches, the design system's palette, with the sunrise on the top card.
    d, bg, br = base(p, dark)
    cards = ""
    for ang, col in ((-22, "#ffa01c"), (-8, "#4180f0")):
        cards += f'<g transform="rotate({ang} 512 820)"><rect x="372" y="250" width="280" height="520" rx="48" fill="{col}"/><rect x="372" y="640" width="280" height="130" rx="0" fill="#fff" opacity=".9"/></g>'
    sdefs, sart = scene(p, 372, 250, 652, 640, 470, 512, 90, NIGHT if dark else LIGHT)
    top = f'''<g transform="rotate(8 512 820)"><clipPath id="{p}cd"><rect x="372" y="250" width="280" height="520" rx="48"/></clipPath>
<g clip-path="url(#{p}cd)">{sart}<rect x="372" y="640" width="280" height="130" fill="#fff"/></g>
<rect x="420" y="680" width="120" height="22" rx="11" fill="#c5d0e6"/><rect x="420" y="718" width="80" height="18" rx="9" fill="#dde4f1"/></g>'''
    return svg(d + sdefs, bg + f'<g clip-path="url(#{p}clip)">{cards}{top}</g>', br)

def pencil(p, dark=False):
    # Hatch's sunrise being drawn: the sun and sea done, a pencil finishing the horizon.
    d, bg, br = base(p, dark)
    sdefs, sart = scene(p, 100, 100, 924, 924, 600, 470, 190, NIGHT if dark else LIGHT)
    pen = '''<g transform="rotate(40 700 470)"><rect x="660" y="140" width="80" height="380" rx="14" fill="#ffc65a"/><rect x="660" y="140" width="80" height="60" rx="14" fill="#f0f3fa"/>
<rect x="660" y="190" width="80" height="18" fill="#c9d1e3"/><path d="M660 520 L700 600 L740 520 Z" fill="#f6dcb5"/><path d="M688 576 L700 600 L712 576 Z" fill="#1d2440"/></g>'''
    return svg(d + sdefs, bg + f'<g clip-path="url(#{p}clip)">{sart}{pen}</g>', br)

def set_square(p, dark=False):
    # A drafting triangle laid over the sunrise: the sunrise as something designed.
    d, bg, br = base(p, dark)
    sdefs, sart = scene(p, 100, 100, 924, 924, 600, 512, 200, NIGHT if dark else LIGHT)
    tri = '''<path d="M230 830 L230 330 L730 830 Z" fill="#ffffff" fill-opacity=".38" stroke="#ffffff" stroke-width="14" stroke-linejoin="round"/>
<path d="M310 750 L310 520 L540 750 Z" fill="none" stroke="#ffffff" stroke-width="10" stroke-linejoin="round"/>''' + \
        "".join(f'<path d="M230 {y} H{258 if i % 2 else 280}" stroke="#1f49aa" stroke-width="6"/>' for i, y in enumerate(range(380, 820, 40)))
    return svg(d + sdefs, bg + f'<g clip-path="url(#{p}clip)">{sart}{tri}</g>', br)

def parts(p, dark=False):
    # The sunrise put together from UI parts: the sun a round button, the sea three rounded bars like rows.
    d, bg, br = base(p, dark)
    blue = ("#4180f0", "#3268dc", "#2350b8") if not dark else ("#3a5fb8", "#2a4a99", "#1c357a")
    rows = "".join(f'<rect x="{220+i*40}" y="{560+i*96}" width="{584-i*80}" height="72" rx="36" fill="{c}"/>' for i, c in enumerate(blue))
    body = bg + f'''<g clip-path="url(#{p}clip)"><circle cx="512" cy="380" r="150" fill="url(#{p}sun)"/>
<circle cx="512" cy="380" r="150" fill="none" stroke="#fff" stroke-opacity=".55" stroke-width="10"/>{rows}</g>'''
    return svg(d + SUNG.format(p=p), body, br)

designer = [
    ("A Switch", "A switch, the best known UI part: the track is Hatch's sky and sea, the knob is the sun. Says \"the app's components\" at a glance.", toggle, "recommended"),
    ("B Swatches", "A fan of colour cards with the sunrise on the top one: the design system's palette.", swatches, ""),
    ("C Pencil", "Hatch's sunrise being drawn, a pencil finishing the horizon.", pencil, ""),
    ("D Set square", "A drafting triangle over the sunrise.", set_square, ""),
    ("E Made of parts", "The sunrise built from UI parts: a round button for the sun, rounded rows for the sea.", parts, ""),
]

LINE = lambda y, x0=1.5, x1=16.5: f'<path d="M{x0} {y} H{x1}" stroke-width="1.6" stroke-linecap="round" fill="none"/>'
menu = [
    ("A Sun on the horizon", "A half sun on a line. When tickets wait, the sun is filled; at rest it is an outline. Nothing else.",
     g('<path d="M4.4 11.5 A4.6 4.6 0 0 1 13.6 11.5" stroke-width="1.6" fill="none"/>' + LINE(11.5)),
     g(half(9, 11.5, 4.6) + LINE(11.5)), "recommended"),
    ("B The sun rises", "The same shape; when tickets wait the sun has risen a little higher.",
     g(half(9, 12, 4.6) + LINE(12)),
     g('<clipPath id="cb"><rect width="18" height="11.1"/></clipPath><circle cx="9" cy="9.3" r="4.6" stroke="none" clip-path="url(#cb)"/>' + LINE(12)), ""),
    ("C Half disc only", "Just the half sun, no line; filled when tickets wait.",
     g('<path d="M3 13 A6 6 0 0 1 15 13 Z" stroke-width="1.6" fill="none" stroke-linejoin="round"/>'),
     g('<path d="M3 13 A6 6 0 0 1 15 13 Z" stroke="none"/>'), ""),
    ("D Always the same", "One drawing, filled sun on a line, no waiting state in the icon: the panel says what waits.",
     g(half(9, 11.5, 4.6) + LINE(11.5)), g(half(9, 11.5, 4.6) + LINE(11.5)), ""),
]

def icon_row(name, note, fn, tag):
    l, dk = fn(f"{fn.__name__}l"), fn(f"{fn.__name__}d", True)
    sizes = "".join(f'<div class="s" style="width:{s}px;height:{s}px">{l}</div>' for s in (192, 64, 32, 16))
    return (f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="sizes">{sizes}'
            f'<div class="pair"><span>Dark</span><div class="s" style="width:96px;height:96px">{dk}</div></div></div>'
            f'<div class="docks"><div class="dock light"><div>{HATCH_LIGHT}</div><div>{STAGE_L}</div><div>{l}</div></div>'
            f'<div class="dock dark"><div>{HATCH_DARK}</div><div>{STAGE_D}</div><div>{dk}</div></div></div></section>')

WIFI = g('<path d="M2 7 Q9 1 16 7 M4.5 9.6 Q9 5.6 13.5 9.6 M7 12.2 Q9 10.6 11 12.2" fill="none" stroke-width="1.6" stroke-linecap="round"/><circle cx="9" cy="14.6" r="1.3" stroke="none"/>')
def menu_row(name, note, rest, wait, tag):
    bar = lambda bgc, fg, gl: f'<div class="bar" style="background:{bgc};color:{fg}"><span>{gl}</span><span style="opacity:.85">{WIFI}</span><span>Mon 5 Oct 14:02</span></div>'
    col = lambda lab, gl: f'<div><span class="lab">{lab}</span>{bar("#f2f2f4", "#000", gl)}{bar("#2b2b30", "#fff", gl)}<div class="big">{gl}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="menu">{col("At rest", rest)}{col("Tickets wait", wait)}</div></section>'

html = f'''<!doctype html><meta charset="utf-8"><title>Designer and menu bar, round two</title>
<style>body{{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}} main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(460px,1fr));gap:12px}}
section{{background:#fff;border-radius:14px;padding:14px 18px}} h2{{margin:28px 0 8px}} h3{{margin:0 0 4px;font-weight:600}} p{{margin:0 0 10px;color:#555;min-height:2.6em}}
.sizes{{display:flex;align-items:flex-end;gap:14px}} .s svg{{width:100%;height:100%;display:block}} .pair{{margin-left:auto;text-align:center;color:#888;font-size:12px}} .tag{{font-size:12px;font-weight:500;color:#b5651d}}
.docks{{display:flex;gap:10px;margin-top:12px}} .dock{{display:flex;gap:8px;padding:8px 12px;border-radius:18px}} .dock.light{{background:linear-gradient(135deg,#dfe6f4,#f6efe9)}} .dock.dark{{background:linear-gradient(135deg,#1b1f2e,#2c2430)}} .dock div{{width:56px;height:56px}} .dock svg{{width:100%;height:100%}}
.menu{{display:flex;gap:24px}} .bar{{display:flex;align-items:center;gap:14px;height:26px;padding:0 12px;border-radius:6px;margin-bottom:6px;font-size:13px}} .bar span{{display:flex}} .bar svg{{width:18px;height:18px}}
.big{{width:144px;height:144px;background:repeating-conic-gradient(#f3f3f3 0 25%,#fff 0 50%) 0 0/16px 16px;border-radius:8px;color:#000}} .big svg{{width:100%;height:100%}} .lab{{display:block;font-size:12px;color:#888;margin-bottom:4px}}</style>
<h2>Components Designer</h2><main>{"".join(icon_row(*v) for v in designer)}</main>
<h2>Menu bar item</h2><main>{"".join(menu_row(*v) for v in menu)}</main>'''
(HERE / "designer-menubar.html").write_text(html)
print("ok")
