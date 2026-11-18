#!/usr/bin/env python3
"""Draw the Supervim app icon and check the committed artwork.

The icon is one chunky light-gray keycap, tilted a few degrees, with a bold
green lowercase f on its face and a yellow hint label with a dark F floating
over its top-left corner. Every outline is straight lines and circular arcs,
and the SVG and the bitmaps are written from the same outlines.

The slots use four drawings:

- master: the 1024 canvas, kept inside the 824 macOS icon grid. Every slot of
  128 pixels and up.
- compact: the master with a larger label, a heavier letter and a deeper side
  on the f. The 64-pixel slot, which is 32 points at 2x.
- medium: upright, on the whole pixels of a 32 grid. The 32-point slot at 1x.
- small: upright, on a 16 grid. The 16-point slot. At 2x it gains the letter
  on the label.

Drawing needs numpy. `--check` reads the committed files with the standard
library only. `--artifacts DIR` also writes the previews; the Finder and Dock
mock is a page photographed by Chrome, and is skipped where there is none.
"""

from __future__ import annotations

import math
import re
import struct
import sys
import zlib
from pathlib import Path

CANVAS = 1024
GRID = 824
MARGIN = (CANVAS - GRID) // 2

KEY_TOP_LIT = "#E9E9EC"
KEY_TOP_SHADE = "#D9D9DD"
KEY_SHOULDER = "#C1C1C6"
KEY_SIDE_LIT = "#B3B3B8"
KEY_SIDE_MID = "#9C9CA1"
KEY_SIDE_SHADE = "#818186"
GREEN = "#3C9647"
GREEN_LIT = "#45A050"
GREEN_SIDE = "#1F5C28"
YELLOW = "#FFD83A"
YELLOW_LIT = "#FFDF52"
YELLOW_SIDE = "#C79C08"
LETTER = "#24421B"
BLACK = "#000000"

# Shapes are measured on the reference image's own 1024 canvas, where the
# drawing is centered on REFERENCE_CENTER. FIT scales it to fill the height of
# the icon grid and moves that point to the canvas center.
REFERENCE_CENTER = (517.2, 495.1)
FIT = 1.245

# iconutil's iconset names, the drawing each slot uses, its pixel size, and
# the PNG-flavored icns type it becomes.
ICONSET = (
    ("icon_16x16.png", "small", 16, "icp4"),
    ("icon_16x16@2x.png", "small-fine", 32, "ic11"),
    ("icon_32x32.png", "medium", 32, "icp5"),
    ("icon_32x32@2x.png", "compact", 64, "ic12"),
    ("icon_128x128.png", "master", 128, "ic07"),
    ("icon_128x128@2x.png", "master", 256, "ic13"),
    ("icon_256x256.png", "master", 256, "ic08"),
    ("icon_256x256@2x.png", "master", 512, "ic14"),
    ("icon_512x512.png", "master", 512, "ic09"),
    ("icon_512x512@2x.png", "master", 1024, "ic10"),
)

np = None


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


# --------------------------------------------------------------------------
# Geometry. A subpath is a closed list of pieces:
#   ("L", start, end)                  straight line
#   ("A", center, radius, a0, a1)      circular arc from angle a0 to a1
# Angles are radians with y growing downward, so a growing angle turns
# clockwise on screen. Closed outlines run clockwise on screen.
# --------------------------------------------------------------------------


def add(p, q):
    return (p[0] + q[0], p[1] + q[1])


def sub(p, q):
    return (p[0] - q[0], p[1] - q[1])


def mul(p, k):
    return (p[0] * k, p[1] * k)


def dot(p, q):
    return p[0] * q[0] + p[1] * q[1]


def unit(p):
    length = math.hypot(p[0], p[1])
    return (p[0] / length, p[1] / length)


def arc_point(center, radius, angle):
    return (center[0] + radius * math.cos(angle), center[1] + radius * math.sin(angle))


def piece_start(piece):
    if piece[0] == "L":
        return piece[1]
    return arc_point(piece[1], piece[2], piece[3])


def piece_end(piece):
    if piece[0] == "L":
        return piece[2]
    return arc_point(piece[1], piece[2], piece[4])


def reverse_piece(piece):
    if piece[0] == "L":
        return ("L", piece[2], piece[1])
    return ("A", piece[1], piece[2], piece[4], piece[3])


def move_piece(piece, offset):
    if piece[0] == "L":
        return ("L", add(piece[1], offset), add(piece[2], offset))
    return ("A", add(piece[1], offset), piece[2], piece[3], piece[4])


def move(subpath, offset):
    return [move_piece(piece, offset) for piece in subpath]


def reverse(subpath):
    return [reverse_piece(piece) for piece in reversed(subpath)]


def flatten(subpath, scale: float = 1.0, tolerance: float = 0.02):
    """Polygon for a subpath, in units of `scale`, without the closing point."""
    points = []
    for piece in subpath:
        if piece[0] == "L":
            points.append(mul(piece[1], scale))
            continue
        _, center, radius, a0, a1 = piece
        reach = radius * scale
        if reach <= tolerance:
            steps = 1
        else:
            step = 2 * math.acos(max(-1.0, 1 - tolerance / reach))
            steps = max(2, int(math.ceil(abs(a1 - a0) / step)))
        for index in range(steps):
            angle = a0 + (a1 - a0) * index / steps
            points.append(mul(arc_point(center, radius, angle), scale))
    return points


def signed_area(points) -> float:
    total = 0.0
    for index, (x0, y0) in enumerate(points):
        x1, y1 = points[(index + 1) % len(points)]
        total += x0 * y1 - x1 * y0
    return total / 2


def clockwise(subpath):
    return subpath if signed_area(flatten(subpath)) >= 0 else reverse(subpath)


def bounds(subpaths):
    xs, ys = [], []
    for subpath in subpaths:
        for x, y in flatten(subpath):
            xs.append(x)
            ys.append(y)
    return min(xs), min(ys), max(xs), max(ys)


def frame(origin, x_degrees: float, y_degrees: float, scale: float = 1.0):
    """Map local (x, y) to the canvas. Each axis is turned clockwise on its own."""
    xr = math.radians(x_degrees)
    yr = math.radians(y_degrees)
    ux = (math.cos(xr) * scale, math.sin(xr) * scale)
    uy = (-math.sin(yr) * scale, math.cos(yr) * scale)

    def place(x: float, y: float):
        return (origin[0] + x * ux[0] + y * uy[0], origin[1] + x * ux[1] + y * uy[1])

    return place


