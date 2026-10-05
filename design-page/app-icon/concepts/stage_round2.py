# Stage icon, round two: new metaphors, each beside Hatch and D3 (the Designer's pick). Writes stage-round2.html.
import math, pathlib
from make_concepts import tile, grad, DOTG, svg, small_arch, hatch, designer_blueprint, ARCH, SW, CX, RC, YC, W, TOP, BOTTOM
HERE = pathlib.Path(__file__).parent
NAVY = ("#1f2b4f", "#0d1530", "rgba(255,255,255,.10)")
FONT = 'font-family="-apple-system, SF Pro Display, Helvetica" font-weight="800"'

def ticket(number=None):
    # A theatre ticket: Hatch's arch printed on it, the stub torn off at a perforation; the stub carries the ticket number.
    p = "t" + (number or "")
    d, bg, br = tile(p, *NAVY)
    x0, y0, x1, y1, notch, cut = 190, 300, 834, 724, 46, 640
    body_path = (f"M{x0+40} {y0} H{x1-40} Q{x1} {y0} {x1} {y0+40} V{(y0+y1)/2-notch} A{notch} {notch} 0 0 0 {x1} {(y0+y1)/2+notch} "
                 f"V{y1-40} Q{x1} {y1} {x1-40} {y1} H{x0+40} Q{x0} {y1} {x0} {y1-40} V{(y0+y1)/2+notch} "
                 f"A{notch} {notch} 0 0 0 {x0} {(y0+y1)/2-notch} V{y0+40} Q{x0} {y0} {x0+40} {y0} Z")
    holes = "".join(f'<circle cx="{cut}" cy="{y}" r="10" fill="#aab8d4"/>' for y in range(y0 + 36, y1 - 20, 44))
    arch = small_arch(400, 250, 58, 370, 660)
    stub = (f'<text x="{(cut+x1)/2}" y="{(y0+y1)/2+40}" text-anchor="middle" {FONT} font-size="{120 if number and len(number) > 2 else 150}" fill="#1f49aa" '
            f'transform="rotate(-90 {(cut+x1)/2} {(y0+y1)/2})">{number}</text>') if number else \
           f'<circle cx="{(cut+x1)/2}" cy="{(y0+y1)/2}" r="52" fill="url(#{p}dt)"/>'
    body = bg + f'''<g clip-path="url(#{p}clip)"><g transform="rotate(-12 512 512)">
<path d="{body_path}" fill="url(#{p}paper)"/>{holes}
<path d="{arch}" fill="none" stroke="url(#{p}ar)" stroke-width="58" stroke-linecap="round"/>
<circle cx="400" cy="585" r="44" fill="url(#{p}dt)"/>{stub}</g></g>'''
    return svg(d + grad(f"{p}ar", "#4180f0", "#1f49aa", 370, 660) + DOTG(p) + grad(f"{p}paper", "#ffffff", "#dfe6f4", 300, 724), body, br)

def matrix(number=None):
    # Four options in a grid, one picked: the Stage's matrix mode.
    p = "m" + (number or "")
    d, bg, br = tile(p, *NAVY)
    cells = ""
    for i, (x, y) in enumerate([(220, 220), (532, 220), (220, 532), (532, 532)]):
        picked = i == 1
        fill = f"url(#{p}ar)" if picked else "#2c3a66"
        cells += f'<rect x="{x}" y="{y}" width="272" height="272" rx="56" fill="{fill}"/>'
        if not picked:
            cells += f'<path d="{small_arch(x+136, 120, 30, y+80, y+200)}" fill="none" stroke="#4a5b8c" stroke-width="30" stroke-linecap="round"/>'
    mark = f'<text x="668" y="420" text-anchor="middle" {FONT} font-size="{150 if number and len(number) > 2 else 190}" fill="#fff">{number}</text>' if number else \
           f'<path d="{small_arch(668, 150, 36, 296, 432)}" fill="none" stroke="#fff" stroke-width="36" stroke-linecap="round"/><circle cx="668" cy="392" r="30" fill="url(#{p}dt)"/>'
    return svg(d + grad(f"{p}ar", "#6aa2ff", "#2a62d6", 220, 492) + DOTG(p), bg + f'<g clip-path="url(#{p}clip)">{cells}{mark}</g>', br)

