"""Writes the three icon concept SVGs (1024 canvas, 824pt body per Apple's macOS icon template)."""
import math, pathlib

OUT = pathlib.Path(__file__).parent
RED, CREAM, INK, GREEN = "#E4432D", "#F5EEE4", "#241F1D", "#3E8E4F"


def squircle(n=5, cx=512, cy=512, r=412, steps=180):
    """Superellipse approximating Apple's continuous-corner icon body."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append(f"{cx + r * math.copysign(abs(c) ** (2 / n), c):.1f},{cy + r * math.copysign(abs(s) ** (2 / n), s):.1f}")
    return "M" + " L".join(pts) + " Z"


def polar(cx, cy, r, deg):
    """Point at `deg` clockwise from 12 o'clock."""
    a = math.radians(deg - 90)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def arc(cx, cy, r, start, end):
    x0, y0 = polar(cx, cy, r, start)
    x1, y1 = polar(cx, cy, r, end)
    large = 1 if (end - start) % 360 > 180 else 0
    return f"M{x0:.1f},{y0:.1f} A{r},{r} 0 {large} 1 {x1:.1f},{y1:.1f}"


def icon(top, bottom, body):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>
    </linearGradient>
  </defs>
  <path d="{squircle()}" fill="url(#bg)"/>
{body}
</svg>
'''


# A: kitchen-timer dial, red sector already swept past 12, hand at its edge.
x, y = polar(512, 512, 250, 125)
a = icon("#FBF6EF", "#EDE3D6", f'''  <circle cx="512" cy="512" r="300" fill="#FFFFFF"/>
  <circle cx="512" cy="512" r="300" fill="none" stroke="{INK}" stroke-width="28" stroke-opacity="0.12"/>
  <path d="M512,512 L{arc(512, 512, 270, 0, 125)[1:]} Z" fill="{RED}"/>
  <path d="M512,512 L{x:.1f},{y:.1f}" stroke="{INK}" stroke-width="36" stroke-linecap="round"/>
  <circle cx="512" cy="512" r="42" fill="{INK}"/>''')

# B: play glyph inside a motion arc, on red: the button is already running.
b = icon("#EE5A40", "#C9321F", f'''  <path d="{arc(512, 512, 270, 40, 330)}" fill="none" stroke="{CREAM}" stroke-width="56" stroke-linecap="round"/>
  <path d="M{polar(512, 512, 270, 330)[0] - 58:.1f},{polar(512, 512, 270, 330)[1] - 42:.1f} L{polar(512, 512, 270, 330)[0] + 26:.1f},{polar(512, 512, 270, 330)[1] - 4:.1f} L{polar(512, 512, 270, 330)[0] - 30:.1f},{polar(512, 512, 270, 330)[1] + 70:.1f} Z" fill="{CREAM}" stroke="{CREAM}" stroke-width="20" stroke-linejoin="round"/>
  <path d="M462,400 L462,624 Q462,650 486,637 L644,537 Q666,512 644,487 L486,387 Q462,374 462,400 Z" fill="{CREAM}"/>''')

# C: geometric tomato (circle + leaf) inside a progress ring.
leaf = "M512,318 C470,262 404,262 380,280 C426,300 452,322 512,330 C572,322 598,300 644,280 C620,262 554,262 512,318 Z"
c = icon("#2D2826", "#1B1716", f'''  <circle cx="512" cy="512" r="318" fill="none" stroke="{CREAM}" stroke-width="34" stroke-opacity="0.16"/>
  <path d="{arc(512, 512, 318, 0, 250)}" fill="none" stroke="{CREAM}" stroke-width="34" stroke-linecap="round"/>
  <circle cx="512" cy="540" r="232" fill="{RED}"/>
  <path d="{leaf}" fill="{GREEN}"/>
  <path d="M512,324 L512,270" stroke="{GREEN}" stroke-width="26" stroke-linecap="round"/>''')

for name, svg in {"concept-a-dial": a, "concept-b-play": b, "concept-c-tomato": c}.items():
    (OUT / f"{name}.svg").write_text(svg)
