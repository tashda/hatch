# Menu bar item, round six: E (the soft tile) with a clearer difference when tickets wait. Writes menubar-soft.html.
import pathlib
from family_variations import g
from menubar_round3 import bar
HERE = pathlib.Path(__file__).parent
n = 0
TILE = '<rect x="1.5" y="1.5" width="15" height="15" rx="4.2" stroke="none" fill-opacity="{o}"/>'

def sun(cy, r, below=16.5, opacity=1.0, fill="currentColor"):
    global n
    n += 1
    return (f'<clipPath id="s{n}"><rect x="1.5" y="1.5" width="15" height="15" rx="4.2"/></clipPath><clipPath id="h{n}"><rect width="18" height="{below}"/></clipPath>'
            f'<g clip-path="url(#s{n})"><circle cx="9" cy="{cy}" r="{r}" stroke="none" fill="{fill}" fill-opacity="{opacity}" clip-path="url(#h{n})"/></g>')

def cut_tile(cy, r):
    # A solid tile with the sun cut out of it, so the menu bar shows through the sun.
    global n
    n += 1
    return (f'<mask id="m{n}"><rect width="18" height="18" fill="#fff"/><circle cx="9" cy="{cy}" r="{r}" fill="#000"/></mask>'
            f'<rect x="1.5" y="1.5" width="15" height="15" rx="4.2" stroke="none" mask="url(#m{n})"/>')

def hole_tile(cy, r, o=.32):
    global n
    n += 1
    return (f'<mask id="m{n}"><rect width="18" height="18" fill="#fff"/><circle cx="9" cy="{cy}" r="{r}" fill="#000"/></mask>'
            f'<rect x="1.5" y="1.5" width="15" height="15" rx="4.2" stroke="none" fill-opacity="{o}" mask="url(#m{n})"/>')

ORANGE = "#ffa01c"
E_REST = g(TILE.format(o=.32) + sun(16.5, 5.6))
options = [
    ("A E as it was", "For comparison: the sun comes up a little.", E_REST, g(TILE.format(o=.32) + sun(12.6, 5.0)), ""),
    ("B Peek, then rise", "At rest only the top of the sun shows above the edge. When tickets wait it is well up and bigger. The move is the signal.",
     g(TILE.format(o=.32) + sun(18.6, 5.4)), g(TILE.format(o=.32) + sun(12.2, 5.6)), ""),
    ("C Asleep, then awake", "At rest the whole icon is faint, like a menu bar item that is idle. When tickets wait the sun is solid and up.",
     g(TILE.format(o=.22) + sun(16.5, 5.6, opacity=.45)), g(TILE.format(o=.32) + sun(12.4, 5.2)), ""),
    ("D Lights on", "At rest E. When tickets wait the tile turns solid with the sun cut out of it, risen.",
     E_REST, g(cut_tile(12.4, 5.0)), ""),
    ("E Empty sun, then full", "At rest the sun is only a hole in the soft tile. When tickets wait the sun is solid.",
     g(hole_tile(16.5, 5.6)), g(TILE.format(o=.32) + sun(16.5, 5.6)), ""),
    ("F The sun turns orange", "At rest E, in the menu bar's own colour. When tickets wait the sun is Hatch's orange: the one coloured thing in the menu bar says it is your turn. (A coloured icon is drawn for light and dark by Hatch, not tinted by macOS.)",
     E_REST, g(TILE.format(o=.32) + sun(16.5, 5.6, fill=ORANGE)), ""),
    ("G Rises and turns orange", "B and F together: at rest the sun only peeks; when tickets wait it is up and orange.",
     g(TILE.format(o=.32) + sun(18.6, 5.4)), g(TILE.format(o=.32) + sun(12.2, 5.6, fill=ORANGE)), "recommended"),
]

def row(name, note, rest, wait, tag):
    col = lambda lab, gl: f'<div><span class="lab">{lab}</span>{bar(gl)}{bar(gl, False)}<div class="big">{gl}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="menu">{col("At rest", rest)}{col("Tickets wait", wait)}</div></section>'

head = (HERE / "menubar-round3.html").read_text().split("<h2>")[0].replace("round three", "round six")
html = head + f'<h2>Menu bar item: the soft tile, with a clearer signal</h2><p>Each icon has a dashed outline, between stand-ins for the icons in your menu bar.</p><main>{"".join(row(*o) for o in options)}</main>'
(HERE / "menubar-soft.html").write_text(html)
print("ok")
