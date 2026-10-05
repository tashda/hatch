# Icon concepts for Stage and the Components Designer, beside Hatch. Writes concepts.html (open it in a browser).
import math, base64, pathlib
HERE = pathlib.Path(__file__).parent
CX = 512
# Hatch's arch, as generate_icon.py draws it.
W, SW, TOP, BOTTOM = 450, 104, 225, 790
RC = (W - SW) / 2; YC = TOP + W / 2; YB = BOTTOM - SW / 2
ARCH = f"M{CX-RC} {YB} V{YC} A{RC} {RC} 0 0 1 {CX+RC} {YC} V{YB}"
DOT = (596, 88)

def tile(p, top, bottom, stroke="rgba(20,40,90,.16)"):
    return f'''<linearGradient id="{p}bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
<filter id="{p}sh" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="14" stdDeviation="14" flood-opacity=".32"/></filter>
<clipPath id="{p}clip"><rect x="100" y="100" width="824" height="824" rx="186"/></clipPath>''', \
f'<rect x="100" y="100" width="824" height="824" rx="186" fill="url(#{p}bg)" filter="url(#{p}sh)"/>', \
f'<rect x="101" y="101" width="822" height="822" rx="185" fill="none" stroke="{stroke}" stroke-width="2"/>'

def grad(id, a, b, y1=TOP, y2=BOTTOM):
    return f'<linearGradient id="{id}" gradientUnits="userSpaceOnUse" x1="0" y1="{y1}" x2="0" y2="{y2}"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>'

DOTG = lambda p: f'<linearGradient id="{p}dt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffc65a"/><stop offset="1" stop-color="#ffa01c"/></linearGradient>'

def svg(defs, body, border):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs>{defs}</defs>{body}{border}</svg>'

def hatch():
    d, bg, br = tile("h", "#ffffff", "#e8edf7")
    return svg(d + grad("har", "#4180f0", "#1f49aa") + DOTG("h"), bg +
        f'<g clip-path="url(#hclip)"><path d="{ARCH}" fill="none" stroke="url(#har)" stroke-width="{SW}" stroke-linecap="round"/><circle cx="512" cy="{DOT[0]}" r="{DOT[1]}" fill="url(#hdt)"/></g>', br)

def small_arch(cx, w, sw, top, bottom):
    rc = (w - sw) / 2; yc = top + w / 2; yb = bottom - sw / 2
    return f"M{cx-rc} {yb} V{yc} A{rc} {rc} 0 0 1 {cx+rc} {yc} V{yb}"

def stage_two_doors(number=None):
    p = "s1" + (number or "")
    d, bg, br = tile(p, "#1f2b4f", "#0d1530", "rgba(255,255,255,.10)")
    left = small_arch(338, 296, 74, 290, 770); right = small_arch(686, 296, 74, 290, 770)
    body = bg + f'''<g clip-path="url(#{p}clip)">
<path d="{left}" fill="none" stroke="#46557f" stroke-width="74" stroke-linecap="round"/>
<path d="{right}" fill="none" stroke="url(#{p}ar)" stroke-width="74" stroke-linecap="round"/>'''
    if number:
        body += f'<text x="512" y="640" text-anchor="middle" font-family="-apple-system, SF Pro Display, Helvetica" font-weight="800" font-size="330" letter-spacing="-14" fill="#fff" stroke="#0d1530" stroke-width="22" paint-order="stroke">{number}</text></g>'
    else:
        body += f'<circle cx="686" cy="612" r="64" fill="url(#{p}dt)"/></g>'
    return svg(d + grad(f"{p}ar", "#6aa2ff", "#2a62d6", 290, 770) + DOTG(p), body, br)

