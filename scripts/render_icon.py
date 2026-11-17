#!/usr/bin/env python3
"""Draw the Supervim app icon and check the committed artwork.

The 1024 canvas is transparent. A continuous-curvature rounded square sits in
the macOS icon grid: 824 units on a side, centered, corner radius 185. The
fill fades from #F7F7F8 at the top to #E9E9EC at the bottom, with a faint
top sheen and a short drop shadow. The only mark is a vertical Vim normal-mode
cursor, 52 by 142, filled with #34C759 and a soft glow of the same green.

Sizes at or below 64 pixels thicken that block so it survives the 16 and 32
point slots. There is no text.
"""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

CANVAS = 1024
SQUIRCLE = 824
MARGIN = (CANVAS - SQUIRCLE) // 2
CORNER_RADIUS = 185
CORNER_EXPONENT = 5.0
TOP = (0xF7, 0xF7, 0xF8)
BOTTOM = (0xE9, 0xE9, 0xEC)
CURSOR = (0x34, 0xC7, 0x59)
CURSOR_W = 52
CURSOR_H = 142
SHADOW_OFFSET = 14
SHADOW_SIGMA = 12.0
SHADOW_OPACITY = 0.22
GLOW_SIGMA = 16.0
SHEEN_STRENGTH = 0.62
SHEEN_REACH = 0.20

# iconutil's iconset names and the PNG-flavored icns types they become.
ICONSET = (
    ("icon_16x16.png", 16, "icp4"),
    ("icon_16x16@2x.png", 32, "ic11"),
    ("icon_32x32.png", 32, "icp5"),
    ("icon_32x32@2x.png", 64, "ic12"),
    ("icon_128x128.png", 128, "ic07"),
    ("icon_128x128@2x.png", 256, "ic13"),
    ("icon_256x256.png", 256, "ic08"),
    ("icon_256x256@2x.png", 512, "ic14"),
    ("icon_512x512.png", 512, "ic09"),
    ("icon_512x512@2x.png", 1024, "ic10"),
)

np = None


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def cursor_box(px: int) -> tuple[int, int, int, int]:
    """Return x, y, width, height of the cursor block in a px canvas."""
    if px <= 16:
        width, height = 4, 9
    elif px <= 32:
        width, height = 6, 16
    elif px <= 64:
        width, height = 8, 22
    else:
        width = max(1, int(math.floor(CURSOR_W * px / CANVAS + 0.5)))
        height = max(1, int(math.floor(CURSOR_H * px / CANVAS + 0.5)))
    x = (px - width) // 2
    y = (px - height) // 2
    return x, y, width, height


def squircle_points(samples: int = 48) -> list[tuple[float, float]]:
    """Clockwise outline of the 1024-grid squircle, y growing downward."""
    left = float(MARGIN)
    top = float(MARGIN)
    right = float(MARGIN + SQUIRCLE)
    bottom = float(MARGIN + SQUIRCLE)
    radius = float(CORNER_RADIUS)
    power = 2.0 / CORNER_EXPONENT
    points: list[tuple[float, float]] = []

    def corner(origin_x: float, origin_y: float, x_of, y_of) -> None:
        for index in range(1, samples + 1):
            theta = (index / samples) * (math.pi / 2)
            points.append((origin_x + x_of(theta), origin_y + y_of(theta)))

    points.append((left + radius, top))
    points.append((right - radius, top))
    corner(
        right - radius,
        top + radius,
        lambda t: radius * math.sin(t) ** power,
        lambda t: -radius * math.cos(t) ** power,
    )
    points.append((right, bottom - radius))
    corner(
        right - radius,
        bottom - radius,
        lambda t: radius * math.cos(t) ** power,
        lambda t: radius * math.sin(t) ** power,
    )
    points.append((left + radius, bottom))
    corner(
        left + radius,
        bottom - radius,
        lambda t: -radius * math.sin(t) ** power,
        lambda t: radius * math.cos(t) ** power,
    )
    points.append((left, top + radius))
    corner(
        left + radius,
        top + radius,
        lambda t: -radius * math.cos(t) ** power,
        lambda t: -radius * math.sin(t) ** power,
    )
    return points


def svg_document() -> str:
    path = " ".join(
        ("M" if index == 0 else "L") + f"{x:.2f},{y:.2f}"
        for index, (x, y) in enumerate(squircle_points())
    )
    path += " Z"
    x, y, width, height = cursor_box(CANVAS)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="body" gradientUnits="userSpaceOnUse" x1="512" y1="100" x2="512" y2="924">
      <stop offset="0" stop-color="#F7F7F8"/>
      <stop offset="1" stop-color="#E9E9EC"/>
    </linearGradient>
    <linearGradient id="sheen" gradientUnits="userSpaceOnUse" x1="512" y1="100" x2="512" y2="924">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.62"/>
      <stop offset="0.20" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="14" stdDeviation="12" flood-color="#000000" flood-opacity="0.22"/>
    </filter>
    <filter id="glow" x="-100%" y="-60%" width="300%" height="220%">
      <feGaussianBlur stdDeviation="16" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>
  <path d="{path}" fill="url(#body)" filter="url(#shadow)"/>
  <path d="{path}" fill="url(#sheen)"/>
  <rect x="{x}" y="{y}" width="{width}" height="{height}" fill="#34C759" filter="url(#glow)"/>