def rounded_polygon(points, radii):
    """Polygon with each corner replaced by a circular arc of its radius."""
    count = len(points)
    if isinstance(radii, (int, float)):
        radii = [radii] * count
    corners = []
    for index in range(count):
        vertex = points[index]
        to_previous = sub(points[index - 1], vertex)
        to_next = sub(points[(index + 1) % count], vertex)
        radius = radii[index]
        if radius <= 0:
            corners.append((vertex, vertex, None, 0.0))
            continue
        u1 = unit(to_previous)
        u2 = unit(to_next)
        half = math.acos(max(-1.0, min(1.0, dot(u1, u2)))) / 2
        reach = radius / math.tan(half)
        start = add(vertex, mul(u1, reach))
        end = add(vertex, mul(u2, reach))
        center = add(vertex, mul(unit(add(u1, u2)), radius / math.sin(half)))
        a0 = math.atan2(start[1] - center[1], start[0] - center[0])
        a1 = math.atan2(end[1] - center[1], end[0] - center[0])
        while a1 - a0 > math.pi:
            a1 -= 2 * math.pi
        while a1 - a0 < -math.pi:
            a1 += 2 * math.pi
        corners.append((start, end, ("A", center, radius, a0, a1), reach))
    pieces = []
    for index in range(count):
        _, end, arc, reach = corners[index]
        following = corners[(index + 1) % count]
        edge = math.dist(points[index], points[(index + 1) % count])
        if reach + following[3] > edge + 1e-6:
            raise SystemExit(f"corner radii overlap on edge {index}: {reach + following[3]:.2f} > {edge:.2f}")
        if arc is not None:
            pieces.append(arc)
        if math.dist(end, following[0]) > 1e-6:
            pieces.append(("L", end, following[0]))
    return pieces


def offset_polygon(points, distance: float):
    """Move every edge of a clockwise polygon outward by `distance`."""
    count = len(points)
    lines = []
    for index in range(count):
        start = points[index]
        end = points[(index + 1) % count]
        tangent = unit(sub(end, start))
        normal = (tangent[1], -tangent[0])
        lines.append((add(start, mul(normal, distance)), tangent))
    moved = []
    for index in range(count):
        (p, r), (q, s) = lines[index - 1], lines[index]
        cross = r[0] * s[1] - r[1] * s[0]
        t = ((q[0] - p[0]) * s[1] - (q[1] - p[1]) * s[0]) / cross
        moved.append(add(p, mul(r, t)))
    return moved


