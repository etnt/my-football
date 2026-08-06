#!/usr/bin/env python3
"""Generate the app launcher icon geometry as an ImageMagick MVG file.

Draws a minimalist soccer ball: a central black pentagon, five radial seams,
and five partial pentagons at the rim (clipped to the ball circle later by the
build pipeline). Coordinates are computed here so the shapes are exact.
"""
import math

W = 1024
CX = CY = W / 2

BALL_R = 300.0        # ball radius
CENTRAL_R = 118.0     # central pentagon circumradius
OUTER_D = 300.0       # distance of rim-pentagon centres from ball centre
OUTER_R = 96.0        # rim pentagon circumradius
SEAM_WIDTH = 18


def poly(cx, cy, r, start_deg):
    """Return five vertex points of a regular pentagon as an MVG point list."""
    pts = []
    for k in range(5):
        a = math.radians(start_deg + 72 * k)
        pts.append(f"{cx + r * math.cos(a):.2f},{cy + r * math.sin(a):.2f}")
    return " ".join(pts)


def point(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


lines = []
lines.append("push graphic-context")

# --- Seams first, so pentagons drawn on top cap them cleanly. ---
lines.append("fill none")
lines.append("stroke black")
lines.append(f"stroke-width {SEAM_WIDTH}")
lines.append("stroke-linecap round")
for k in range(5):
    ang = -90 + 72 * k                     # central pentagon vertex angle
    vx, vy = point(CX, CY, CENTRAL_R, ang)  # start at the central vertex
    ex, ey = point(CX, CY, OUTER_D, ang)    # out to the rim pentagon centre
    lines.append(f"line {vx:.2f},{vy:.2f} {ex:.2f},{ey:.2f}")

# --- Filled black pentagons on top. ---
lines.append("stroke none")
lines.append("fill black")
# Central pentagon, pointing up.
lines.append(f"polygon {poly(CX, CY, CENTRAL_R, -90)}")
# Rim pentagons, aligned with each central vertex, pointing inward.
for k in range(5):
    ang = -90 + 72 * k
    ox, oy = point(CX, CY, OUTER_D, ang)
    lines.append(f"polygon {poly(ox, oy, OUTER_R, ang + 180)}")

lines.append("pop graphic-context")

with open("assets/icon/marks.mvg", "w") as f:
    f.write("\n".join(lines) + "\n")

print("wrote assets/icon/marks.mvg")
