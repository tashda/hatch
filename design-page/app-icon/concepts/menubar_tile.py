# Menu bar item, round four: variations on the little tile (C). Writes menubar-tile.html.
import pathlib
from family_variations import g
from menubar_round3 import tile as old_tile, bar
HERE = pathlib.Path(__file__).parent
FRAME = '<rect x="2.25" y="2.25" width="13.5" height="13.5" rx="3.6" fill="none" stroke-width="1.5"/>'
CLIP = '<clipPath id="{id}"><rect x="1.5" y="1.5" width="15" height="15" rx="4.2"/></clipPath>'

def half(r, cy=11.0):
    return f'<path d="M{9-r} {cy} A{r} {r} 0 0 1 {9+r} {cy} Z" stroke="none"/>'

def risen(id, cy, r, below):
    return f'<clipPath id="{id}"><rect width="18" height="{below}"/></clipPath><circle cx="9" cy="{cy}" r="{r}" stroke="none" clip-path="url(#{id})"/>'

def sea(id, top=11.9, dash=True):
    # The sea as a solid band in the bottom of the tile, one reflection cut out of it.
    m = f'<mask id="{id}m"><rect width="18" height="18" fill="#fff"/>' + ('<path d="M6.6 14 H11.4" stroke="#000" stroke-width="1.3" stroke-linecap="round"/>' if dash else '') + '</mask>'
    return CLIP.format(id=id) + m + f'<g clip-path="url(#{id})"><rect x="0" y="{top}" width="18" height="8" stroke="none" mask="url(#{id}m)"/></g>'

LINE = '<path d="M2.5 11.2 H15.5" stroke-width="1.5" fill="none"/><path d="M6.8 13.9 H11.2" stroke-width="1.4" stroke-linecap="round" fill="none"/>'
options = [
    ("C1 The sea fills", "At rest: the frame, a bigger sun on the horizon and one reflection, light like the icons beside it. When tickets wait the sea fills in, so the tile turns into Hatch's icon.",
     g(FRAME + half(4.2, 11.2) + LINE), g(FRAME + half(4.2, 11.1) + sea("w1")), "recommended"),
    ("C2 The sun rises", "Hatch's icon in one colour: frame, sun and a solid sea. When tickets wait the sun is higher.",
     g(FRAME + half(3.9, 11.1) + sea("r2")), g(FRAME + risen("u2", 9.0, 3.9, 11.1) + sea("w2")), ""),
    ("C3 Sun on the frame", "No horizon line: the frame's bottom edge is the horizon and the sun sits on it. When tickets wait the sun has risen into the middle.",
     g(FRAME + risen("u3", 15.75, 5.0, 15.75)), g(FRAME + '<circle cx="9" cy="9.6" r="4.2" stroke="none"/>'), ""),
    ("C4 Outline sun to filled", "Frame, horizon and reflection stay; the sun is an outline at rest and filled when tickets wait.",
     g(FRAME + '<path d="M5.55 11.2 A3.45 3.45 0 0 1 12.45 11.2" fill="none" stroke-width="1.5"/>' + LINE), g(FRAME + half(4.2, 11.2) + LINE), ""),
    ("Round three's C", "For comparison.", old_tile(False), old_tile(True), ""),
]

def row(name, note, rest, wait, tag):
    col = lambda lab, gl: f'<div><span class="lab">{lab}</span>{bar(gl)}{bar(gl, False)}<div class="big">{gl}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="menu">{col("At rest", rest)}{col("Tickets wait", wait)}</div></section>'

html = (HERE / "menubar-round3.html").read_text().split("<h2>")[0].replace("round three", "round four") + \
    f'<h2>Menu bar item: the little tile</h2><p>Each icon has a dashed outline, between stand-ins for the icons in your menu bar.</p><main>{"".join(row(*o) for o in options)}</main>'
(HERE / "menubar-tile.html").write_text(html)
print("ok")