def convex_hull(points):
    ordered = sorted(set(points))

    def turn(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for point in ordered:
        while len(lower) >= 2 and turn(lower[-2], lower[-1], point) <= 1e-9:
            lower.pop()
        lower.append(point)
    for point in reversed(ordered):
        while len(upper) >= 2 and turn(upper[-2], upper[-1], point) <= 1e-9:
            upper.pop()
        upper.append(point)
    return lower[:-1] + upper[:-1]


def round_hull(centers, radius: float):
    """Outline of the convex hull of equal circles around `centers`."""
    hull = convex_hull(centers)
    return rounded_polygon(offset_polygon(hull, radius), radius)


def tuck(centers, targets, distance: float):
    """Slide each center toward its target.

    A raised face and the body under it would otherwise share their outer
    edge, and the darker body would show through the antialiasing as a
    hairline. Sliding the upper circles along the extrusion keeps the
    silhouette's tangent lines and pulls the shared edge under the face.
    """
    return [add(c, mul(unit(sub(t, c)), distance)) for c, t in zip(centers, targets)]


def rounded_rect(x: float, y: float, width: float, height: float, radius: float):
    corners = [(x, y), (x + width, y), (x + width, y + height), (x, y + height)]
    return rounded_polygon(corners, radius)


def facing_parts(piece, direction):
    """The parts of a clockwise outline piece whose outward side faces `direction`."""
    if piece[0] == "L":
        tangent = sub(piece[2], piece[1])
        outward = (tangent[1], -tangent[0])
        return [piece] if dot(outward, direction) > 1e-9 else []
    _, center, radius, a0, a1 = piece
    sign = 1.0 if a1 > a0 else -1.0
    heading = math.atan2(direction[1], direction[0])
    low, high = min(a0, a1), max(a0, a1)
    cuts = [low, high]
    for base in (heading + math.pi / 2, heading - math.pi / 2):
        turns = math.ceil((low - base) / (2 * math.pi))
        angle = base + turns * 2 * math.pi
        while angle < high:
            if angle - low > 1e-9 and high - angle > 1e-9:
                cuts.append(angle)
            angle += 2 * math.pi
    cuts.sort()
    parts = []
    for start, end in zip(cuts, cuts[1:]):
        middle = (start + end) / 2
        if sign * math.cos(middle - heading) <= 1e-9:
            continue
        parts.append(("A", center, radius, start, end) if sign > 0 else ("A", center, radius, end, start))
    return parts if sign > 0 else list(reversed(parts))


def extrusion_side(subpath, direction):
    """Subpaths that cover what the outline sweeps when pushed along `direction`.

    Together with the outline itself they are exactly the swept shape, so the
    side of a raised letter has no notches at its corners.
    """
    walls = []
    for piece in clockwise(subpath):
        for part in facing_parts(piece, direction):
            far = move_piece(reverse_piece(part), direction)
            wall = [
                part,
                ("L", piece_end(part), piece_start(far)),
                far,
                ("L", piece_end(far), piece_start(part)),
            ]
            walls.append(clockwise(wall))
    return walls


# --------------------------------------------------------------------------
# Scenes
# --------------------------------------------------------------------------


def solid(color: str):
    return ("solid", color)


def linear(start, end, stops):
    return ("linear", start, end, tuple(stops))


def layer(name, subpaths, paint, opacity: float = 1.0, blur: float = 0.0, clip=None):
    return {
        "name": name,
        "subpaths": subpaths,
        "paint": paint,
        "opacity": opacity,
        "blur": blur,
        "clip": clip,
    }


def fit(point):
    return (
        CANVAS / 2 + (point[0] - REFERENCE_CENTER[0]) * FIT,
        CANVAS / 2 + (point[1] - REFERENCE_CENTER[1]) * FIT,
    )


def master_scene(compact: bool = False):
    """The full drawing on the 1024 canvas.

    `compact` is the same drawing prepared for 64 pixels: a larger label with
    a heavier letter and a deeper side on the f, so they survive the scale.
    """
    k = FIT

    # Keycap. The face and the foot are the reference's two quadrilaterals,
    # listed clockwise from the top left. The body is the hull of both with
    # one corner radius, so the face outline and the silhouette share arcs.
    radius = 62 * k
    face_corners = [fit(p) for p in ((262, 224), (798, 258), (757, 702), (206, 655))]
    foot_corners = [fit(p) for p in ((276, 340), (833, 372), (770, 833), (214, 764))]
    face_centers = offset_polygon(face_corners, -radius)
    foot_centers = offset_polygon(foot_corners, -radius)
    key_top = round_hull(face_centers, radius)
    key_shoulder = round_hull(tuck(face_centers, foot_centers, 10 * k) + tuck(face_centers, foot_centers, 26 * k), radius)
    key_body = round_hull(tuck(face_centers, foot_centers, 10 * k) + foot_centers, radius)

    def face(x: float, y: float):
        """Point on the face; x and y run 0..1 from its top-left corner."""
        top = add(mul(face_corners[0], 1 - x), mul(face_corners[1], x))
        bottom = add(mul(face_corners[3], 1 - x), mul(face_corners[2], x))
        return add(mul(top, 1 - y), mul(bottom, y))

    # The sides shade across the direction the keycap is extruded in, so the
    # rounded front-right corner turns from the front tone to the right tone.
    drop = unit(sub(foot_centers[2], face_centers[2]))
    across = (drop[1], -drop[0])
    left = face_centers[3]
    corner = face_centers[2]
    span = dot(sub(corner, left), across) + radius * 1.15
    side_end = add(left, mul(across, span))
    turn = dot(sub(corner, left), across) / span
    body_paint = linear(
        left,
        side_end,
        [(0.0, KEY_SIDE_LIT), (0.45, KEY_SIDE_MID), (turn, KEY_SIDE_MID), (1.0, KEY_SIDE_SHADE)],
    )
    top_paint = linear(face(0.05, 1.0), face(0.95, 0.0), [(0.0, KEY_TOP_LIT), (1.0, KEY_TOP_SHADE)])

    # Lowercase f. Its crossbar follows the keycap and its stem leans a
    # little further, like the reference.
    glyph = frame(fit((467, 296.5)), 3.2, 10.0, k)
    f_points = [
        (0, 0), (142, 0), (142, 62), (80, 62), (80, 95), (138, 95), (138, 151),
        (80, 151), (80, 300), (0, 300), (0, 151), (-42, 151), (-42, 95), (0, 95),
    ]
    f_radii = [88, 13, 13, 30, 4, 13, 13, 4, 13, 13, 4, 13, 13, 4]
    f_face = rounded_polygon([glyph(x, y) for x, y in f_points], [r * k for r in f_radii])
    f_depth = (11 * k, 16 * k) if compact else (7 * k, 10 * k)
    f_side = extrusion_side(f_face, f_depth)
    f_paint = linear(glyph(-42, 0), glyph(142, 300), [(0.0, GREEN_LIT), (1.0, GREEN)])

    # Hint label, turned 9 degrees the other way, with a lip under it.
    grow = 1.2 if compact else 1.0
    label = frame(fit((319, 239) if compact else (311, 227)), -9.0, -9.0, k * grow)
    label_radius = 27 * k * grow
    label_corners = [label(-98, -52), label(98, -52), label(98, 52), label(-98, 52)]
    label_centers = offset_polygon(label_corners, -label_radius)
    lip = (1 * k * grow, 13 * k * grow)
    label_top = round_hull(label_centers, label_radius)
    lip_centers = [add(c, lip) for c in label_centers]
    label_body = round_hull(tuck(label_centers, lip_centers, 6 * k) + lip_centers, label_radius)
    label_paint = linear(label(0, -52), label(0, 52), [(0.0, YELLOW_LIT), (1.0, YELLOW)])
    if compact:
        letter_points = [
            (-28, -36), (26, -36), (26, -15), (-5, -15), (-5, -6), (21, -6),
            (21, 14), (-5, 14), (-5, 36), (-28, 36),
        ]
    else:
        letter_points = [
            (-27, -34), (23, -34), (23, -18), (-10, -18), (-10, -6), (19, -6),
            (19, 9), (-10, 9), (-10, 34), (-27, 34),
        ]
    letter = rounded_polygon([label(x, y) for x, y in letter_points], 2.5 * k)

    return {
        "size": CANVAS,
        "layers": [
            layer("ground-shadow", [move(s, (0, 18)) for s in (key_body, key_top, label_body, label_top)], solid(BLACK), 0.30, 15.0),
            layer("keycap-sides", [key_body], body_paint),
            layer("keycap-shoulder", [key_shoulder], solid(KEY_SHOULDER)),
            layer("keycap-face", [key_top], top_paint),
            layer("label-shadow", [move(label_body, (7 * k, 14 * k))], solid(BLACK), 0.22, 8.0 * k, clip="keycap"),
            layer("f-shadow", [move(f_face, (11 * k, 15 * k))], solid(BLACK), 0.26, 6.0 * k, clip="face"),
            layer("f-side", f_side, solid(GREEN_SIDE)),
            layer("f-face", [f_face], f_paint),
            layer("label-lip", [label_body], solid(YELLOW_SIDE)),
            layer("label-face", [label_top], label_paint),
            layer("label-letter", [letter], solid(LETTER)),
        ],
        "clips": {"keycap": [key_body, key_top], "face": [key_top]},
    }


def box_centers(x0: float, y0: float, x1: float, y1: float, radius: float):
    return [
        (x0 + radius, y0 + radius),
        (x1 - radius, y0 + radius),
        (x1 - radius, y1 - radius),
        (x0 + radius, y1 - radius),
    ]


def upright_f(stem_left, stem_right, top, bottom, hook_right, hook_bottom, bar_left, bar_right, bar_top, bar_bottom, outer, inner, tip):
    """Lowercase f on whole pixels: a stem, a hook to the right, a crossbar."""
    points = [
        (stem_left, top), (hook_right, top), (hook_right, hook_bottom), (stem_right, hook_bottom),
        (stem_right, bar_top), (bar_right, bar_top), (bar_right, bar_bottom), (stem_right, bar_bottom),
        (stem_right, bottom), (stem_left, bottom), (stem_left, bar_bottom), (bar_left, bar_bottom),
        (bar_left, bar_top), (stem_left, bar_top),
    ]
    radii = [outer, tip, tip, inner, 0, tip, tip, 0, tip, tip, 0, tip, tip, 0]
    return rounded_polygon(points, radii)


def upright_letter(left, top, stem, bar, width, middle_width, height, middle_top):
    """Capital F from three bars."""
    return [
        rounded_rect(left, top, stem, height, 0),
        rounded_rect(left, top, width, bar, 0),
        rounded_rect(left, top + middle_top, middle_width, bar, 0),
    ]


def medium_scene():
    """The 32-pixel drawing: upright, every edge on a whole pixel."""
    radius = 5
    face_centers = box_centers(4, 7, 28, 25, radius)
    foot_centers = box_centers(4, 12, 30, 30, radius)
    key_top = round_hull(face_centers, radius)
    key_shoulder = round_hull(tuck(face_centers, foot_centers, 0.5) + tuck(face_centers, foot_centers, 1.2), radius)
    key_body = round_hull(tuck(face_centers, foot_centers, 0.5) + foot_centers, radius)
    body_paint = linear((4, 0), (30, 0), [(0.0, KEY_SIDE_LIT), (0.5, KEY_SIDE_MID), (0.8, KEY_SIDE_MID), (1.0, KEY_SIDE_SHADE)])
    top_paint = linear((5, 25), (27, 7), [(0.0, KEY_TOP_LIT), (1.0, KEY_TOP_SHADE)])

    f_face = upright_f(15, 19, 9, 22, 23, 12, 12, 22, 14, 17, outer=4, inner=1, tip=0.75)
    f_side = extrusion_side(f_face, (1, 1))

    label_radius = 3
    label_centers = box_centers(1, 1, 13, 10, label_radius)
    lip_centers = box_centers(1, 2, 13, 11, label_radius)
    label_top = round_hull(label_centers, label_radius)
    label_body = round_hull(tuck(label_centers, lip_centers, 0.5) + lip_centers, label_radius)
    letter = upright_letter(5, 3, 2, 1, 5, 4, 5, 2)

    return {
        "size": 32,
        "layers": [
            layer("ground-shadow", [move(s, (0, 1)) for s in (key_body, key_top, label_body, label_top)], solid(BLACK), 0.34, 0.9),
            layer("keycap-sides", [key_body], body_paint),
            layer("keycap-shoulder", [key_shoulder], solid(KEY_SHOULDER)),
            layer("keycap-face", [key_top], top_paint),
            layer("label-shadow", [move(label_body, (0.5, 1))], solid(BLACK), 0.22, 0.7, clip="keycap"),
            layer("f-side", f_side, solid(GREEN_SIDE)),
            layer("f-face", [f_face], solid(GREEN)),
            layer("label-lip", [label_body], solid(YELLOW_SIDE)),
            layer("label-face", [label_top], solid(YELLOW)),
            layer("label-letter", letter, solid(LETTER)),
        ],
        "clips": {"keycap": [key_body, key_top]},
    }


def small_scene(fine: bool = False):
    """The 16-point drawing. `fine` is the 2x slot, which has room for the
    letter on the label and a thin side on the f."""
    radius = 2.5
    face_centers = box_centers(2, 3, 14, 12, radius)
    foot_centers = box_centers(2, 6, 15, 15, radius)
    key_top = round_hull(face_centers, radius)
    key_body = round_hull(tuck(face_centers, foot_centers, 0.25) + foot_centers, radius)
    body_paint = linear((2, 0), (15, 0), [(0.0, KEY_SIDE_LIT), (0.5, KEY_SIDE_MID), (0.8, KEY_SIDE_MID), (1.0, KEY_SIDE_SHADE)])
    top_paint = linear((3, 12), (13, 3), [(0.0, KEY_TOP_LIT), (1.0, KEY_TOP_SHADE)])

    f_face = upright_f(8, 10, 4, 11, 13, 6, 6, 11, 7, 9, outer=2, inner=0.5, tip=0.25)

    label_radius = 1.5
    label_centers = box_centers(1, 1, 7, 5, label_radius)
    lip_centers = box_centers(1, 2, 7, 6, label_radius)
    label_top = round_hull(label_centers, label_radius)
    label_body = round_hull(tuck(label_centers, lip_centers, 0.25) + lip_centers, label_radius)

    layers = [
        layer("ground-shadow", [move(s, (0, 0.5)) for s in (key_body, key_top, label_body, label_top)], solid(BLACK), 0.34, 0.5),
        layer("keycap-sides", [key_body], body_paint),
        layer("keycap-face", [key_top], top_paint),
    ]
    if fine:
        layers.append(layer("f-side", extrusion_side(f_face, (0.5, 0.5)), solid(GREEN_SIDE)))
    layers += [
        layer("f-face", [f_face], solid(GREEN)),
        layer("label-lip", [label_body], solid(YELLOW_SIDE)),
        layer("label-face", [label_top], solid(YELLOW)),
    ]
    if fine:
        layers.append(layer("label-letter", upright_letter(3, 1.5, 1, 0.5, 2.5, 2, 3, 1), solid(LETTER)))
    return {"size": 16, "layers": layers, "clips": {}}


SCENES = {
    "master": master_scene,
    "compact": lambda: master_scene(compact=True),
    "medium": medium_scene,
    "small": small_scene,
    "small-fine": lambda: small_scene(fine=True),
}


# --------------------------------------------------------------------------
# SVG
# --------------------------------------------------------------------------


def number(value: float) -> str:
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def path_data(subpaths) -> str:
    parts = []
    for subpath in subpaths:
        start = piece_start(subpath[0])
        parts.append(f"M{number(start[0])},{number(start[1])}")
        for piece in subpath:
            end = piece_end(piece)
            if piece[0] == "L":
                parts.append(f"L{number(end[0])},{number(end[1])}")
            else:
                _, _, radius, a0, a1 = piece
                large = 1 if abs(a1 - a0) > math.pi else 0
                sweep = 1 if a1 > a0 else 0
                r = number(radius)
                parts.append(f"A{r},{r} 0 {large} {sweep} {number(end[0])},{number(end[1])}")
        parts.append("Z")
    return " ".join(parts)


def svg_document(scene, title: str = "Supervim") -> str:
    size = scene["size"]
    defs = []
    body = []
    blurs = []
    for name, subpaths in scene["clips"].items():
        defs.append(f'    <clipPath id="clip-{name}"><path d="{path_data(subpaths)}"/></clipPath>')
    for item in scene["layers"]:
        name = item["name"]
        attributes = [f'id="{name}"', f'd="{path_data(item["subpaths"])}"']
        paint = item["paint"]
        if paint[0] == "solid":
            attributes.append(f'fill="{paint[1]}"')
        else:
            _, start, end, stops = paint
            defs.append(
                f'    <linearGradient id="paint-{name}" gradientUnits="userSpaceOnUse" '
                f'x1="{number(start[0])}" y1="{number(start[1])}" x2="{number(end[0])}" y2="{number(end[1])}">'
            )
            for offset, color in stops:
                defs.append(f'      <stop offset="{number(offset)}" stop-color="{color}"/>')
            defs.append("    </linearGradient>")
            attributes.append(f'fill="url(#paint-{name})"')
        if item["opacity"] < 1:
            attributes.append(f'fill-opacity="{number(item["opacity"])}"')
        if item["blur"] > 0:
            sigma = number(item["blur"])
            if sigma not in blurs:
                blurs.append(sigma)
                defs.append(
                    f'    <filter id="blur-{len(blurs)}" filterUnits="userSpaceOnUse" x="0" y="0" '
                    f'width="{size}" height="{size}" color-interpolation-filters="sRGB">'
                    f'<feGaussianBlur stdDeviation="{sigma}"/></filter>'
                )
            attributes.append(f'filter="url(#blur-{blurs.index(sigma) + 1})"')
        if item["clip"]:
            attributes.append(f'clip-path="url(#clip-{item["clip"]})"')
        body.append("  <path " + " ".join(attributes) + "/>")
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">',
        f"  <title>{title}</title>",
        "  <defs>",
        *defs,
        "  </defs>",
        *body,
        "</svg>",
        "",
    ]
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Rasterizer (numpy)
# --------------------------------------------------------------------------


