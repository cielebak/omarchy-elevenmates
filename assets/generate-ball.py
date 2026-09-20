"""Regenerate the football mark in assets/banner.svg.

The mark is a disc with five pentagons cut out of it, which is the shorthand
everyone reads as a football. An honest projection of the real solid was tried
first and does not survive the size it is used at: thirty-two faces silt into a
golf ball, and cutting the seams to the rim turns the bright field into the
points of a star.

The proportions are measured, not guessed - patch circumradius and centre
distance as fractions of the disc's own radius, each patch turned so a flat
edge faces outwards, one of them square at the bottom.

    python3 assets/generate-ball.py   # the <g id="ball"> block for the banner

The result is one path with an even-odd fill, so the patches are holes rather
than shapes in the background's colour - the bar's background is a theme away
from being anything at all.
"""
import math

PATCH_RADIUS = 0.298     # of the disc's radius
PATCH_CENTRE = 0.605     # how far out the patches sit
PATCHES = 5


def pentagon(cx, cy, r, rot_deg, decimals):
    pts = [(cx + r * math.cos(math.radians(-90 + rot_deg + 72 * k)),
            cy + r * math.sin(math.radians(-90 + rot_deg + 72 * k)))
           for k in range(5)]
    fmt = "%%.%df %%.%df" % (decimals, decimals)
    return "M" + " L".join(fmt % p for p in pts) + " Z"


def ball_path(radius=1.0, decimals=4):
    """One path: the disc, then the patches. Fill it with the even-odd rule."""
    fmt = "%%.%df" % decimals
    r = fmt % radius
    minus_r = fmt % -radius
    # Two half arcs, because a single one of 360 degrees is a no-op in SVG.
    parts = ["M%s 0 A%s %s 0 1 0 %s 0 A%s %s 0 1 0 %s 0 Z"
             % (minus_r, r, r, r, r, r, minus_r)]
    for k in range(PATCHES):
        angle = math.radians(-90 + 36 + 72 * k)
        parts.append(pentagon(PATCH_CENTRE * radius * math.cos(angle),
                              PATCH_CENTRE * radius * math.sin(angle),
                              PATCH_RADIUS * radius,
                              36 + 72 * k, decimals))
    return " ".join(parts)


if __name__ == "__main__":
    print('    <g id="ball" stroke="none">')
    print('      <path fill-rule="evenodd" d="%s"/>' % ball_path(8.2, 3))
    print('    </g>')