def stage_stack(number=None):
    p = "s4" + (number or "")
    d, bg, br = tile(p, "#1f2b4f", "#0d1530", "rgba(255,255,255,.10)")
    back = small_arch(590, 380, 88, 210, 700); front = small_arch(450, 380, 88, 320, 810)
    body = bg + f'''<g clip-path="url(#{p}clip)">
<path d="{back}" fill="none" stroke="#3e4d78" stroke-width="88" stroke-linecap="round"/>
<path d="{front}" fill="none" stroke="#0f1833" stroke-width="128" stroke-linecap="round"/>
<path d="{front}" fill="none" stroke="url(#{p}ar)" stroke-width="88" stroke-linecap="round"/>'''
    if number:
        body += f'<text x="512" y="660" text-anchor="middle" font-family="-apple-system, SF Pro Display, Helvetica" font-weight="800" font-size="330" letter-spacing="-14" fill="#fff" stroke="#0d1530" stroke-width="22" paint-order="stroke">{number}</text></g>'
    else:
        body += f'<circle cx="450" cy="640" r="64" fill="url(#{p}dt)"/></g>'
    return svg(d + grad(f"{p}ar", "#6aa2ff", "#2a62d6", 320, 810) + DOTG(p), body, br)

def stage_wipe():
    p = "s2"
    d, bg, br = tile(p, "#ffffff", "#e8edf7")
    body = bg + f'''<g clip-path="url(#{p}clip)">
<rect x="512" y="100" width="412" height="824" fill="url(#{p}dark)"/>
<g clip-path="url(#{p}L)"><path d="{ARCH}" fill="none" stroke="url(#{p}ar)" stroke-width="{SW}" stroke-linecap="round"/></g>
<g clip-path="url(#{p}R)"><path d="{ARCH}" fill="none" stroke="url(#{p}arD)" stroke-width="{SW}" stroke-linecap="round"/></g>
<rect x="508" y="100" width="8" height="824" fill="#ffffff" opacity=".9"/>
<circle cx="512" cy="{DOT[0]}" r="{DOT[1]}" fill="url(#{p}dt)" stroke="#fff" stroke-width="10"/></g>'''
    defs = d + grad(f"{p}ar", "#4180f0", "#1f49aa") + grad(f"{p}arD", "#8db8ff", "#4f86f0") + DOTG(p) + \
        grad(f"{p}dark", "#1f2b4f", "#0d1530", 100, 924) + \
        f'<clipPath id="{p}L"><rect x="0" y="0" width="512" height="1024"/></clipPath><clipPath id="{p}R"><rect x="512" y="0" width="512" height="1024"/></clipPath>'
    return svg(defs, body, br)

def stage_curtain():
    p = "s3"
    d, bg, br = tile(p, "#1f2b4f", "#0d1530", "rgba(255,255,255,.10)")
    # Curtains drawn aside inside the arch, a floor, the dot centre stage.
    inner_l, inner_r = CX - RC + SW / 2, CX + RC - SW / 2
    body = bg + f'''<g clip-path="url(#{p}clip)">
<ellipse cx="512" cy="760" rx="210" ry="40" fill="#ffffff" opacity=".10"/>
<path d="M{inner_l} {YC-40} Q{inner_l+120} {YC+20} {inner_l+40} 770 L{inner_l} 770 Z" fill="url(#{p}cu)"/>
<path d="M{inner_r} {YC-40} Q{inner_r-120} {YC+20} {inner_r-40} 770 L{inner_r} 770 Z" fill="url(#{p}cu)"/>
<path d="{ARCH}" fill="none" stroke="url(#{p}ar)" stroke-width="{SW}" stroke-linecap="round"/>
<circle cx="512" cy="640" r="74" fill="url(#{p}dt)"/></g>'''
    return svg(d + grad(f"{p}ar", "#6aa2ff", "#2a62d6") + grad(f"{p}cu", "#3b5fb8", "#22397a", 400, 770) + DOTG(p), body, br)

def annular(r1, r2, a0, a1, cy=YC):
    pt = lambda r, a: (CX + r * math.cos(math.radians(a)), cy - r * math.sin(math.radians(a)))
    (x0, y0), (x1, y1) = pt(r2, a0), pt(r2, a1)
    (x2, y2), (x3, y3) = pt(r1, a1), pt(r1, a0)
    return f"M{x0:.1f} {y0:.1f} A{r2} {r2} 0 0 0 {x1:.1f} {y1:.1f} L{x2:.1f} {y2:.1f} A{r1} {r1} 0 0 1 {x3:.1f} {y3:.1f} Z"