def _numpy():
    global np
    if np is None:
        import numpy as imported

        np = imported
    return np


def rgb(color: str):
    value = int(color.lstrip("#"), 16)
    return ((value >> 16) & 255, (value >> 8) & 255, value & 255)


def coverage(subpaths, px: int, scale: float, rows: int):
    """Fraction of each pixel inside the subpaths, nonzero winding.

    Each pixel row is cut into `rows` scanlines. Along a scanline the covered
    length is exact, so vertical and near-vertical edges are not stair-stepped.
    """
    array = _numpy()
    lines = px * rows
    accumulator = array.zeros((lines, px + 2), dtype=array.float64)
    for subpath in subpaths:
        points = array.asarray(flatten(subpath, scale), dtype=array.float64)
        x0, y0 = points[:, 0], points[:, 1]
        x1, y1 = array.roll(x0, -1), array.roll(y0, -1)
        keep = y0 != y1
        x0, y0, x1, y1 = x0[keep], y0[keep], x1[keep], y1[keep]
        first = array.ceil(array.minimum(y0, y1) * rows - 0.5).astype(array.int64)
        last = array.ceil(array.maximum(y0, y1) * rows - 0.5).astype(array.int64)
        first = array.clip(first, 0, lines)
        last = array.clip(last, 0, lines)
        counts = last - first
        total = int(counts.sum())
        if total == 0:
            continue
        edge = array.repeat(array.arange(len(counts)), counts)
        starts = array.cumsum(counts) - counts
        line = first[edge] + (array.arange(total) - starts[edge])
        y = (line + 0.5) / rows
        x = x0[edge] + (y - y0[edge]) * (x1[edge] - x0[edge]) / (y1[edge] - y0[edge])
        x = array.clip(x, 0.0, float(px))
        direction = array.where(y1[edge] > y0[edge], 1.0, -1.0)
        column = array.floor(x).astype(array.int64)
        fraction = x - column
        array.add.at(accumulator, (line, column), direction * (1 - fraction))
        array.add.at(accumulator, (line, column + 1), direction * fraction)
    winding = array.cumsum(accumulator, axis=1)[:, :px]
    inside = array.clip(array.abs(winding), 0.0, 1.0)
    return inside.reshape(px, rows, px).mean(axis=1).astype(array.float32)