</svg>
"""


def write_png(path: Path, image) -> None:
    height, width, channels = image.shape
    if channels != 4:
        raise SystemExit(f"{path} is not RGBA")
    raw = b"".join(b"\x00" + image[y].tobytes() for y in range(height))
    compressed = zlib.compress(raw, 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.write_bytes(png)


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


def _numpy():
    global np
    if np is None:
        import numpy as imported

        np = imported
    return np


def gaussian_kernel(sigma: float):
    array = _numpy()
    if sigma <= 0.05:
        return array.asarray([1.0], dtype=array.float32)
    radius = max(1, int(math.ceil(sigma * 3)))
    offsets = array.arange(-radius, radius + 1, dtype=array.float32)
    kernel = array.exp(-0.5 * (offsets / sigma) ** 2)
    kernel /= kernel.sum()
    return kernel


def blur_alpha(alpha, sigma: float):
    array = _numpy()
    kernel = gaussian_kernel(sigma)
    if kernel.shape[0] == 1:
        return alpha
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


def squircle_coverage(px: int, samples: int = 4):
    array = _numpy()
    margin = MARGIN * px / CANVAS
    side = SQUIRCLE * px / CANVAS
    radius = CORNER_RADIUS * px / CANVAS
    half = side / 2
    inner = half - radius
    coverage = array.zeros((px, px), dtype=array.float32)
    xs = array.arange(px, dtype=array.float32)[None, :]
    ys = array.arange(px, dtype=array.float32)[:, None]
    for y_index in range(samples):
        for x_index in range(samples):
            y = ys + (y_index + 0.5) / samples
            x = xs + (x_index + 0.5) / samples
            local_x = x - margin
            local_y = y - margin
            qx = array.abs(local_x - half) - inner
            qy = array.abs(local_y - half) - inner
            ax = array.maximum(qx, 0) / radius
            ay = array.maximum(qy, 0) / radius
            inside = (ax**CORNER_EXPONENT + ay**CORNER_EXPONENT) <= 1.0
            in_box = (local_x >= 0) & (local_y >= 0) & (local_x <= side) & (local_y <= side)
            coverage += (inside & in_box).astype(array.float32)
    coverage /= float(samples * samples)
    return coverage


def over(base, rgb, alpha):
    array = _numpy()
    alpha = alpha[..., None]
    out_a = alpha + base[..., 3:4] * (1 - alpha)
    out_rgb = (rgb * alpha + base[..., :3] * base[..., 3:4] * (1 - alpha)) / array.maximum(out_a, 1e-6)
    base[..., :3] = out_rgb
    base[..., 3:4] = out_a


def render(px: int):
    array = _numpy()
    coverage = squircle_coverage(px)
    image = array.zeros((px, px, 4), dtype=array.float32)
    scale = px / CANVAS

    if px >= 64:
        offset = max(1, int(math.floor(SHADOW_OFFSET * scale + 0.5)))
        shifted = array.zeros_like(coverage)
        shifted[offset:, :] = coverage[:-offset, :]
        shadow = blur_alpha(shifted, SHADOW_SIGMA * scale) * SHADOW_OPACITY
        over(image, array.zeros((1, 1, 3), dtype=array.float32), shadow)

    top = array.array(TOP, dtype=array.float32).reshape(1, 1, 3) / 255
    bottom = array.array(BOTTOM, dtype=array.float32).reshape(1, 1, 3) / 255
    margin = MARGIN * scale
    side = SQUIRCLE * scale
    y = array.arange(px, dtype=array.float32).reshape(px, 1, 1)
    t = array.clip((y - margin) / side, 0, 1)
    gradient = top * (1 - t) + bottom * t
    over(image, array.broadcast_to(gradient, (px, px, 3)), coverage)

    sheen = array.clip(1 - t / SHEEN_REACH, 0, 1) ** 1.4 * SHEEN_STRENGTH
    sheen = sheen[:, 0, 0][:, None] * coverage
    white = array.ones((1, 1, 3), dtype=array.float32)
    over(image, white, sheen)

    x0, y0, width, height = cursor_box(px)
    cursor = array.zeros((px, px), dtype=array.float32)
    cursor[y0 : y0 + height, x0 : x0 + width] = 1
    if px <= 32:
        glow_sigma = 0.0
    elif px <= 64:
        glow_sigma = 1.15
    else:
        glow_sigma = GLOW_SIGMA * scale
    if glow_sigma > 0:
        glow = array.clip(blur_alpha(cursor, glow_sigma) * 0.8, 0, 0.7)
        glow = glow * (1 - cursor)
        green = array.array(CURSOR, dtype=array.float32).reshape(1, 1, 3) / 255
        over(image, green, glow)

    uint8 = array.clip(array.rint(image * 255), 0, 255).astype(array.uint8)
    uint8[y0 : y0 + height, x0 : x0 + width] = (CURSOR[0], CURSOR[1], CURSOR[2], 255)
    return uint8


def generate(root: Path, artifacts: Path | None) -> None:
    _numpy()
    svg_path = root / "Resources" / "AppIcon.svg"
    svg_path.parent.mkdir(parents=True, exist_ok=True)
    svg_path.write_text(svg_document(), encoding="utf-8")

    iconset = root / "Resources" / "AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    packed: list[tuple[str, bytes]] = []
    cache: dict[int, object] = {}
    master = None
    for filename, size, os_type in ICONSET:
        image = cache.get(size)
        if image is None:
            image = render(size)
            cache[size] = image
        png_path = iconset / filename
        write_png(png_path, image)
        packed.append((os_type, png_path.read_bytes()))
        if size == CANVAS:
            master = image
            (root / "Resources" / "AppIcon-1024.png").write_bytes(png_path.read_bytes())
    if master is None:
        raise SystemExit("the iconset has no 1024 image")
    icns_path = root / "Resources" / "AppIcon.icns"
    icns_path.write_bytes(pack_icns(packed))
    print(f"Wrote {svg_path}")
    print(f"Wrote {root / 'Resources' / 'AppIcon-1024.png'}")
    print(f"Wrote {icns_path}")
    if artifacts is not None:
        write_artifacts(artifacts, master, cache)


def write_artifacts(directory: Path, master, cache) -> None:
    array = _numpy()
    directory.mkdir(parents=True, exist_ok=True)
    master_path = directory / "supervim-app-icon-1024.png"
    write_png(master_path, master)
    light = composite_on(master, (245, 245, 247))
    write_png(directory / "supervim-app-icon-1024-on-light.png", light)

    tile = 128
    sizes = (16, 32, 64, 128, 256, 512, 1024)
    gap = 28
    pad = 32
    label = 22
    width = pad * 2 + len(sizes) * tile + (len(sizes) - 1) * gap
    height = pad * 2 + tile + label
    sheet = array.zeros((height, width, 4), dtype=array.uint8)
    sheet[..., :3] = (236, 236, 239)
    sheet[..., 3] = 255
    for index, size in enumerate(sizes):
        shown = fit_tile(cache[size], tile)
        shown = composite_on(shown, (245, 245, 247))
        x = pad + index * (tile + gap)
        y = pad
        sheet[y : y + tile, x : x + tile] = shown
        draw_label(sheet, str(size), x, y + tile + 4, tile)
    write_png(directory / "supervim-app-icon-sizes.png", sheet)
    print(f"Wrote previews in {directory}")


def composite_on(image, color: tuple[int, int, int]):
    array = _numpy()
    alpha = image[..., 3:4].astype(array.float32) / 255
    rgb = image[..., :3].astype(array.float32) * alpha + array.array(color, dtype=array.float32) * (1 - alpha)
    out = array.empty_like(image)
    out[..., :3] = array.clip(array.rint(rgb), 0, 255).astype(array.uint8)
    out[..., 3] = 255
    return out


def fit_tile(image, tile: int):
    array = _numpy()
    size = image.shape[0]
    if size == tile:
        return image
    if size < tile:
        if tile % size != 0:
            raise SystemExit(f"cannot scale {size} to {tile}")
        factor = tile // size
        return array.repeat(array.repeat(image, factor, axis=0), factor, axis=1)
    if size % tile != 0:
        raise SystemExit(f"cannot scale {size} to {tile}")
    factor = size // tile
    block = image.reshape(tile, factor, tile, factor, 4).astype(array.float32)
    return array.clip(array.rint(block.mean(axis=(1, 3))), 0, 255).astype(array.uint8)


DIGITS = {
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
}


def draw_label(image, text: str, left: int, top: int, tile: int) -> None:
    scale = 2
    glyph = 3 * scale
    gap = scale
    text_width = len(text) * glyph + (len(text) - 1) * gap
    x0 = left + (tile - text_width) // 2
    ink = (80, 80, 84, 255)
    for char_index, char in enumerate(text):
        rows = DIGITS[char]
        origin = x0 + char_index * (glyph + gap)
        for row_index, bits in enumerate(rows):
            for col_index, bit in enumerate(bits):
                if bit != "1":
                    continue
                y = top + row_index * scale
                x = origin + col_index * scale
                image[y : y + scale, x : x + scale] = ink


def read_png(path: Path):
    data = path.read_bytes()
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        raise SystemExit(f"{path} is not a PNG")
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
                raise SystemExit(f"{path} must be 8-bit non-interlaced RGBA")
        elif tag == b"IDAT":
            body += chunk
        elif tag == b"IEND":
            break
    if width is None or height is None:
        raise SystemExit(f"{path} has no IHDR")
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
        previous = unfilter(filter_type, scanline, previous)
        rows.append(previous)
    return width, height, rows


def unfilter(filter_type: int, scanline: bytearray, previous: bytearray) -> bytearray:
    out = bytearray(len(scanline))
    for index, value in enumerate(scanline):
        left = out[index - 4] if index >= 4 else 0
        up = previous[index]
        upper_left = previous[index - 4] if index >= 4 else 0
        if filter_type == 0:
            predicted = 0
        elif filter_type == 1:
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


def solid_cursor_bounds(rows, width: int, height: int) -> tuple[int, int, int]:
    count = 0
    min_x, min_y, max_x, max_y = width, height, -1, -1
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixel(rows, x, y)
            if alpha < 250 or abs(red - 52) > 2 or abs(green - 199) > 2 or abs(blue - 89) > 2:
                continue
            count += 1
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
    if count == 0:
        raise SystemExit("cursor block is missing")
    return count, max_x - min_x + 1, max_y - min_y + 1


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def check(root: Path) -> None:
    svg = (root / "Resources" / "AppIcon.svg").read_text(encoding="utf-8")
    require("1024" in svg, "SVG is not a 1024 canvas")
    require("#34C759" in svg, "SVG cursor is not #34C759")
    require("#F7F7F8" in svg and "#E9E9EC" in svg, "SVG gradient stops are missing")
    require("<text" not in svg, "SVG must not draw text")

    png_path = root / "Resources" / "AppIcon-1024.png"
    width, height, rows = read_png(png_path)
    require((width, height) == (1024, 1024), f"master PNG is {width}x{height}")
    require(pixel(rows, 512, 512) == (52, 199, 89, 255), f"center pixel is {pixel(rows, 512, 512)}")
    for corner in ((0, 0), (1023, 0), (0, 1023), (1023, 1023)):
        require(pixel(rows, *corner)[3] == 0, f"canvas corner {corner} is not transparent")

    top = pixel(rows, 512, 160)
    bottom = pixel(rows, 512, 860)
    require(top[3] == 255 and bottom[3] == 255, "squircle interior is not opaque")
    require(max(top[:3]) - min(top[:3]) <= 8, f"top fill is tinted: {top}")
    require(max(bottom[:3]) - min(bottom[:3]) <= 8, f"bottom fill is tinted: {bottom}")
    require(230 <= top[0] <= 255 and 220 <= bottom[0] <= 250, f"fill is out of range: {top} {bottom}")
    require(top[0] > bottom[0], f"gradient does not lighten toward the top: {top} vs {bottom}")

    near = pixel(rows, 478, 512)
    far = pixel(rows, 250, 512)
    require((near[1] - near[0]) > (far[1] - far[0]) + 20, f"cursor glow is missing: near {near}, far {far}")

    shadow = False
    for y in range(930, 1016):
        red, green, blue, alpha = pixel(rows, 512, y)
        if 8 <= alpha <= 140 and max(red, green, blue) < 90:
            shadow = True
            break
    require(shadow, "drop shadow under the squircle is missing")

    images = icns_pngs(root / "Resources" / "AppIcon.icns")
    expected = {os_type: size for _, size, os_type in ICONSET}
    for os_type, size in expected.items():
        blob_path = root / "Resources" / f".check-{os_type}.png"
        blob_path.write_bytes(images[os_type])
        try:
            got_w, got_h, got_rows = read_png(blob_path)
        finally:
            blob_path.unlink()
        require((got_w, got_h) == (size, size), f"{os_type} is {got_w}x{got_h}")
        if size == 1024:
            require(pixel(got_rows, 512, 512) == (52, 199, 89, 255), "ic10 center is not the cursor green")
        if size <= 64:
            count, box_w, box_h = solid_cursor_bounds(got_rows, size, size)
            minimum = {16: (32, 4, 9), 32: (80, 6, 16), 64: (160, 8, 20)}[size]
            require(
                count >= minimum[0] and box_w >= minimum[1] and box_h >= minimum[2] and box_h > box_w,
                f"{os_type} cursor is {count}px in a {box_w}x{box_h} box, need {minimum}",
            )
            require(pixel(got_rows, 0, 0)[3] == 0, f"{os_type} corner is not transparent")
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
