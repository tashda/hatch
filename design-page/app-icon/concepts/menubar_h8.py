# Menu bar item, round nine: polishing H8 (a solid tile with the orange sun in a cut-out circle). Writes menubar-h8.html.
import pathlib
from family_variations import g
from menubar_round3 import bar
from menubar_soft import TILE, sun as peek_sun
HERE = pathlib.Path(__file__).parent
n = 0
TILE_R = 4.4

def nid():
    global n
    n += 1
    return f"j{n}"

def sun_fill(i, kind):
    if kind == "jewel":
        return (f'<radialGradient id="{i}s" cx="0.36" cy="0.3" r="0.8"><stop offset="0" stop-color="#ffe7ad"/><stop offset=".45" stop-color="#ffb43c"/>'
                f'<stop offset="1" stop-color="#f08400"/></radialGradient>')
    if kind == "deep":
        return f'<linearGradient id="{i}s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffc24d"/><stop offset="1" stop-color="#ff8a00"/></linearGradient>'
    return f'<linearGradient id="{i}s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffd27a"/><stop offset="1" stop-color="#ffa01c"/></linearGradient>'

def h8(r=4.0, gap=1.1, cy=9.0, tile_opacity=1.0, kind="flat", corona=False, tile_fill="currentColor", tile_grad=None, extra_cut="", extra_sun=""):
    i = nid()
    defs = sun_fill(i, kind)
    if tile_grad:
        defs += f'<linearGradient id="{i}t" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{tile_grad[0]}"/><stop offset="1" stop-color="{tile_grad[1]}"/></linearGradient>'
        tile_fill = f"url(#{i}t)"
    cut = f'<circle cx="9" cy="{cy}" r="{r+gap+(1.4 if corona else 0)}" fill="#000"/>' + extra_cut
    body = (f'<mask id="{i}m"><rect width="18" height="18" fill="#fff"/>{cut}</mask>'
            f'<rect x="1.5" y="1.5" width="15" height="15" rx="{TILE_R}" stroke="none" fill="{tile_fill}" fill-opacity="{tile_opacity}" mask="url(#{i}m)"/>')
    if corona:
        body += f'<circle cx="9" cy="{cy}" r="{r+gap+0.5}" fill="none" stroke="#ffa01c" stroke-opacity=".75" stroke-width="0.8"/>'
    body += f'<circle cx="9" cy="{cy}" r="{r}" fill="url(#{i}s)" stroke="none"/>' + extra_sun.replace("SUN", f"url(#{i}s)")
    return g(defs + body)

def sunrise_negative():
    # Hatch's icon cut out of the solid tile: the half sun on a horizon, orange, with two orange reflection dashes.
    i = nid()
    defs = sun_fill(i, "flat")
    cut = ('<path d="M4.2 11 A4.8 4.8 0 0 1 13.8 11 Z" fill="#000"/><rect x="3.4" y="10.6" width="11.2" height="1.1" fill="#000"/>'
           '<path d="M6.2 13.4 H11.8 M7.6 15.0 H10.4" stroke="#000" stroke-width="1.8" stroke-linecap="round"/>')
    body = (f'<mask id="{i}m"><rect width="18" height="18" fill="#fff"/>{cut}</mask>'
            f'<rect x="1.5" y="1.5" width="15" height="15" rx="{TILE_R}" stroke="none" mask="url(#{i}m)"/>'
            f'<path d="M5.2 10.5 A3.8 3.8 0 0 1 12.8 10.5 Z" fill="url(#{i}s)" stroke="none"/>'
            f'<path d="M6.9 13.4 H11.1 M8.1 15.0 H9.9" stroke="#ffa01c" stroke-width=".9" stroke-linecap="round"/>')
    return g(defs + body)

REFLECT_CUT = '<path d="M6.6 14.3 H11.4" stroke="#000" stroke-width="1.9" stroke-linecap="round"/>'
REFLECT_SUN = '<path d="M7.3 14.3 H10.7" stroke="#ffaa2a" stroke-width="1.0" stroke-linecap="round"/>'

PEEK = g(TILE.format(o=.32) + peek_sun(18.6, 5.4))
def soft_cut_rest():
    i = nid()
    return g(f'<mask id="{i}m"><rect width="18" height="18" fill="#fff"/><circle cx="9" cy="9" r="5.1" fill="#000"/></mask>'
             f'<rect x="1.5" y="1.5" width="15" height="15" rx="{TILE_R}" stroke="none" fill-opacity=".32" mask="url(#{i}m)"/><circle cx="9" cy="9" r="4" stroke="none" fill-opacity=".55"/>')

options = [
    ("H8 as it was", "For comparison.", PEEK, h8(r=3.8, gap=1.3, tile_opacity=.85), ""),
    ("J1 Refined", "A fully solid tile with softer corners, a slightly bigger sun and a finer gap. Cleaner edges at 18 pt.", PEEK, h8(), "recommended"),
    ("J2 Jewel sun", "The same, with light falling on the sun from the top left: it looks round, like a small orange marble. No glow outside it.", PEEK, h8(kind="jewel"), ""),
    ("J3 Corona", "A thin orange ring in the gap around the sun, like a corona.", PEEK, h8(r=3.5, gap=0.9, corona=True), ""),
    ("J4 Sun and reflection", "The sun a little higher, one orange reflection under it, both cut into the tile: Hatch's icon in miniature.", PEEK,
     h8(r=3.4, gap=1.0, cy=7.6, extra_cut=REFLECT_CUT, extra_sun=REFLECT_SUN), ""),
    ("J5 Sunrise in negative", "Hatch's own icon cut out of the solid tile: half sun on the horizon, two reflection lines.", PEEK, sunrise_negative(), ""),
    ("J6 Bold", "A bigger sun and the finest gap: the most orange.", PEEK, h8(r=4.7, gap=0.8, kind="deep"), ""),
    ("J7 Navy tile", "The tile in the Stage's navy instead of the menu bar's colour: the family's colours together. Same on light and dark bars.", PEEK,
     h8(tile_grad=("#2a3a66", "#141d3d"), kind="jewel"), ""),
    ("J8 Matching rest", "J1 with a resting state built the same way: the soft tile with a grey sun in a cut-out circle. Waiting, the tile and sun come alive.",
     soft_cut_rest(), h8(), ""),
]

def row(name, note, rest, wait, tag):
    col = lambda lab, gl: f'<div><span class="lab">{lab}</span>{bar(gl)}{bar(gl, False)}<div class="big">{gl}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="menu">{col("At rest", rest)}{col("Tickets wait", wait)}</div></section>'

head = (HERE / "menubar-round3.html").read_text().split("<h2>")[0].replace("round three", "round nine")
html = head + f'<h2>Menu bar item: polishing H8</h2><p>Each icon has a dashed outline, between stand-ins for the icons in your menu bar.</p><main>{"".join(row(*o) for o in options)}</main>'
(HERE / "menubar-h8.html").write_text(html)
print("ok")