def gaussian_kernel(sigma: float):
    array = _numpy()
    radius = max(1, int(math.ceil(sigma * 3)))
    offsets = array.arange(-radius, radius + 1, dtype=array.float32)
    kernel = array.exp(-0.5 * (offsets / sigma) ** 2)
    kernel /= kernel.sum()
    return kernel


def blur_alpha(alpha, sigma: float):
    array = _numpy()
    if sigma <= 0.05:
        return alpha
    kernel = gaussian_kernel(sigma)
    radius = kernel.shape[0] // 2
    padded = array.pad(alpha, ((0, 0), (radius, radius)), mode="constant")
    horizontal = array.zeros_like(alpha)
    for index, weight in enumerate(kernel):
        horizontal += weight * padded[:, index : index + alpha.shape[1]]
    padded = array.pad(horizontal, ((radius, radius), (0, 0)), mode="constant")
    vertical = array.zeros_like(alpha)
    for index, weight in enumerate(kernel):
        vertical += weight * padded[index : index + alpha.shape[0], :]
    return vertical


def paint_pixels(paint, px: int, scale: float):
    array = _numpy()
    if paint[0] == "solid":
        return array.asarray(rgb(paint[1]), dtype=array.float32).reshape(1, 1, 3) / 255
    _, start, end, stops = paint
    xs = (array.arange(px, dtype=array.float32)[None, :] + 0.5) / scale
    ys = (array.arange(px, dtype=array.float32)[:, None] + 0.5) / scale
    dx, dy = end[0] - start[0], end[1] - start[1]
    t = ((xs - start[0]) * dx + (ys - start[1]) * dy) / (dx * dx + dy * dy)
    t = array.clip(t, 0.0, 1.0)
    offsets = [offset for offset, _ in stops]
    colors = [rgb(color) for _, color in stops]
    channels = [array.interp(t, offsets, [color[index] for color in colors]) for index in range(3)]
    return array.stack(channels, axis=-1).astype(array.float32) / 255


def over(base, color, alpha):
    array = _numpy()
    alpha = alpha[..., None]
    out_a = alpha + base[..., 3:4] * (1 - alpha)
    out_rgb = (color * alpha + base[..., :3] * base[..., 3:4] * (1 - alpha)) / array.maximum(out_a, 1e-6)
    base[..., :3] = out_rgb
    base[..., 3:4] = out_a


def render(scene, px: int):
    """RGBA uint8 image of a scene at px by px."""
    array = _numpy()
    scale = px / scene["size"]
    rows = 4 if px >= 256 else 8 if px >= 64 else 16
    clips = {name: coverage(subpaths, px, scale, rows) for name, subpaths in scene["clips"].items()}
    image = array.zeros((px, px, 4), dtype=array.float32)
    for item in scene["layers"]:
        alpha = coverage(item["subpaths"], px, scale, rows)
        if item["blur"] > 0:
            alpha = blur_alpha(alpha, item["blur"] * scale)
        if item["clip"]:
            alpha = alpha * clips[item["clip"]]
        over(image, paint_pixels(item["paint"], px, scale), alpha * item["opacity"])
    return array.clip(array.rint(image * 255), 0, 255).astype(array.uint8)


# --------------------------------------------------------------------------
# PNG and icns
# --------------------------------------------------------------------------


def png_bytes(image) -> bytes:
    height, width, channels = image.shape
    if channels != 4:
        raise SystemExit("image is not RGBA")
    raw = b"".join(b"\x00" + image[y].tobytes() for y in range(height))
    compressed = zlib.compress(raw, 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")


def write_png(path: Path, image) -> None:
    path.write_bytes(png_bytes(image))


def pack_icns(images: list[tuple[str, bytes]]) -> bytes:
    chunks = []
    toc = b""
    for os_type, blob in images:
        header = os_type.encode("ascii") + struct.pack(">I", 8 + len(blob))
        chunks.append(header + blob)
        toc += header
    toc_chunk = b"TOC " + struct.pack(">I", 8 + len(toc)) + toc
    body = toc_chunk + b"".join(chunks)
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


def render_slots():
    """Every (drawing, pixel size) the iconset needs, rendered once."""
    scenes = {name: build() for name, build in SCENES.items()}
    slots = {}
    for _, drawing, size, _ in ICONSET:
        if (drawing, size) not in slots:
            slots[(drawing, size)] = render(scenes[drawing], size)
    return scenes, slots


def generate(root: Path, artifacts: Path | None) -> None:
    _numpy()
    resources = root / "Resources"
    resources.mkdir(parents=True, exist_ok=True)
    scenes, slots = render_slots()
    svg_path = resources / "AppIcon.svg"
    svg_path.write_text(svg_document(scenes["master"]), encoding="utf-8")

    iconset = resources / "AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    packed: list[tuple[str, bytes]] = []
    for filename, drawing, size, os_type in ICONSET:
        blob = png_bytes(slots[(drawing, size)])
        (iconset / filename).write_bytes(blob)
        packed.append((os_type, blob))
    master_path = resources / "AppIcon-1024.png"
    write_png(master_path, slots[("master", CANVAS)])
    icns_path = resources / "AppIcon.icns"
    icns_path.write_bytes(pack_icns(packed))
    print(f"Wrote {svg_path}")
    print(f"Wrote {master_path}")
    print(f"Wrote {icns_path}")
    if artifacts is not None:
        write_previews(artifacts, slots)


# --------------------------------------------------------------------------
# Previews
# --------------------------------------------------------------------------

LIGHT = (255, 255, 255)
DARK = (30, 30, 30)

# 3 by 5 digits, plus the mark the size labels need.
GLYPHS = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("110", "010", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "010", "010", "010"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "111"),
    "x": ("000", "101", "010", "101", "000"),
    " ": ("00", "00", "00", "00", "00"),
}


def composite_on(image, color: tuple[int, int, int]):
    array = _numpy()
    alpha = image[..., 3:4].astype(array.float32) / 255
    mixed = image[..., :3].astype(array.float32) * alpha + array.array(color, dtype=array.float32) * (1 - alpha)
    out = array.empty_like(image)
    out[..., :3] = array.clip(array.rint(mixed), 0, 255).astype(array.uint8)
    out[..., 3] = 255
    return out


def enlarge(image, factor: int):
    array = _numpy()
    return array.repeat(array.repeat(image, factor, axis=0), factor, axis=1)


def draw_label(image, text: str, center: int, top: int, ink) -> None:
    scale = 2
    widths = [len(GLYPHS[char][0]) * scale for char in text]
    x = center - (sum(widths) + scale * (len(text) - 1)) // 2
    for char, width in zip(text, widths):
        for row, bits in enumerate(GLYPHS[char]):
            for column, bit in enumerate(bits):
                if bit == "1":
                    y0 = top + row * scale
                    x0 = x + column * scale
                    image[y0 : y0 + scale, x0 : x0 + scale, :3] = ink
        x += width + scale


