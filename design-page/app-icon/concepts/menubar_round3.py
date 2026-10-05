# Menu bar item, round three: shapes that fill the menu bar's height like the icons around them. Writes menubar-round3.html.
import pathlib
from family_variations import g
HERE = pathlib.Path(__file__).parent

def striped(cid, solid=True):
    # A round sun whose lower half is cut by two gaps that widen downwards: the sun and its reflection in one shape.
    mask = f'<mask id="{cid}"><rect width="18" height="18" fill="#fff"/><rect x="0" y="10.4" width="18" height="1.4" fill="#000"/><rect x="0" y="13.3" width="18" height="1.8" fill="#000"/></mask>'
    if solid:
        return g(mask + f'<circle cx="9" cy="9" r="7.5" stroke="none" mask="url(#{cid})"/>')
    return g('<circle cx="9" cy="9" r="7.5" stroke="none"/>')

def window(filled):
    # A round window with the sun half up inside it, on the horizon.
    sun = '<path d="M5.4 11 A3.6 3.6 0 0 1 12.6 11 Z" stroke="none"/>' if filled else '<path d="M6.15 11 A2.85 2.85 0 0 1 11.85 11" fill="none" stroke-width="1.5"/>'
    return g('<circle cx="9" cy="9" r="7.25" fill="none" stroke-width="1.5"/><path d="M2.5 11 H15.5" stroke-width="1.5" fill="none"/>' + sun)

def tile(filled):
    # Hatch's icon in miniature: a rounded square with the sun on the horizon.
    if filled:
        return g('<mask id="tm"><rect width="18" height="18" fill="#fff"/><path d="M5.6 11.6 A3.4 3.4 0 0 1 12.4 11.6 Z" fill="#000"/><path d="M3 11.6 H15" stroke="#000" stroke-width="1.4"/></mask><rect x="1.5" y="1.5" width="15" height="15" rx="4.2" stroke="none" mask="url(#tm)"/>')
    return g('<rect x="2.25" y="2.25" width="13.5" height="13.5" rx="3.6" fill="none" stroke-width="1.5"/><path d="M5.6 11.6 A3.4 3.4 0 0 1 12.4 11.6 Z" stroke="none"/><path d="M2.5 11.6 H15.5" stroke-width="1.5" fill="none"/>')

def tall(filled):
    # The half sun made taller, so the drawing runs from the top of the menu bar to the bottom.
    sun = '<path d="M2 11 A7 7 0 0 1 16 11 Z" stroke="none"/>' if filled else '<path d="M2.75 11 A6.25 6.25 0 0 1 15.25 11" fill="none" stroke-width="1.5"/>'
    return g(sun + '<path d="M1.5 11 H16.5 M5.5 14.5 H12.5" stroke-width="1.5" stroke-linecap="round" fill="none"/>')

options = [
    ("A Striped sun", "A full round sun, its lower half cut by two gaps that widen downwards: the sun setting into its reflection, as tall as the icons beside it. When tickets wait the gaps close and the sun is whole.",
     striped("sa", True), striped("sb", False), "recommended"),
    ("B Round window", "A circle with the sun half up on the horizon inside it. Outline sun at rest, filled when tickets wait.", window(False), window(True), ""),
    ("C Little tile", "Hatch's icon in miniature: a rounded square with the sun on the horizon; the whole tile fills when tickets wait.", tile(False), tile(True), ""),
    ("D Taller half sun", "Round two's sun made taller with one reflection under the line, so it spans the height. Outline at rest, filled when waiting.", tall(False), tall(True), ""),
]

# Stand-ins for the icons in the owner's menu bar, at the same size, to judge height and weight.
NEIGHBOURS = [
    g('<rect x="2" y="4" width="14" height="10" rx="2.5" fill="none" stroke-width="1.5"/><path d="M5 7.5 H6 M8.5 7.5 H9.5 M12 7.5 H13" stroke-width="1.6" stroke-linecap="round"/>'),
    g('<rect x="2.25" y="2.25" width="13.5" height="13.5" rx="3.5" fill="none" stroke-width="1.5"/>'),
    g('<path d="M9 2 C13 2 16 4.5 16 8 C16 13 12 16 9 16 C6 16 2 13 2 8 C2 4.5 5 2 9 2 Z" fill="none" stroke-width="1.5"/><path d="M9 6 V10 M9 12.2 V12.4" stroke-width="1.6" stroke-linecap="round"/>'),
    g('<path d="M2 7 Q9 1 16 7 M4.5 9.6 Q9 5.6 13.5 9.6 M7 12.2 Q9 10.6 11 12.2" fill="none" stroke-width="1.6" stroke-linecap="round"/><circle cx="9" cy="14.6" r="1.3" stroke="none"/>'),
]

def bar(glyph, dark=True):
    icons = "".join(f'<span>{n}</span>' for n in NEIGHBOURS[:2]) + f'<span class="me">{glyph}</span>' + "".join(f'<span>{n}</span>' for n in NEIGHBOURS[2:])
    style = "background:linear-gradient(90deg,#4a403b,#5e5450);color:#fff" if dark else "background:#ecebef;color:#000"
    return f'<div class="bar" style="{style}">{icons}<span class="clock">Mon 5 Oct 13.51</span></div>'

def row(name, note, rest, wait, tag):
    col = lambda lab, gl: f'<div><span class="lab">{lab}</span>{bar(gl)}{bar(gl, False)}<div class="big">{gl}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="menu">{col("At rest", rest)}{col("Tickets wait", wait)}</div></section>'

html = f'''<!doctype html><meta charset="utf-8"><title>Menu bar item, round three</title>
<style>body{{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}} main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(520px,1fr));gap:12px}}
section{{background:#fff;border-radius:14px;padding:14px 18px}} h3{{margin:0 0 4px;font-weight:600}} p{{margin:0 0 10px;color:#555;min-height:2.6em}} .tag{{font-size:12px;font-weight:500;color:#b5651d}}
.menu{{display:flex;gap:20px}} .bar{{white-space:nowrap;display:flex;align-items:center;gap:16px;height:30px;padding:0 12px;border-radius:6px;margin-bottom:6px;font-size:13px}} .bar span{{display:flex}} .bar svg{{width:18px;height:18px}} .bar .me{{outline:1px dashed rgba(255,160,28,.8);outline-offset:3px;border-radius:3px}}
.big{{width:144px;height:144px;background:repeating-conic-gradient(#f3f3f3 0 25%,#fff 0 50%) 0 0/16px 16px;border-radius:8px;color:#000}} .big svg{{width:100%;height:100%}} .lab{{display:block;font-size:12px;color:#888;margin-bottom:4px}}</style>
<h2>Menu bar item, round three</h2><p>Each new icon has a dashed outline, between stand-ins for the icons in your menu bar, in a dark and a light bar.</p><main>{"".join(row(*o) for o in options)}</main>'''
(HERE / "menubar-round3.html").write_text(html)
print("ok")