def slider():
    # Before and after: a frame with a divider and a round handle, the gesture every Mac user knows for comparing.
    p = "sl"
    d, bg, br = tile(p, "#ffffff", "#e8edf7")
    fx0, fy0, fx1, fy1 = 200, 250, 824, 774
    body = bg + f'''<g clip-path="url(#{p}clip)">
<clipPath id="{p}f"><rect x="{fx0}" y="{fy0}" width="{fx1-fx0}" height="{fy1-fy0}" rx="70"/></clipPath>
<g clip-path="url(#{p}f)"><rect x="{fx0}" y="{fy0}" width="{512-fx0}" height="{fy1-fy0}" fill="#cfdcf3"/>
<rect x="512" y="{fy0}" width="{fx1-512}" height="{fy1-fy0}" fill="url(#{p}ar)"/></g>
<rect x="500" y="200" width="24" height="624" rx="12" fill="#fff"/>
<circle cx="512" cy="512" r="104" fill="url(#{p}dt)" stroke="#fff" stroke-width="20"/>
<path d="M478 470 L440 512 L478 554 M546 470 L584 512 L546 554" fill="none" stroke="#fff" stroke-width="22" stroke-linecap="round" stroke-linejoin="round"/></g>'''
    return svg(d + grad(f"{p}ar", "#4180f0", "#1f49aa", 250, 774) + DOTG(p), body, br)

def loupe():
    # A loupe over Hatch's arch: the Stage is where you look closely before you decide.
    p = "lp"
    d, bg, br = tile(p, *NAVY)
    lens_c, lens_r = (470, 470), 220
    body = bg + f'''<g clip-path="url(#{p}clip)">
<path d="M{lens_c[0]+150} {lens_c[1]+150} L770 770" stroke="url(#{p}hd)" stroke-width="92" stroke-linecap="round"/>
<circle cx="{lens_c[0]}" cy="{lens_c[1]}" r="{lens_r}" fill="#e9effa"/>
<clipPath id="{p}lens"><circle cx="{lens_c[0]}" cy="{lens_c[1]}" r="{lens_r}"/></clipPath>
<g clip-path="url(#{p}lens)"><path d="{small_arch(470, 300, 70, 330, 760)}" fill="none" stroke="url(#{p}ar)" stroke-width="70" stroke-linecap="round"/>
<circle cx="470" cy="560" r="58" fill="url(#{p}dt)"/></g>
<circle cx="{lens_c[0]}" cy="{lens_c[1]}" r="{lens_r}" fill="none" stroke="#c9d6f0" stroke-width="34"/></g>'''
    return svg(d + grad(f"{p}ar", "#4180f0", "#1f49aa", 330, 700) + grad(f"{p}hd", "#ffc65a", "#ff9a10", 620, 770) + DOTG(p), body, br)

def velvet():
    # A real theatre: deep velvet curtains with a swag, the arch lit centre stage on the boards.
    p = "v"
    d, bg, br = tile(p, "#2a0f1c", "#12060c", "rgba(255,255,255,.10)")
    folds_l = "".join(f'<path d="M{100+i*46} 100 Q{120+i*46} 420 {150+i*36} 700" stroke="#000" stroke-opacity=".22" stroke-width="10" fill="none"/>' for i in range(5))
    folds_r = "".join(f'<path d="M{924-i*46} 100 Q{904-i*46} 420 {874-i*36} 700" stroke="#000" stroke-opacity=".22" stroke-width="10" fill="none"/>' for i in range(5))
    body = bg + f'''<g clip-path="url(#{p}clip)">
<path d="M100 790 H924 V924 H100 Z" fill="#3a1a12"/><path d="M100 790 H924" stroke="#6b3a22" stroke-width="10"/>
<ellipse cx="512" cy="790" rx="230" ry="44" fill="#ffd27a" opacity=".35"/>
<path d="{small_arch(512, 280, 66, 420, 800)}" fill="none" stroke="url(#{p}ar)" stroke-width="66" stroke-linecap="round"/>
<circle cx="512" cy="680" r="54" fill="url(#{p}dt)"/>
<path d="M100 100 H360 Q330 440 400 700 Q260 720 100 690 Z" fill="url(#{p}cu)"/>{folds_l}
<path d="M924 100 H664 Q694 440 624 700 Q764 720 924 690 Z" fill="url(#{p}cu)"/>{folds_r}
<path d="M100 100 H924 V190 Q812 260 700 190 Q606 260 512 190 Q418 260 324 190 Q212 260 100 190 Z" fill="url(#{p}sw)"/>
<path d="M100 214 Q212 284 324 214 Q418 284 512 214 Q606 284 700 214 Q812 284 924 214" stroke="#ffb340" stroke-width="10" fill="none"/></g>'''
    return svg(d + grad(f"{p}ar", "#6aa2ff", "#2a62d6", 420, 800) + DOTG(p) + grad(f"{p}cu", "#d0324a", "#7a1426", 100, 700) + grad(f"{p}sw", "#e04358", "#9e1b30", 100, 260), body, br)

