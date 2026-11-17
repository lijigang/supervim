#!/usr/bin/env python3
"""Rasterize a few after-images of the Supervim chrome for the docs.

These are design previews, not AppKit snapshots. SF Mono and SF Rounded are
substituted with DejaVu, which is what this Linux checkout can draw. The
macOS CI job renders the real views; see scripts/render-ui-snapshots.sh.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "ui-polish"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
MONO_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
SANS_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
CJK = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"

GREEN = (52, 199, 89, 255)
LIGHT_FILL = (247, 247, 248, 247)
LIGHT_TEXT = (28, 28, 30, 255)
LIGHT_MATCHED = (15, 122, 50, 255)
LIGHT_SECONDARY = (110, 110, 115, 255)
LIGHT_CAP = (255, 255, 255, 255)
LIGHT_STROKE = (28, 28, 30, 41)
DARK_FILL = (36, 36, 38, 245)
DARK_TEXT = (245, 245, 247, 255)
DARK_MATCHED = GREEN
DARK_SECONDARY = (174, 174, 178, 255)
DARK_CAP = (58, 58, 60, 255)
DARK_STROKE = (245, 245, 247, 71)
BANDS = [
    (255, 214, 10, 255),
    (0, 122, 255, 255),
    (255, 255, 255, 255),
    (52, 199, 89, 255),
    (0, 0, 0, 255),
]


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def rounded(draw: ImageDraw.ImageDraw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def shadow_behind(base: Image.Image, box, radius: int, blur: int = 6, alpha: int = 56) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius=radius, fill=(0, 0, 0, alpha))
    base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def icon_mark(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    radius = max(2, int(size * 0.22))
    rounded(draw, (1, 1, size - 2, size - 2), radius, (247, 247, 248, 255), (28, 28, 30, 40), 1)
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(overlay).rectangle((1, size // 2, size - 2, size - 2), fill=(0, 0, 0, 16))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((1, 1, size - 2, size - 2), radius=radius, fill=255)
    image.alpha_composite(Image.composite(overlay, Image.new("RGBA", (size, size), (0, 0, 0, 0)), mask))
    cw, ch = max(2, int(size * 0.16)), int(size * 0.46)
    x = (size - cw) // 2
    y = (size - ch) // 2
    ImageDraw.Draw(image).rounded_rectangle((x, y, x + cw, y + ch), radius=1, fill=GREEN)
    return image


def badge(label: str, typed: str, dark: bool) -> Image.Image:
    matched_font = font(MONO_BOLD, 24)
    rest_font = font(MONO, 24)
    matched = ""
    rest = label
    if typed and label.lower().startswith(typed.lower()):
        count = len(typed)
        matched, rest = label[:count], label[count:]
    def width(text, face):
        if not text:
            return 0
        return int(face.getlength(text))
    text_w = width(matched, matched_font) + width(rest, rest_font)
    pad_x, cursor_w, gap, shadow = 14, 6, 10, 10
    inner_w = pad_x + cursor_w + gap + text_w + pad_x
    inner_h = 24 + 12
    width_px = inner_w + shadow * 2
    height_px = max(inner_h + shadow * 2, 52)
    image = Image.new("RGBA", (width_px, height_px), (0, 0, 0, 0))
    pill = (shadow, shadow, width_px - shadow - 1, height_px - shadow - 1)
    shadow_behind(image, pill, 12)
    fill = DARK_FILL if dark else LIGHT_FILL
    stroke = DARK_STROKE if dark else LIGHT_STROKE
    text_color = DARK_TEXT if dark else LIGHT_TEXT
    match_color = DARK_MATCHED if dark else LIGHT_MATCHED
    draw = ImageDraw.Draw(image)
    rounded(draw, pill, 12, fill, stroke, 2)
    cy = height_px // 2
    cursor = (pill[0] + pad_x, cy - 12, pill[0] + pad_x + cursor_w, cy + 12)
    draw.rounded_rectangle(cursor, radius=2, fill=GREEN)
    x = cursor[2] + gap
    baseline = cy - 12
    if matched:
        draw.text((x, baseline), matched, font=matched_font, fill=match_color)
        x += width(matched, matched_font)
    if rest:
        draw.text((x, baseline), rest, font=rest_font, fill=text_color)
    return image


def bands(size) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 255))
    draw = ImageDraw.Draw(image)
    slice_w = size[0] / len(BANDS)
    for index, color in enumerate(BANDS):
        draw.rectangle((int(slice_w * index), 0, int(slice_w * (index + 1)) + 1, size[1]), fill=color)
    return image


def paste_center_row(base: Image.Image, tiles: list[Image.Image]) -> None:
    gap = 36
    total = sum(tile.width for tile in tiles) + gap * (len(tiles) - 1)
    x = (base.width - total) // 2
    y = (base.height - tiles[0].height) // 2
    for tile in tiles:
        base.alpha_composite(tile, (x, y + (tiles[0].height - tile.height) // 2))
        x += tile.width + gap


def hints(dark: bool) -> Image.Image:
    image = bands((1280, 280))
    tiles = [
        badge("S", "s", dark),
        badge("SA", "s", dark),
        badge("D", "", dark),
        badge("JK", "j", dark),
    ]
    paste_center_row(image, tiles)
    return image


def help_sheet() -> Image.Image:
    width, height = 1280, 760
    image = Image.new("RGBA", (width, height), (236, 236, 238, 255))
    panel = (40, 30, width - 40, height - 30)
    shadow_behind(image, panel, 28, blur=14, alpha=40)
    draw = ImageDraw.Draw(image)
    rounded(draw, panel, 28, (247, 247, 248, 242), (28, 28, 30, 36), 2)
    draw.text((72, 58), "Shortcuts", font=font(SANS_BOLD, 36), fill=LIGHT_TEXT)
    subtitle = "? or Esc to close"
    face = font(SANS, 22)
    draw.text((panel[2] - 72 - int(face.getlength(subtitle)), 68), subtitle, font=face, fill=LIGHT_SECONDARY)
    draw.line((72, 118, panel[2] - 72, 118), fill=(28, 28, 30, 36), width=2)

    columns = [
        (
            72,
            [
                ("SCROLL", [("j", "Scroll down", ""), ("k", "Scroll up", ""), ("gg", "Scroll to the top", ""), ("G", "Scroll to the bottom", "")]),
                ("HINTS", [("f", "Hint", ""), ("F", "Command-click hint", "Command-click · differs from Vimium")]),
                ("FIND", [("/", "Find with the app shortcut", "Command+F · differs from Vimium"), ("yy", "Copy URL", "Command+L, Command+C · Safari, Chromium")]),
            ],
        ),
        (
            680,
            [
                ("NAVIGATION", [("H", "History back", "Command+["), ("L", "History forward", "Command+]"), ("x", "Close", "Command+W"), ("t", "New", "Command+T")]),
                ("MODES", [("gi", "Focus the first input", ""), ("i", "Insert", ""), ("Esc", "Escape", ""), ("?", "Show help", "differs from Vimium")]),
            ],
        ),
    ]
    for origin, sections in columns:
        y = 142
        for title, rows in sections:
            draw.text((origin, y), title, font=font(SANS_BOLD, 18), fill=LIGHT_SECONDARY)
            y += 32
            for keys, summary, note in rows:
                cap_face = font(MONO_BOLD, 22)
                cap_w = max(44, int(cap_face.getlength(keys)) + 20)
                cap = (origin, y, origin + cap_w, y + 32)
                rounded(draw, cap, 8, LIGHT_CAP, (28, 28, 30, 40), 2)
                tw = int(cap_face.getlength(keys))
                draw.text((origin + (cap_w - tw) / 2, y + 4), keys, font=cap_face, fill=LIGHT_TEXT)
                draw.text((origin + cap_w + 14, y + (2 if note else 4)), summary, font=font(SANS, 24), fill=LIGHT_TEXT)
                if note:
                    draw.text((origin + cap_w + 14, y + 28), note, font=font(SANS, 16), fill=LIGHT_SECONDARY)
                y += 56 if note else 42
            y += 16
    return image


def status_and_banner() -> Image.Image:
    image = Image.new("RGBA", (1280, 320), (244, 244, 246, 255))
    bar = Image.new("RGBA", (1280, 88), (246, 246, 247, 255))
    image.alpha_composite(bar, (0, 0))
    draw = ImageDraw.Draw(image)
    glyphs = [
        ("normal", "Normal"),
        ("insert", "Insert"),
        ("paused", "Paused"),
    ]
    for index, (kind, title) in enumerate(glyphs):
        x = 80 + index * 220
        ink = (20, 20, 22, 255)
        if kind == "normal":
            draw.rounded_rectangle((x, 28, x + 10, 60), radius=2, fill=ink)
        elif kind == "insert":
            draw.rectangle((x + 8, 30, x + 11, 58), fill=ink)
            draw.rectangle((x, 28, x + 20, 32), fill=ink)
            draw.rectangle((x, 56, x + 20, 60), fill=ink)
        else:
            draw.rectangle((x, 28, x + 7, 60), fill=ink)
            draw.rectangle((x + 12, 28, x + 19, 60), fill=ink)
        draw.text((x + 36, 30), title, font=font(SANS, 22), fill=ink)
    toast = badge_banner()
    image.alpha_composite(toast, ((1280 - toast.width) // 2, 150))
    return image


def badge_banner() -> Image.Image:
    message = "没找到可点击元素"
    face = font(CJK, 26)
    text_w = int(face.getlength(message))
    width, height = text_w + 120, 88
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    box = (6, 8, width - 7, height - 10)
    shadow_behind(image, box, 18, blur=8, alpha=48)
    draw = ImageDraw.Draw(image)
    rounded(draw, box, 18, LIGHT_FILL, LIGHT_STROKE, 2)
    mark = icon_mark(32)
    image.alpha_composite(mark, (24, 28))
    draw.text((68, 28), message, font=face, fill=LIGHT_TEXT)
    return image


def permissions() -> Image.Image:
    image = Image.new("RGBA", (1000, 640), (232, 232, 234, 255))
    panel = (40, 36, 960, 600)
    shadow_behind(image, panel, 18, blur=12, alpha=36)
    draw = ImageDraw.Draw(image)
    rounded(draw, panel, 16, (246, 246, 247, 255), None, 1)
    # Title bar
    draw.rectangle((40, 36, 960, 92), fill=(236, 236, 238, 255))
    draw.text((430, 52), "Supervim Needs Permissions", font=font(SANS, 18), fill=LIGHT_SECONDARY)
    mark = icon_mark(64)
    image.alpha_composite(mark, (80, 120))
    draw.text((164, 128), "Supervim Needs Permissions", font=font(SANS_BOLD, 32), fill=LIGHT_TEXT)
    body = (
        "Supervim needs Accessibility and Input Monitoring.\n"
        "Open the System Settings pane for each one and turn Supervim on."
    )
    draw.multiline_text((80, 220), body, font=font(SANS, 22), fill=LIGHT_TEXT, spacing=8)
    buttons = ["Open Accessibility Settings", "Open Input Monitoring Settings"]
    y = 340
    for title in buttons:
        rounded(draw, (80, y, 560, y + 44), 10, (255, 255, 255, 255), (28, 28, 30, 40), 2)
        draw.text((100, y + 10), title, font=font(SANS, 20), fill=LIGHT_TEXT)
        draw.text((500, y + 8), "↗", font=font(SANS, 22), fill=LIGHT_SECONDARY)
        y += 60
    rounded(draw, (80, 500, 280, 548), 10, (0, 122, 255, 255))
    draw.text((112, 512), "Check Again", font=font(SANS_BOLD, 20), fill=(255, 255, 255, 255))
    return image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    images = {
        "hints-light.png": hints(False),
        "hints-dark.png": hints(True),
        "help-light.png": help_sheet(),
        "status-and-banner.png": status_and_banner(),
        "permissions-light.png": permissions(),
    }
    for name, image in images.items():
        path = OUT / name
        image.save(path, "PNG", optimize=True)
        print(f"{path.relative_to(ROOT)} {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