def designer_keystone():
    p = "d1"
    d, bg, br = tile(p, "#ffffff", "#e8edf7")
    r1, r2, gap = RC - SW / 2, RC + SW / 2, "#f3f6fb"
    n = 7; step = 180 / n; blocks = []
    for i in range(n):
        a0, a1 = 180 - i * step, 180 - (i + 1) * step
        key = i == n // 2
        blocks.append(f'<path d="{annular(r1, r2 + (26 if key else 0), a1, a0)}" fill="url(#{p}{"dt" if key else "ar"})" stroke="{gap}" stroke-width="16" stroke-linejoin="round"/>')
    legs = ""
    for x in (CX - r2, CX + r1):
        for y0, y1 in ((YC, 620), (620, BOTTOM - 10)):
            legs += f'<rect x="{x}" y="{y0}" width="{SW}" height="{y1-y0}" fill="url(#{p}ar)" stroke="{gap}" stroke-width="16" stroke-linejoin="round"/>'
    return svg(d + grad(f"{p}ar", "#4180f0", "#1f49aa") + DOTG(p), bg + f'<g clip-path="url(#{p}clip)">{legs}{"".join(blocks)}</g>', br)

def designer_selection():
    p = "d2"
    d, bg, br = tile(p, "#ffffff", "#e8edf7")
    grid = "".join(f'<path d="M{v} 100 V924 M100 {v} H924" stroke="#dbe3f1" stroke-width="3"/>' for v in range(164, 924, 96))
    x0, y0, x1, y1 = CX - W / 2 - 34, TOP - 34, CX + W / 2 + 34, BOTTOM + 34
    handles = "".join(f'<rect x="{x-24}" y="{y-24}" width="48" height="48" rx="8" fill="#fff" stroke="#2f6fe8" stroke-width="8"/>'
                      for x in (x0, CX, x1) for y in (y0, (y0 + y1) / 2, y1) if not (x == CX and y == (y0 + y1) / 2))
    body = bg + f'''<g clip-path="url(#{p}clip)">{grid}
<path d="{ARCH}" fill="none" stroke="url(#{p}ar)" stroke-width="{SW}" stroke-linecap="round"/>
<circle cx="512" cy="{DOT[0]}" r="{DOT[1]}" fill="url(#{p}dt)"/>
<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" fill="none" stroke="#2f6fe8" stroke-width="8"/>{handles}</g>'''
    return svg(d + grad(f"{p}ar", "#4180f0", "#1f49aa") + DOTG(p), body, br)

def designer_blueprint():
    p = "d3"
    d, bg, br = tile(p, "#2a63d8", "#1a3f9e", "rgba(255,255,255,.14)")
    fine = "".join(f'<path d="M{v} 100 V924 M100 {v} H924" stroke="#ffffff" stroke-opacity=".08" stroke-width="2"/>' for v in range(132, 924, 32))
    major = "".join(f'<path d="M{v} 100 V924 M100 {v} H924" stroke="#ffffff" stroke-opacity=".16" stroke-width="3"/>' for v in range(228, 924, 128))
    out = small_arch(CX, W, 8, TOP, BOTTOM)
    inner = small_arch(CX, W - 2 * SW, 8, TOP + SW, BOTTOM)
    dim = f'<path d="M{CX-W/2} 865 H{CX+W/2} M{CX-W/2} 845 V885 M{CX+W/2} 845 V885" stroke="#fff" stroke-opacity=".7" stroke-width="6"/>'
    body = bg + f'''<g clip-path="url(#{p}clip)">{fine}{major}
<path d="{ARCH}" fill="none" stroke="#ffffff" stroke-opacity=".14" stroke-width="{SW}" stroke-linecap="round"/>
<path d="{out}" fill="none" stroke="#fff" stroke-width="10"/><path d="{inner}" fill="none" stroke="#fff" stroke-width="10"/>
<path d="M{CX} {YC} m-{RC+80} 0 h{2*RC+160}" stroke="#fff" stroke-opacity=".45" stroke-width="4" stroke-dasharray="18 14"/>
{dim}<circle cx="512" cy="{DOT[0]}" r="{DOT[1]}" fill="url(#{p}dt)"/></g>'''
    return svg(d + DOTG(p), body, br)

