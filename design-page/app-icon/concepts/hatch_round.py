# New ideas for Hatch's own icon, each in a Dock with the Stage (S8) and the Designer (D3). Writes hatch-ideas.html.
import math, pathlib
from make_concepts import tile, grad, DOTG, svg, hatch, designer_blueprint
from stage_round2 import loupe
HERE = pathlib.Path(__file__).parent
FONT = 'font-family="-apple-system, SF Pro Rounded, SF Pro Display, Helvetica" font-weight="800"'

def egg_points(cx, cy, a, b, k=0.16, n=160):
    return [(cx + a * math.cos(t) * (1 - k * math.sin(t)), cy - b * math.sin(t)) for t in (2 * math.pi * i / n for i in range(n))]

def split_egg():
    # A flat egg opening along a zigzag, warm light coming out of the crack: something about to hatch.
    p = "e"
    d, bg, br = tile(p, "#1f2b4f", "#0d1530", "rgba(255,255,255,.10)")
    pts = egg_points(512, 560, 230, 290)
    zig = [(250, 560), (320, 520), (380, 575), (450, 515), (512, 575), (574, 515), (644, 575), (704, 520), (774, 560)]
    top = [q for q in pts if q[1] < 545]
    bottom = [q for q in pts if q[1] >= 545]
    def poly(ps): return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in ps) + " Z"
    upper = poly(sorted(top, key=lambda q: math.atan2(-(q[1] - 560), q[0] - 512)) + [])  # outline order
    body = bg + f'''<g clip-path="url(#{p}clip)">
<clipPath id="{p}egg"><path d="{poly(pts)}"/></clipPath>
<ellipse cx="512" cy="560" rx="300" ry="120" fill="url(#{p}glow)"/>
<g clip-path="url(#{p}egg)">
  <path d="M0 1024 V{zig[0][1]} {' '.join(f'L{x} {y}' for x, y in zig)} L1024 {zig[-1][1]} V1024 Z" fill="url(#{p}shell)"/>
</g>
<g transform="translate(0 -70) rotate(-8 512 520)" clip-path="url(#{p}egg)">
  <path d="M0 0 V{zig[0][1]} {' '.join(f'L{x} {y}' for x, y in zig)} L1024 {zig[-1][1]} V0 Z" fill="url(#{p}shell)"/>
</g></g>'''
    defs = d + grad(f"{p}shell", "#ffffff", "#dfe6f4", 270, 850) + \
        f'<radialGradient id="{p}glow"><stop offset="0" stop-color="#ffc65a"/><stop offset=".55" stop-color="#ffa01c" stop-opacity=".55"/><stop offset="1" stop-color="#ffa01c" stop-opacity="0"/></radialGradient>'
    return svg(defs, body, br)

def hatching():
    # Hatching, the drawing kind: a ball made of parallel pen strokes, one of them orange. Ideas taking shape.
    p = "hl"
    d, bg, br = tile(p, "#ffffff", "#e8edf7")
    cx, cy, r, gap, sw = 512, 512, 290, 82, 50
    lines = ""
    for i in range(-3, 4):
        off = i * gap
        half = math.sqrt(max(r * r - off * off, 0))
        # Diagonal at 45 degrees: the stroke's centre is offset along (1, 1)/sqrt2.
        ox, oy = off / math.sqrt(2), off / math.sqrt(2)
        dx, dy = half / math.sqrt(2), half / math.sqrt(2)
        col = f"url(#{p}dt)" if i == 1 else f"url(#{p}ar)"
        lines += f'<path d="M{cx+ox-dx:.1f} {cy+oy+dy:.1f} L{cx+ox+dx:.1f} {cy+oy-dy:.1f}" stroke="{col}" stroke-width="{sw}" stroke-linecap="round"/>'
    return svg(d + grad(f"{p}ar", "#4180f0", "#1f49aa", 220, 800) + grad(f"{p}dt", "#ffc65a", "#ffa01c", 220, 800), bg + f'<g clip-path="url(#{p}clip)">{lines}</g>', br)

def hash_sign():
    # The # of a ticket number, drawn as four rounded bars; the one that crosses last is orange.
    p = "hs"
    d, bg, br = tile(p, "#ffffff", "#e8edf7")
    sw = 96
    bars = f'''<path d="M430 250 L370 774" stroke="url(#{p}ar)" stroke-width="{sw}" stroke-linecap="round"/>
<path d="M654 250 L594 774" stroke="url(#{p}ar)" stroke-width="{sw}" stroke-linecap="round"/>
<path d="M270 404 H770" stroke="url(#{p}ar)" stroke-width="{sw}" stroke-linecap="round"/>
<path d="M254 620 H754" stroke="url(#{p}dt)" stroke-width="{sw}" stroke-linecap="round"/>'''
    return svg(d + grad(f"{p}ar", "#4180f0", "#1f49aa", 250, 774) + grad(f"{p}dt", "#ffc65a", "#ffa01c", 572, 668), bg + f'<g clip-path="url(#{p}clip)">{bars}</g>', br)

