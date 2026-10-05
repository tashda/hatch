# Menu bar item, round five: variations on C3, the sun sitting on the frame's edge. Writes menubar-c3.html.
import pathlib
from family_variations import g
from menubar_round3 import bar
HERE = pathlib.Path(__file__).parent
FRAME = '<rect x="2.25" y="2.25" width="13.5" height="13.5" rx="3.6" fill="none" stroke-width="1.5"/>'
n = 0

def sun(cy, r, below, cx=9.0):
    """A filled sun cut flat at y = below (the horizon)."""
    global n
    n += 1
    return f'<clipPath id="k{n}"><rect width="18" height="{below}"/></clipPath><circle cx="{cx}" cy="{cy}" r="{r}" stroke="none" clip-path="url(#k{n})"/>'

def ring_sun(cy, r, below):
    global n
    n += 1
    return f'<clipPath id="k{n}"><rect width="18" height="{below}"/></clipPath><circle cx="9" cy="{cy}" r="{r-0.75}" fill="none" stroke-width="1.5" clip-path="url(#k{n})"/>'

SOFT = '<rect x="1.5" y="1.5" width="15" height="15" rx="4.2" stroke="none" fill-opacity=".32"/>'
THICK = '<path d="M2.25 13 V5.85 A3.6 3.6 0 0 1 5.85 2.25 H12.15 A3.6 3.6 0 0 1 15.75 5.85 V13" fill="none" stroke-width="1.5"/><path d="M1.5 13 H16.5 V12.9 A3.6 3.6 0 0 1 16.5 13 V12.9 L16.5 12.9 V16.5 H1.5 Z" stroke="none" opacity="0"/><path d="M1.5 12.6 H16.5 V12.9 A3.6 3.6 0 0 1 12.9 16.5 H5.1 A3.6 3.6 0 0 1 1.5 12.9 Z" stroke="none"/>'
CIRCLE = '<circle cx="9" cy="9" r="7.25" fill="none" stroke-width="1.5"/>'

options = [
    ("A C3 as it was", "For comparison: the sun on the frame's bottom edge, risen into the middle when tickets wait.",
     g(FRAME + sun(15.75, 5.0, 15.75)), g(FRAME + '<circle cx="9" cy="9.6" r="4.2" stroke="none"/>'), ""),
    ("B Rises, not to the middle", "The same at rest. When tickets wait the sun comes three quarters up and stays on the horizon, so it never looks like a record button.",
     g(FRAME + sun(15.75, 5.0, 15.75)), g(FRAME + sun(12.3, 4.6, 15.75)), "recommended"),
    ("C Bigger sun", "The sun fills more of the tile: easier to read at 18 pt.",
     g(FRAME + sun(15.75, 6.0, 15.75)), g(FRAME + sun(12.0, 5.4, 15.75)), ""),
    ("D A gap at the horizon", "The sun stops just above the frame's edge, a thin gap as the horizon. A touch more refined.",
     g(FRAME + sun(15.75, 5.2, 14.0)), g(FRAME + sun(12.0, 4.8, 14.0)), ""),
    ("E Soft tile, no border", "No line: the tile is a soft fill (the menu bar draws it lighter), the sun solid on its bottom edge.",
     g(SOFT + sun(16.5, 5.6, 16.5)), g(SOFT + sun(12.6, 5.0, 16.5)), ""),
    ("F Round frame", "A circle instead of a rounded square, the sun on its bottom.",
     g(CIRCLE + sun(15.6, 5.0, 15.3)), g(CIRCLE + sun(11.6, 4.5, 15.3)), ""),
    ("G No frame", "Only the sun and the horizon, the sun big enough to fill the height: a flat-bottomed sun on a line.",
     g(sun(10.5, 7.5, 12.6) + '<path d="M1 15.25 H17" stroke-width="1.5" stroke-linecap="round" fill="none"/>'),
     g(sun(8.6, 7.0, 12.6) + '<path d="M1 15.25 H17" stroke-width="1.5" stroke-linecap="round" fill="none"/>'), ""),
    ("H Heavy horizon", "The frame's bottom is a solid band, the sea; the sun sits on it.",
     g(THICK + sun(12.6, 4.6, 12.0)), g(THICK + sun(9.8, 4.4, 12.0)), ""),
    ("I Outline sun", "The frame and an outlined sun on its edge; the sun fills in when tickets wait.",
     g(FRAME + ring_sun(15.75, 5.0, 15.0)), g(FRAME + sun(15.75, 5.0, 15.75)), ""),
]

def row(name, note, rest, wait, tag):
    col = lambda lab, gl: f'<div><span class="lab">{lab}</span>{bar(gl)}{bar(gl, False)}<div class="big">{gl}</div></div>'
    return f'<section><h3>{name} <span class="tag">{tag}</span></h3><p>{note}</p><div class="menu">{col("At rest", rest)}{col("Tickets wait", wait)}</div></section>'

head = (HERE / "menubar-round3.html").read_text().split("<h2>")[0].replace("round three", "round five")
html = head + f'<h2>Menu bar item: the sun on the edge</h2><p>Each icon has a dashed outline, between stand-ins for the icons in your menu bar.</p><main>{"".join(row(*o) for o in options)}</main>'
(HERE / "menubar-c3.html").write_text(html)
print("ok")
