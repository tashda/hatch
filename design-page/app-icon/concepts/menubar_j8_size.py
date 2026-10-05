# Menu bar item, round ten: J8 at larger sizes and with more contrast at rest. Writes menubar-j8-size.html.
import pathlib
from family_variations import g
from menubar_round3 import bar
HERE = pathlib.Path(__file__).parent
n = 0

def j8(size, waiting, rest_tile=.32, rest_sun=.55):
    """J8 with the tile `size` pt wide on the 18 pt canvas; the sun and the gap scale with it."""
    global n
    n += 1
    i = f"z{n}"
    k = size / 15
    x = (18 - size) / 2
    r, gap, rx = 4.0 * k, 1.1 * k, 4.4 * k
    if waiting:
        defs = f'<linearGradient id="{i}s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffd27a"/><stop offset="1" stop-color="#ffa01c"/></linearGradient>'
        return g(defs + f'<mask id="{i}m"><rect width="18" height="18" fill="#fff"/><circle cx="9" cy="9" r="{r+gap}" fill="#000"/></mask>'
                 f'<rect x="{x}" y="{x}" width="{size}" height="{size}" rx="{rx}" stroke="none" mask="url(#{i}m)"/>'
                 f'<circle cx="9" cy="9" r="{r}" fill="url(#{i}s)" stroke="none"/>')
    return g(f'<mask id="{i}m"><rect width="18" height="18" fill="#fff"/><circle cx="9" cy="9" r="{r+gap}" fill="#000"/></mask>'
             f'<rect x="{x}" y="{x}" width="{size}" height="{size}" rx="{rx}" stroke="none" fill-opacity="{rest_tile}" mask="url(#{i}m)"/>'
             f'<circle cx="9" cy="9" r="{r}" stroke="none" fill-opacity="{rest_sun}"/>')

options = [
    ("J8 as it was", "A 15 pt tile, faint at rest (tile 32 %, sun 55 %).", j8(15, False), j8(15, True), ""),
    ("K1 Bigger, clearer at rest", "A 16.5 pt tile, the size of the solid icons beside it, and more contrast at rest (tile 40 %, sun 80 %).",
     j8(16.5, False, .40, .80), j8(16.5, True), "recommended"),
    ("K2 Full size", "The tile fills the 18 pt canvas edge to edge.", j8(18, False, .40, .80), j8(18, True), ""),
    ("K3 Bigger, rest as before", "16.5 pt, with J8's faint resting state.", j8(16.5, False), j8(16.5, True), ""),
]

def row(name, note, rest, wait, tag):
    col = lambda lab, gl: f'<div><span class="lab">{lab}</span>{bar(gl)}{bar(gl, False)}<div class="big">{gl}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="menu">{col("At rest", rest)}{col("Tickets wait", wait)}</div></section>'

head = (HERE / "menubar-round3.html").read_text().split("<h2>")[0].replace("round three", "round ten")
html = head + f'<h2>Menu bar item: J8, the right size</h2><p>Each icon has a dashed outline, between stand-ins for the icons in your menu bar.</p><main>{"".join(row(*o) for o in options)}</main>'
(HERE / "menubar-j8-size.html").write_text(html)
print("ok")
