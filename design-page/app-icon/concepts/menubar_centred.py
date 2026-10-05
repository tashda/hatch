# Menu bar item, round eight: G with the sun centred and no glow. Writes menubar-centred.html.
import pathlib
from family_variations import g
from menubar_round3 import bar
from menubar_soft import TILE, sun
HERE = pathlib.Path(__file__).parent
n = 0

def orange(r, cy=9.0, cut=False, tint=None, solid_tile=False):
    """A flat orange sun (the app icon's top-to-bottom gradient, no glow) in the middle of the soft tile."""
    global n
    n += 1
    i = f"o{n}"
    defs = f'<linearGradient id="{i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffd27a"/><stop offset="1" stop-color="#ffa01c"/></linearGradient>'
    if solid_tile:
        tile = f'<mask id="{i}m"><rect width="18" height="18" fill="#fff"/><circle cx="9" cy="{cy}" r="{r+1.3}" fill="#000"/></mask><rect x="1.5" y="1.5" width="15" height="15" rx="4.2" stroke="none" fill-opacity=".85" mask="url(#{i}m)"/>'
    elif cut:
        tile = f'<mask id="{i}m"><rect width="18" height="18" fill="#fff"/><circle cx="9" cy="{cy}" r="{r+1.2}" fill="#000"/></mask><rect x="1.5" y="1.5" width="15" height="15" rx="4.2" stroke="none" fill-opacity=".32" mask="url(#{i}m)"/>'
    elif tint:
        tile = f'<rect x="1.5" y="1.5" width="15" height="15" rx="4.2" stroke="none" fill="{tint}" fill-opacity=".30"/>'
    else:
        tile = TILE.format(o=.32)
    return g(defs + tile + f'<circle cx="9" cy="{cy}" r="{r}" fill="url(#{i})" stroke="none"/>')

PEEK = g(TILE.format(o=.32) + sun(18.6, 5.4))
GREY_CENTRE = lambda r=3.8: g(TILE.format(o=.32) + f'<circle cx="9" cy="9" r="{r}" stroke="none"/>')
RING_CENTRE = g(TILE.format(o=.32) + '<circle cx="9" cy="9" r="3.4" fill="none" stroke-width="1.4"/>')

options = [
    ("H1 Peek, then a centred sun", "At rest as now. When tickets wait a flat orange sun sits in the middle, no glow.", PEEK, orange(4.2), "recommended"),
    ("H2 Smaller centred sun", "The same with a smaller sun, more tile around it.", PEEK, orange(3.4), ""),
    ("H3 Bigger centred sun", "A bigger sun that nearly fills the tile.", PEEK, orange(5.2), ""),
    ("H4 Centred at rest too", "The sun is always in the middle: grey at rest, orange when tickets wait. Only the colour changes.", GREY_CENTRE(), orange(3.8), ""),
    ("H5 Grey ring, then orange", "At rest an outlined sun in the middle; when tickets wait it is filled orange.", RING_CENTRE, orange(3.8), ""),
    ("H6 A gap around the sun", "The orange sun with a thin gap cut around it, so it stands apart from the tile; crisp, no blur.", PEEK, orange(3.8, cut=True), ""),
    ("H7 Warm tile", "The tile turns a soft orange and the sun sits in it.", PEEK, orange(3.8, tint="#ffa01c"), ""),
    ("H8 Stronger tile", "The tile goes solid in the menu bar's colour with the orange sun in a cut-out circle: the strongest signal without glow.", PEEK, orange(3.8, solid_tile=True), ""),
]

def row(name, note, rest, wait, tag):
    col = lambda lab, gl: f'<div><span class="lab">{lab}</span>{bar(gl)}{bar(gl, False)}<div class="big">{gl}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="menu">{col("At rest", rest)}{col("Tickets wait", wait)}</div></section>'

head = (HERE / "menubar-round3.html").read_text().split("<h2>")[0].replace("round three", "round eight")
html = head + f'<h2>Menu bar item: a centred sun, no glow</h2><p>Each icon has a dashed outline, between stand-ins for the icons in your menu bar.</p><main>{"".join(row(*o) for o in options)}</main>'
(HERE / "menubar-centred.html").write_text(html)
print("ok")
