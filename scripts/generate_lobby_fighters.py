"""Generate small transparent lobby artwork from the existing Store assets."""

import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "store"
OUTPUT = ROOT / "assets" / "lobby_fighters"
RENDERER = ROOT / "lib" / "features" / "store" / "presentation" / "fighter_artwork.dart"
MAX_BYTES = 40_000


def save_thumbnail(image, path):
    image = image.convert("RGBA")
    image.thumbnail((320, 320), Image.Resampling.LANCZOS)
    alpha = image.getchannel("A")
    if alpha.getbbox() is None or alpha.getextrema()[0] != 0:
        raise ValueError(f"Expected a visible cutout with transparency: {path}")
    for size in (320, 256, 224, 192, 160):
        image.thumbnail((size, size), Image.Resampling.LANCZOS)
        for quality in (90, 84, 76, 66):
            image.save(path, "WEBP", quality=quality, method=6)
            if path.stat().st_size <= MAX_BYTES:
                return
    raise ValueError(f"Thumbnail exceeds {MAX_BYTES} bytes: {path}")


def main():
    code = RENDERER.read_text()
    catalog = code.split("};", 1)[0]
    names = re.findall(r"^  '([a-z_]+)': \[", catalog, re.MULTILINE)
    bounds = re.findall(r"\(\[([\d, ]+)\], \[([\d, ]+)\]\)", code)
    if len(names) != 20 or len(bounds) * 5 != len(names):
        raise ValueError("Store catalog and combat sheet bounds do not match.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for group, (columns, rows) in enumerate(bounds):
        x = [int(value) for value in columns.split(",")]
        y = [int(value) for value in rows.split(",")]
        with Image.open(SOURCE / f"fighter_combat_{group}.webp") as sheet:
            if sheet.size != (x[-1], y[-1]) or len(x) != 6 or len(y) != 6:
                raise ValueError(f"Unexpected grid dimensions for combat sheet {group}.")
            for col, name in enumerate(names[group * 5 : group * 5 + 5]):
                for pose in range(5):
                    cutout = sheet.crop((x[col] + 2, y[pose] + 2, x[col + 1] - 2, y[pose + 1] - 2))
                    save_thumbnail(cutout, OUTPUT / f"{name}_pose_{pose}.webp")
                for variant in ("normal", "luxury"):
                    item = f"{name}_{variant}"
                    with Image.open(SOURCE / f"hd_{item}.webp") as image:
                        save_thumbnail(image, OUTPUT / f"{item}.webp")


if __name__ == "__main__":
    main()