def porthole():
    # A hatch, the door kind: a round hatch swung open with warm light inside.
    p = "ph"
    d, bg, br = tile(p, "#1f2b4f", "#0d1530", "rgba(255,255,255,.10)")
    bolts = "".join(f'<circle cx="{440+240*math.cos(math.radians(a)):.1f}" cy="{590+240*math.sin(math.radians(a)):.1f}" r="16" fill="#9fb4dd"/>' for a in range(0, 360, 45))
    body = bg + f'''<g clip-path="url(#{p}clip)">
<circle cx="440" cy="590" r="200" fill="url(#{p}light)"/>
<circle cx="440" cy="590" r="240" fill="none" stroke="url(#{p}ring)" stroke-width="80"/>{bolts}
<g transform="rotate(-35 700 360)"><ellipse cx="730" cy="380" rx="80" ry="215" fill="url(#{p}lid)"/><ellipse cx="730" cy="380" rx="48" ry="170" fill="none" stroke="#ffffff" stroke-opacity=".25" stroke-width="10"/></g></g>'''
    defs = d + f'<radialGradient id="{p}light" cx=".5" cy=".55" r=".6"><stop offset="0" stop-color="#ffe2a0"/><stop offset=".6" stop-color="#ffb43c"/><stop offset="1" stop-color="#f08a10"/></radialGradient>' + \
        grad(f"{p}ring", "#6aa2ff", "#2a62d6", 310, 810) + grad(f"{p}lid", "#4f86f0", "#1f49aa", 80, 580)
    return svg(defs, body, br)

def sunrise():
    # Rising: the orange dot coming up over a blue horizon. The plainest way to say something new is coming.
    p = "sr"
    d, bg, br = tile(p, "#ffffff", "#e8edf7")
    body = bg + f'''<g clip-path="url(#{p}clip)">
<circle cx="512" cy="590" r="200" fill="url(#{p}dt)"/>
<rect x="100" y="590" width="824" height="334" fill="url(#{p}ar)"/>
<path d="M330 690 H694 M400 770 H624" stroke="#ffffff" stroke-opacity=".35" stroke-width="28" stroke-linecap="round"/></g>'''
    return svg(d + grad(f"{p}ar", "#4180f0", "#1f49aa", 590, 924) + grad(f"{p}dt", "#ffd27a", "#ffa01c", 390, 590), body, br)

def phases():
    # Five phases as five steps up, the last one orange: from a question to something shipped.
    p = "st"
    d, bg, br = tile(p, "#ffffff", "#e8edf7")
    bars = ""
    for i in range(5):
        x = 232 + i * 128; h = 140 + i * 105
        col = f"url(#{p}dt)" if i == 4 else f"url(#{p}ar)"
        bars += f'<rect x="{x}" y="{780-h}" width="88" height="{h}" rx="44" fill="{col}"/>'
    return svg(d + grad(f"{p}ar", "#4180f0", "#1f49aa", 240, 780) + grad(f"{p}dt", "#ffc65a", "#ffa01c", 240, 780), bg + f'<g clip-path="url(#{p}clip)">{bars}</g>', br)

def row(name, note, art, tag=""):
    sizes = "".join(f'<div class="s" style="width:{s}px;height:{s}px">{art}</div>' for s in (256, 128, 64, 32, 16))
    dock = f'<div class="dockwrap"><div class="dock"><div>{art}</div><div>{loupe()}</div><div>{designer_blueprint()}</div></div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="sizes">{sizes}{dock}</div></section>'

ideas = [
    ("Today", "The doorway arch and the dot. The Stage and the Designer both carry this arch, so a new Hatch mark would move into the lens and the blueprint too.", hatch(), ""),
    ("H1 Split egg", "A flat egg opening along a zigzag, warm light from the crack. The name, said plainly, without the realistic shell of the earlier try.", split_egg(), "recommended"),
    ("H2 Hatching", "Hatching as in drawing: a ball made of parallel pen strokes, one of them orange. A design tool's pun on the name.", hatching(), ""),
    ("H3 Hash", "The # of a ticket number, with the last bar orange. Tickets are what Hatch is made of.", hash_sign(), ""),
    ("H4 Open hatch", "A round hatch swung open, light inside: the door kind of hatch.", porthole(), ""),
    ("H5 Sunrise", "The orange dot rising over a blue horizon: something new coming up.", sunrise(), ""),
    ("H6 Five steps", "Hatch's five phases as steps up, the last one orange: a question becomes something shipped. Reads as signal bars, though.", phases(), ""),
]
html = f'''<!doctype html><meta charset="utf-8"><title>Hatch icon ideas</title>
<style>body{{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}} section{{background:#fff;border-radius:14px;padding:16px 20px;margin:12px 0}}
h3{{margin:0 0 4px;font-weight:600}} p{{margin:0 0 12px;color:#555}} .sizes{{display:flex;align-items:flex-end;gap:18px;flex-wrap:wrap}} .s svg{{width:100%;height:100%;display:block}}
.dock{{display:flex;gap:8px;padding:8px 12px;border-radius:18px;background:rgba(255,255,255,.55)}} .dock div{{width:56px;height:56px}} .dock svg{{width:100%;height:100%}} .dockwrap{{padding:14px;border-radius:12px;background:linear-gradient(135deg,#6a7fb5,#c9a7a0);margin-left:auto}}
.tag{{font-size:12px;font-weight:500;color:#b5651d}}</style>
<h2>Hatch, new ideas</h2>{"".join(row(*i) for i in ideas)}'''
(HERE / "hatch-ideas.html").write_text(html)
print("ok")