def spotlights():
    # Two beams from above, one on a dim arch and one on the lit arch with the dot: candidates under the lights.
    p = "sp"
    d, bg, br = tile(p, "#141c38", "#070b1c", "rgba(255,255,255,.10)")
    body = bg + f'''<g clip-path="url(#{p}clip)">
<path d="M250 100 L320 100 L450 790 L150 790 Z" fill="url(#{p}beamD)"/>
<path d="M704 100 L774 100 L874 790 L574 790 Z" fill="url(#{p}beam)"/>
<ellipse cx="300" cy="790" rx="150" ry="30" fill="#ffffff" opacity=".08"/><ellipse cx="724" cy="790" rx="150" ry="30" fill="#ffe2a0" opacity=".30"/>
<path d="{small_arch(300, 210, 52, 470, 790)}" fill="none" stroke="#3a4870" stroke-width="52" stroke-linecap="round"/>
<path d="{small_arch(724, 210, 52, 470, 790)}" fill="none" stroke="url(#{p}ar)" stroke-width="52" stroke-linecap="round"/>
<circle cx="724" cy="690" r="46" fill="url(#{p}dt)"/></g>'''
    defs = d + grad(f"{p}ar", "#7fb0ff", "#2a62d6", 470, 790) + DOTG(p) + \
        f'<linearGradient id="{p}beam" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff2cc" stop-opacity=".05"/><stop offset="1" stop-color="#fff2cc" stop-opacity=".45"/></linearGradient>' + \
        f'<linearGradient id="{p}beamD" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity=".02"/><stop offset="1" stop-color="#ffffff" stop-opacity=".10"/></linearGradient>'
    return svg(defs, body, br)

def row(name, note, art, tag=""):
    sizes = "".join(f'<div class="s" style="width:{s}px;height:{s}px">{art}</div>' for s in (256, 128, 64, 32, 16))
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="sizes">{sizes}</div></section>'

def dock(stage):
    return f'<div class="dockwrap"><div class="dock"><div>{hatch()}</div><div>{stage}</div><div>{designer_blueprint()}</div></div></div>'

ideas = [
    ("S5 Ticket", "A theatre ticket with Hatch's arch printed on it. Hatch is built on tickets and the Stage is the show; the stub is where the running Stage puts the ticket number.", ticket(), ticket("151"), "recommended"),
    ("S6 Matrix", "Four options in a grid, one picked and lit. The Stage's matrix mode; the number replaces the arch in the picked cell.", matrix(), matrix("151"), ""),
    ("S7 Before and after", "A frame cut in two with the round handle you drag to compare. The best known compare symbol; the handle is Hatch's orange dot.", slider(), None, ""),
    ("S8 Loupe", "A loupe over Hatch's arch: the place you look closely before you decide.", loupe(), None, ""),
    ("S9 Velvet curtains", "A real theatre: red velvet, a gold swag, the arch lit on the boards. Unmistakably a stage, and the only red icon in the family.", velvet(), None, ""),
    ("S10 Two spotlights", "Two candidates under the lights; the lit one holds the dot.", spotlights(), None, ""),
]
sections = ""
for name, note, art, numbered, tag in ideas:
    sections += row(name, note, art, tag)
    if numbered: sections += row(name + " with a ticket number", "The running Stage's Dock tile.", numbered)
html = f'''<!doctype html><meta charset="utf-8"><title>Stage icon, round two</title>
<style>body{{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}} h2{{margin:32px 0 8px}} section{{background:#fff;border-radius:14px;padding:16px 20px;margin:12px 0}}
h3{{margin:0 0 4px;font-weight:600}} p{{margin:0 0 12px;color:#555}} .sizes{{display:flex;align-items:flex-end;gap:20px}} .s svg{{width:100%;height:100%;display:block}}
.dock{{display:flex;gap:10px;padding:10px 16px;border-radius:22px;background:rgba(255,255,255,.55);width:max-content}} .dock div{{width:72px;height:72px}} .dockwrap{{padding:20px;border-radius:14px;background:linear-gradient(135deg,#6a7fb5,#c9a7a0);display:inline-block;margin:6px}}
.tag{{font-size:12px;font-weight:500;color:#b5651d}}</style>
<h2>Stage, round two</h2>{sections}
<h2>Each beside Hatch and D3 in a Dock</h2>{"".join(dock(i[2]) for i in ideas)}'''
(HERE / "stage-round2.html").write_text(html)
print("ok")
