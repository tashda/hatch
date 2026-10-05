# Menu bar item, round seven: G with a smaller, centred, glowing orange sun when tickets wait. Writes menubar-glow.html.
import pathlib
from family_variations import g
from menubar_round3 import bar
from menubar_soft import TILE, sun
HERE = pathlib.Path(__file__).parent
REST = g(TILE.format(o=.32) + sun(18.6, 5.4))
n = 0

def glowing(cy, r, glow_r, strength, tint=None, ring=False):
    global n
    n += 1
    i = f"gl{n}"
    defs = (f'<radialGradient id="{i}" cx="9" cy="{cy}" r="{glow_r}" gradientUnits="userSpaceOnUse">'
            f'<stop offset="{r/glow_r:.2f}" stop-color="#ffb43c" stop-opacity="{strength}"/><stop offset="1" stop-color="#ffb43c" stop-opacity="0"/></radialGradient>'
            f'<radialGradient id="{i}s" cx="9" cy="{cy-r*0.3}" r="{r*1.2}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ffd27a"/><stop offset="1" stop-color="#ff9a10"/></radialGradient>'
            f'<clipPath id="{i}c"><rect x="1.5" y="1.5" width="15" height="15" rx="4.2"/></clipPath>')
    tile = f'<rect x="1.5" y="1.5" width="15" height="15" rx="4.2" stroke="none" fill="{tint}" fill-opacity=".38"/>' if tint else TILE.format(o=.32)
    halo = f'<circle cx="9" cy="{cy}" r="{r+1.6}" fill="#ffa01c" fill-opacity=".35" stroke="none"/>' if ring else f'<circle cx="9" cy="{cy}" r="{glow_r}" fill="url(#{i})" stroke="none"/>'
    return g(defs + tile + f'<g clip-path="url(#{i}c)">{halo}<circle cx="9" cy="{cy}" r="{r}" fill="url(#{i}s)" stroke="none"/></g>')

options = [
    ("G as it was", "For comparison.", REST, g(TILE.format(o=.32) + sun(12.2, 5.6, fill="#ffa01c")), ""),
    ("G1 Centred, soft glow", "A smaller sun in the middle of the tile with a soft orange glow around it.", REST, glowing(9, 3.8, 7.2, .75), "recommended"),
    ("G2 Smaller, stronger glow", "A smaller sun still, the glow reaching the tile's edges.", REST, glowing(9, 3.1, 7.5, .95), ""),
    ("G3 A little high", "Centred across, a touch above the middle, as if just risen.", REST, glowing(8.2, 3.6, 7.0, .8), ""),
    ("G4 Ring instead of glow", "A crisp ring around the sun instead of a blur, which stays sharp at 18 pt.", REST, glowing(9, 3.6, 7.0, .8, ring=True), ""),
    ("G5 Warm tile", "The whole tile warms to orange behind a glowing sun.", REST, glowing(9, 3.6, 7.2, .85, tint="#ffa01c"), ""),
]

def row(name, note, rest, wait, tag):
    col = lambda lab, gl: f'<div><span class="lab">{lab}</span>{bar(gl)}{bar(gl, False)}<div class="big">{gl}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="menu">{col("At rest", rest)}{col("Tickets wait", wait)}</div></section>'

head = (HERE / "menubar-round3.html").read_text().split("<h2>")[0].replace("round three", "round seven")
html = head + f'<h2>Menu bar item: a glowing sun</h2><p>At rest is the same for all: the sun only peeks. Each icon has a dashed outline, between stand-ins for the icons in your menu bar.</p><main>{"".join(row(*o) for o in options)}</main>'
(HERE / "menubar-glow.html").write_text(html)
print("ok")