def png(path):
    return f'<img src="data:image/png;base64,{base64.b64encode(pathlib.Path(path).read_bytes()).decode()}">'

def row(name, note, art, tag=""):
    sizes = "".join(f'<div class="s" style="width:{s}px;height:{s}px">{art}</div>' for s in (256, 128, 64, 32, 16))
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="sizes">{sizes}</div></section>'

if __name__ == "__main__":
    import sys
    stage_today = png(sys.argv[1]) if len(sys.argv) > 1 else ""
    stage_number = png(sys.argv[2]) if len(sys.argv) > 2 else ""
    html = f'''<!doctype html><meta charset="utf-8"><title>Icon concepts</title>
    <style>body{{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}} h2{{margin:32px 0 8px}} section{{background:#fff;border-radius:14px;padding:16px 20px;margin:12px 0}}
    h3{{margin:0 0 4px;font-weight:600}} p{{margin:0 0 12px;color:#555}} .sizes{{display:flex;align-items:flex-end;gap:20px}} .s img,.s svg{{width:100%;height:100%;display:block}}
    .dock{{display:flex;gap:10px;padding:10px 16px;border-radius:22px;background:rgba(255,255,255,.55);width:max-content}} .dock div{{width:72px;height:72px}} .dockwrap{{padding:28px;border-radius:14px;background:linear-gradient(135deg,#6a7fb5,#c9a7a0)}}
    .tag{{font-size:12px;font-weight:500;color:#b5651d}} .dark{{background:#1e1e1e}}</style>
    <h2>Today</h2>
    {row("Hatch", "Doorway arch, warm dot, light tile. Keep.", hatch())}
    {row("Stage (source today)", "Stepped arches, a tunnel. At 32 px and below it is a blue blob with a dot; the arches repeat Hatch's.", stage_today)}
    <h2>Stage</h2>
    {row("S1 Two doors, stacked", "Two arches, one behind the other: the one in front is lit and holds the dot. Options, one picked. The dark tile tells it apart from Hatch.", stage_stack(), "recommended")}
    {row("S1 with a ticket number", "The running Stage's Dock tile: the number over the doors.", stage_stack("151"))}
    {row("S1a Two doors, side by side", "The same idea flat. Reads as the letters nA, so not this one.", stage_two_doors())}
    {row("S2 Wipe", "Hatch's own icon, cut down the middle: light on one side, dark on the other, the dot is the wipe handle.", stage_wipe())}
    {row("S3 Curtain", "Hatch's arch as a proscenium with the curtains open, the dot centre stage.", stage_curtain())}
    <h2>Components Designer</h2>
    {row("D1 Keystone", "Hatch's arch built from blocks, the keystone orange. A design system is pieces that hold each other up.", designer_keystone(), "recommended")}
    {row("D2 Selection", "Hatch's icon on a grid with selection handles, as in a design tool.", designer_selection())}
    {row("D3 Blueprint", "Hatch's arch as a construction drawing on blueprint blue.", designer_blueprint())}
    <h2>Together in a Dock</h2>
    <div class="dockwrap"><div class="dock"><div>{hatch()}</div><div>{stage_stack()}</div><div>{designer_keystone()}</div></div></div>
    <div class="dockwrap" style="margin-top:12px"><div class="dock"><div>{hatch()}</div><div>{stage_wipe()}</div><div>{designer_selection()}</div></div></div>
    '''
    (HERE / "concepts.html").write_text(html)
    print(HERE / "concepts.html")