def sizes_sheet(slots):
    """16, 32, 64, 128 and 256 pixels as shipped, on white and on dark.

    The second row of each panel repeats the four smallest slots, named by
    point size and scale, enlarged to 128 pixels without smoothing so the
    pixel fitting can be judged.
    """
    array = _numpy()
    real = [("16", "small", 16), ("32", "medium", 32), ("64", "compact", 64), ("128", "master", 128), ("256", "master", 256)]
    zoomed = [("16", "small", 16, 8), ("16 2x", "small-fine", 32, 4), ("32", "medium", 32, 4), ("32 2x", "compact", 64, 2)]
    pad, gap, label = 40, 44, 26
    width = pad * 2 + sum(size for _, _, size in real) + gap * (len(real) - 1)
    panel = pad + 256 + label + pad + 128 + label + pad
    sheet = array.zeros((panel * 2, width, 4), dtype=array.uint8)
    sheet[..., 3] = 255
    for index, (background, ink) in enumerate(((LIGHT, (110, 110, 115)), (DARK, (152, 152, 157)))):
        top = index * panel
        sheet[top : top + panel, :, :3] = background
        x = pad
        for text, drawing, size in real:
            y = top + pad + 256 - size
            sheet[y : y + size, x : x + size] = composite_on(slots[(drawing, size)], background)
            draw_label(sheet, text, x + size // 2, top + pad + 256 + 10, ink)
            x += size + gap
        x = pad
        y = top + pad + 256 + label + pad
        step = (width - pad * 2 - 128 * len(zoomed)) // (len(zoomed) - 1)
        for text, drawing, size, factor in zoomed:
            tile = enlarge(composite_on(slots[(drawing, size)], background), factor)
            sheet[y : y + 128, x : x + 128] = tile
            draw_label(sheet, text, x + 64, y + 128 + 10, ink)
            x += 128 + step
    return sheet


def write_previews(directory: Path, slots) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    write_png(directory / "preview-1024.png", slots[("master", CANVAS)])
    write_png(directory / "preview-sizes.png", sizes_sheet(slots))
    print(f"Wrote {directory / 'preview-1024.png'}")
    print(f"Wrote {directory / 'preview-sizes.png'}")
    write_mock(directory / "preview-dock-finder.png", slots)


MOCK_WIDTH = 880
MOCK_HEIGHT = 520

MOCK_STYLE = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { width: 880px; font: 12px/1.2 -apple-system, "SF Pro Text", Inter, "Helvetica Neue", Arial, sans-serif; -webkit-font-smoothing: antialiased; }
.screen { position: relative; width: 880px; height: 520px; overflow: hidden; background: var(--desk); color: var(--text); }
.light { --desk: #c9d7e8; --window: #ffffff; --bar: #f1f1f3; --side: #e9e9ec; --text: #1d1d1f; --dim: #86868b; --line: rgba(0,0,0,.12); --stripe: #f5f5f7; --dock: rgba(255,255,255,.45); --dockline: rgba(255,255,255,.6); --pick: rgba(0,0,0,.08); }
.dark { --desk: #20242c; --window: #1e1e1e; --bar: #323234; --side: #2a2a2c; --text: #f5f5f7; --dim: #98989d; --line: rgba(255,255,255,.14); --stripe: #262628; --dock: rgba(70,70,74,.5); --dockline: rgba(255,255,255,.16); --pick: rgba(255,255,255,.12); }
.window { position: absolute; border-radius: 10px; background: var(--window); box-shadow: 0 0 0 .5px var(--line), 0 18px 40px rgba(0,0,0,.28); overflow: hidden; }
.title { height: 38px; background: var(--bar); border-bottom: .5px solid var(--line); display: flex; align-items: center; font-weight: 600; font-size: 13px; }
.lights { display: flex; gap: 8px; margin: 0 14px 0 13px; }
.lights i { width: 12px; height: 12px; border-radius: 50%; }
.side { position: absolute; left: 0; top: 38px; bottom: 0; width: 128px; background: var(--side); border-right: .5px solid var(--line); padding: 10px 8px; }
.side h4 { font-size: 11px; color: var(--dim); font-weight: 600; margin: 0 0 4px 6px; }
.side p { height: 24px; display: flex; align-items: center; gap: 7px; padding: 0 6px; border-radius: 5px; }
.side p.on { background: var(--pick); }
.side p i { width: 14px; height: 11px; border-radius: 2.5px; background: #3b82f6; }
.grid { position: absolute; left: 128px; right: 0; top: 38px; bottom: 0; display: grid; grid-template-columns: repeat(4, 1fr); align-content: start; gap: 14px 0; padding: 20px 10px; }
.app { display: flex; flex-direction: column; align-items: center; gap: 5px; }
.app span { padding: 1px 5px; border-radius: 4px; }
.app.on .tile { background: var(--pick); border-radius: 6px; }
.app.on span { background: #2f6fe0; color: #fff; }
.tile { width: 72px; height: 72px; display: flex; align-items: center; justify-content: center; }
.fake { border-radius: 22.4%; box-shadow: 0 1px 2px rgba(0,0,0,.3); }
.rows { position: absolute; left: 0; right: 0; top: 38px; bottom: 0; }
.rows div { height: 24px; display: flex; align-items: center; gap: 7px; padding: 0 14px; }
.rows div:nth-child(odd) { background: var(--stripe); }
.rows div.head { height: 24px; color: var(--dim); font-size: 11px; background: var(--window); border-bottom: .5px solid var(--line); }
.rows div b { font-weight: 400; margin-left: auto; color: var(--dim); }
.rows div u { width: 16px; height: 16px; display: flex; align-items: center; justify-content: center; text-decoration: none; }
.rows div.big { height: 44px; }
.rows div.big u { width: 32px; height: 32px; }
.dock { position: absolute; left: 50%; bottom: 8px; transform: translateX(-50%); height: 80px; padding: 8px 10px; display: flex; gap: 4px; border-radius: 22px; background: var(--dock); box-shadow: inset 0 0 0 .5px var(--dockline), 0 8px 24px rgba(0,0,0,.2); }
.dock .slot { width: 64px; height: 64px; display: flex; align-items: center; justify-content: center; }
img { display: block; }
"""

MOCK_NAMES = ("Atlas", "Beacon", "Cobalt", "Drift", "Ember", "Fathom", "Glint")
MOCK_TINTS = (
    ("#5ab0ff", "#1a6fe8"), ("#ff9d5c", "#f0532d"), ("#8f8cf5", "#5a48d6"), ("#5fd18b", "#1f9d57"),
    ("#ff7a8a", "#e23a55"), ("#62d4e3", "#1899b8"), ("#b7bcc6", "#7d838f"),
)


def mock_html(slots) -> str:
    """One page with a light and a dark desktop: Finder icon view, list view, Dock."""
    import base64

    def picture(drawing: str, pixels: int) -> str:
        data = base64.b64encode(png_bytes(slots[(drawing, pixels)])).decode("ascii")
        points = pixels // 2
        return f'<img width="{points}" height="{points}" src="data:image/png;base64,{data}">'

    def fake(index: int, points: float) -> str:
        top, bottom = MOCK_TINTS[index % len(MOCK_TINTS)]
        side = points * GRID / CANVAS
        return f'<i class="fake" style="width:{side:.2f}px;height:{side:.2f}px;background:linear-gradient({top},{bottom})"></i>'

    def screen(theme: str) -> str:
        cells = []
        order = [0, 1, "supervim", 2, 3, 4, 5, 6]
        for item in order:
            if item == "supervim":
                cells.append(f'<div class="app on"><div class="tile">{picture("master", 128)}</div><span>Supervim</span></div>')
            else:
                cells.append(f'<div class="app"><div class="tile">{fake(item, 64)}</div><span>{MOCK_NAMES[item]}</span></div>')
        rows = ['<div class="head">Name<b>Kind</b></div>']
        for item in (0, 1, 2):
            rows.append(f'<div><u>{fake(item, 16)}</u>{MOCK_NAMES[item]}<b>Application</b></div>')
        rows.append(f'<div><u>{picture("small-fine", 32)}</u>Supervim<b>Application</b></div>')
        for item in (3, 4):
            rows.append(f'<div><u>{fake(item, 16)}</u>{MOCK_NAMES[item]}<b>Application</b></div>')
        rows.append(f'<div class="big"><u>{picture("compact", 64)}</u>Supervim<b>32 pt</b></div>')
        rows.append(f'<div class="big"><u>{fake(5, 32)}</u>{MOCK_NAMES[5]}<b>32 pt</b></div>')
        dock = []
        for item in (0, 1, 2, "supervim", 3, 4, 5):
            inner = picture("master", 128) if item == "supervim" else fake(item, 64)
            dock.append(f'<div class="slot">{inner}</div>')
        lights = '<div class="lights"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div>'
        places = "".join(
            f'<p class="{"on" if name == "Applications" else ""}"><i></i>{name}</p>'
            for name in ("Recents", "Applications", "Desktop", "Documents", "Downloads")
        )
        return f"""
<div class="screen {theme}">
  <div class="window" style="left:24px;top:22px;width:508px;height:384px">
    <div class="title">{lights}Applications</div>
    <div class="side"><h4>Favorites</h4>{places}</div>
    <div class="grid">{"".join(cells)}</div>
  </div>
  <div class="window" style="left:556px;top:22px;width:300px;height:384px">
    <div class="title">{lights}Applications</div>
    <div class="rows">{"".join(rows)}</div>
  </div>
  <div class="dock">{"".join(dock)}</div>
</div>"""

    return f'<!doctype html><html><head><meta charset="utf-8"><style>{MOCK_STYLE}</style></head><body>{screen("light")}{screen("dark")}</body></html>'


def write_mock(path: Path, slots) -> None:
    """Screenshot the Finder and Dock mock at 2x with a Chrome that is on this machine."""
    import shutil
    import subprocess
    import tempfile
    import time

    names = ("google-chrome", "chromium", "chromium-browser", "chrome")
    browser = next((found for found in map(shutil.which, names) if found), None)
    mac = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    if browser is None and mac.exists():
        browser = str(mac)
    if browser is None:
        print(f"No Chrome on this machine; left {path} as it was")
        return
    scratch = Path(tempfile.mkdtemp(prefix="supervim-icon-"))
    try:
        page = scratch / "mock.html"
        page.write_text(mock_html(slots), encoding="utf-8")
        shot = scratch / "mock.png"
        command = [
            browser, "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
            "--force-device-scale-factor=2", f"--window-size={MOCK_WIDTH},{MOCK_HEIGHT * 2}",
            f"--user-data-dir={scratch / 'profile'}", f"--screenshot={shot}", page.as_uri(),
        ]
        # Some headless builds write the screenshot and then never exit, so
        # stop the browser once the file is complete.
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 60
        data = b""
        while time.monotonic() < deadline:
            time.sleep(0.25)
            data = shot.read_bytes() if shot.exists() else b""
            if data.endswith(b"IEND\xaeB`\x82") or process.poll() is not None:
                break
        if process.poll() is None:
            process.terminate()
            process.wait()
        data = shot.read_bytes() if shot.exists() else b""
        if not data.endswith(b"IEND\xaeB`\x82"):
            raise SystemExit("Chrome did not write the Finder and Dock mock")
        path.write_bytes(data)
    finally:
        # The browser's helpers can still be writing their profile for a moment.
        for _ in range(20):
            shutil.rmtree(scratch, ignore_errors=True)
            if not scratch.exists():
                break
            time.sleep(0.1)
    print(f"Wrote {path}")


# --------------------------------------------------------------------------
# Check (standard library only)
# --------------------------------------------------------------------------


def read_png(data: bytes):
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        raise SystemExit("not a PNG")
    position = 8
    width = height = None
    body = b""
    while position < len(data):
        length = struct.unpack(">I", data[position : position + 4])[0]
        tag = data[position + 4 : position + 8]
        chunk = data[position + 8 : position + 8 + length]
        position += 12 + length
        if tag == b"IHDR":
            width, height, bit, color, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if (bit, color, interlace) != (8, 6, 0):
                raise SystemExit("PNG must be 8-bit non-interlaced RGBA")
        elif tag == b"IDAT":
            body += chunk
        elif tag == b"IEND":
            break
    if width is None or height is None:
        raise SystemExit("PNG has no IHDR")
    raw = zlib.decompress(body)
    stride = width * 4
    rows = []
    cursor = 0
    previous = bytearray(stride)
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        scanline = bytearray(raw[cursor : cursor + stride])
        cursor += stride
        previous = scanline if filter_type == 0 else unfilter(filter_type, scanline, previous)
        rows.append(previous)
    return width, height, rows


def unfilter(filter_type: int, scanline: bytearray, previous: bytearray) -> bytearray:
    out = bytearray(len(scanline))
    for index, value in enumerate(scanline):
        left = out[index - 4] if index >= 4 else 0
        up = previous[index]
        upper_left = previous[index - 4] if index >= 4 else 0
        if filter_type == 1:
            predicted = left
        elif filter_type == 2:
            predicted = up
        elif filter_type == 3:
            predicted = (left + up) // 2
        elif filter_type == 4:
            predicted = paeth(left, up, upper_left)
        else:
            raise SystemExit(f"unsupported PNG filter {filter_type}")
        out[index] = (value + predicted) & 255
    return out


def paeth(left: int, up: int, upper_left: int) -> int:
    estimate = left + up - upper_left
    nearest_left = abs(estimate - left)
    nearest_up = abs(estimate - up)
    nearest_upper_left = abs(estimate - upper_left)
    if nearest_left <= nearest_up and nearest_left <= nearest_upper_left:
        return left
    if nearest_up <= nearest_upper_left:
        return up
    return upper_left


def pixel(rows, x: int, y: int) -> tuple[int, int, int, int]:
    index = x * 4
    sample = rows[y]
    return sample[index], sample[index + 1], sample[index + 2], sample[index + 3]


def icns_pngs(path: Path) -> dict[str, bytes]:
    data = path.read_bytes()
    if data[:4] != b"icns":
        raise SystemExit(f"{path} is not an icns")
    declared = struct.unpack(">I", data[4:8])[0]
    if declared != len(data):
        raise SystemExit(f"{path} length is {len(data)}, header says {declared}")
    found = {}
    offset = 8
    while offset + 8 <= len(data):
        os_type = data[offset : offset + 4].decode("ascii")
        length = struct.unpack(">I", data[offset + 4 : offset + 8])[0]
        if length < 8 or offset + length > len(data):
            raise SystemExit(f"bad icns chunk {os_type}")
        if os_type != "TOC ":
            found[os_type] = data[offset + 8 : offset + length]
        offset += length
    if offset != len(data):
        raise SystemExit(f"{path} has trailing bytes")
    return found


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def is_gray(color) -> bool:
    return color[3] == 255 and max(color[:3]) - min(color[:3]) <= 10


def is_green(color) -> bool:
    red, green, blue, alpha = color
    return alpha >= 250 and green >= 120 and green - red >= 50 and green - blue >= 40


def is_yellow(color) -> bool:
    red, green, blue, alpha = color
    return alpha >= 250 and red >= 200 and green >= 170 and blue <= 110


def is_letter(color) -> bool:
    red, green, blue, alpha = color
    return alpha >= 250 and red <= 70 and 45 <= green <= 80 and blue <= 55 and green > red


def census(rows, width: int, height: int):
    """Count the green, yellow and letter pixels and box the opaque ones."""
    counts = {"green": 0, "yellow": 0, "letter": 0}
    box = [width, height, -1, -1]
    for y in range(height):
        for x in range(width):
            color = pixel(rows, x, y)
            if color[3] >= 250:
                box = [min(box[0], x), min(box[1], y), max(box[2], x), max(box[3], y)]
            if is_green(color):
                counts["green"] += 1
            elif is_yellow(color):
                counts["yellow"] += 1
            elif is_letter(color):
                counts["letter"] += 1
    return counts, box


NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


def same_drawing(expected: str, found: str, tolerance: float = 0.011) -> bool:
    """Equal text, except that numbers may differ in the last printed digit.

    Sines and arctangents can round differently between C libraries, so the
    committed SVG is compared by value.
    """
    if NUMBER.sub("#", expected) != NUMBER.sub("#", found):
        return False
    pairs = zip(NUMBER.findall(expected), NUMBER.findall(found))
    return all(abs(float(a) - float(b)) <= tolerance for a, b in pairs)


def check_master(rows, name: str) -> None:
    def at(point):
        x, y = fit(point)
        return pixel(rows, int(x), int(y))

    for corner in ((0, 0), (1023, 0), (0, 1023), (1023, 1023)):
        require(pixel(rows, *corner)[3] == 0, f"{name}: canvas corner {corner} is not transparent")
    face, face_far = at((300, 600)), at((700, 330))
    require(is_gray(face) and is_gray(face_far), f"{name}: keycap face is tinted: {face} {face_far}")
    require(face[0] >= 215 and face_far[0] >= 205, f"{name}: keycap face is too dark: {face} {face_far}")
    require(face[0] > face_far[0], f"{name}: keycap face does not lighten toward the lower left")
    front, right = at((480, 760)), at((800, 560))
    require(is_gray(front) and is_gray(right), f"{name}: keycap sides are tinted: {front} {right}")
    require(face_far[0] - front[0] >= 40, f"{name}: front side is not darker than the face: {front}")
    require(front[0] - right[0] >= 12, f"{name}: right side is not darker than the front: {front} {right}")
    require(is_green(at((460, 500))), f"{name}: the f is not green: {at((460, 500))}")
    require(is_green(at((560, 330))), f"{name}: the f has no hook: {at((560, 330))}")
    require(is_gray(at((560, 380))), f"{name}: the f is closed under its hook: {at((560, 380))}")
    require(is_yellow(at((250, 240))), f"{name}: the label is not yellow: {at((250, 240))}")
    require(is_letter(at((293, 230))), f"{name}: the label has no dark letter: {at((293, 230))}")
    shadow = False
    x, y = fit((480, 800))
    for row in range(int(y), 1020):
        red, green, blue, alpha = pixel(rows, int(x), row)
        if 8 <= alpha <= 160 and max(red, green, blue) < 60:
            shadow = True
            break
    require(shadow, f"{name}: the soft shadow under the keycap is missing")


# Fewest green, yellow and letter pixels each small slot may have.
SMALL_SLOTS = {
    "icp4": (20, 16, 0),
    "ic11": (80, 55, 12),
    "icp5": (64, 64, 11),
    "ic12": (160, 100, 10),
}


def check(root: Path) -> None:
    svg = (root / "Resources" / "AppIcon.svg").read_text(encoding="utf-8")
    require('viewBox="0 0 1024 1024"' in svg, "SVG is not a 1024 canvas")
    require("<text" not in svg, "SVG must draw its letters as paths")
    for color in (KEY_TOP_LIT, KEY_SIDE_MID, GREEN, YELLOW, LETTER):
        require(color in svg, f"SVG is missing {color}")
    for name in ("keycap-face", "keycap-sides", "f-face", "label-face", "label-letter", "ground-shadow"):
        require(f'id="{name}"' in svg, f"SVG is missing the {name} layer")
    require(same_drawing(svg_document(master_scene()), svg), "Resources/AppIcon.svg is not what render_icon.py draws")

    left, top, right, bottom = bounds([s for item in master_scene()["layers"] if item["blur"] == 0 for s in item["subpaths"]])
    require(
        left >= MARGIN - 0.5 and top >= MARGIN - 0.5 and right <= CANVAS - MARGIN + 0.5 and bottom <= CANVAS - MARGIN + 0.5,
        f"the drawing leaves the {GRID} icon grid: {left:.1f} {top:.1f} {right:.1f} {bottom:.1f}",
    )

    width, height, rows = read_png((root / "Resources" / "AppIcon-1024.png").read_bytes())
    require((width, height) == (CANVAS, CANVAS), f"master PNG is {width}x{height}")
    check_master(rows, "AppIcon-1024.png")
    _, box = census(rows, width, height)
    require(
        box[0] >= MARGIN - 1 and box[1] >= MARGIN - 1 and box[2] <= CANVAS - MARGIN and box[3] <= CANVAS - MARGIN,
        f"opaque pixels leave the {GRID} icon grid: {box}",
    )

    images = icns_pngs(root / "Resources" / "AppIcon.icns")
    for _, _, size, os_type in ICONSET:
        require(os_type in images, f"icns has no {os_type}")
        got_w, got_h, got_rows = read_png(images[os_type])
        require((got_w, got_h) == (size, size), f"{os_type} is {got_w}x{got_h}")
        for corner in ((0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)):
            require(pixel(got_rows, *corner)[3] <= 40, f"{os_type} corner {corner} is not clear")
        if size == CANVAS:
            check_master(got_rows, os_type)
        if os_type in SMALL_SLOTS:
            counts, _ = census(got_rows, size, size)
            green, yellow, letter = SMALL_SLOTS[os_type]
            require(
                counts["green"] >= green and counts["yellow"] >= yellow and counts["letter"] >= letter,
                f"{os_type} has {counts}, needs green {green}, yellow {yellow}, letter {letter}",
            )
    print("App icon check passed")


def main(argv: list[str]) -> None:
    root = repo_root()
    if "--check" in argv:
        check(root)
        return
    artifacts = None
    if "--artifacts" in argv:
        index = argv.index("--artifacts")
        artifacts = Path(argv[index + 1])
    generate(root, artifacts)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except SystemExit:
        raise
    except Exception as error:
        raise SystemExit(str(error)) from error
