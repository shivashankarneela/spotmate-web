#!/usr/bin/env python3
"""Expand HaloBerry illustrated avatar action ZIPs into Flutter's existing posture asset directory.

The GitHub uploads remain compressed to make batches easy to manage.
Only WEBP source images are deployed; PNG/JPG duplicates stay inside archives.
No existing 7 legacy posture sprites are modified.
"""
from __future__ import annotations

import json
from pathlib import Path
from zipfile import BadZipFile, ZipFile

ROOT = Path(__file__).resolve().parents[1]
POSTURES = ROOT / "assets/avatars/postures"
MAX_BATCH = 5


def main() -> None:
    seen: set[str] = set()
    total = 0
    for batch in range(1, MAX_BATCH + 1):
        archive = POSTURES / f"spotmate_default_actions_batch{batch}.zip"
        if not archive.is_file():
            continue
        try:
            with ZipFile(archive) as z:
                catalog = json.loads(z.read("actions_catalog.json"))
                characters = catalog.get("characters", [])
                if not isinstance(characters, list) or not characters:
                    raise ValueError("Action catalog has no characters")
                count = 0
                for character in characters:
                    character_id = character["character_id"]
                    if not character_id.startswith(("boy_", "girl_")):
                        raise ValueError(f"Unsupported character ID {character_id!r}")
                    for action in character["actions"]:
                        source = action["files"]["webp"]
                        parts = Path(source).parts
                        if len(parts) != 3 or parts[0] != character_id or parts[1] != "webp" or not source.endswith(".webp"):
                            raise ValueError(f"Unexpected asset path {source!r}")
                        name = parts[-1]
                        if name in seen:
                            raise ValueError(f"Duplicate posture filename across batches: {name}")
                        seen.add(name)
                        image = z.read(source)
                        if not image.startswith(b"RIFF") or image[8:12] != b"WEBP":
                            raise ValueError(f"Invalid WebP asset: {source}")
                        # Flat placement ensures pubspec's existing
                        # assets/avatars/postures/ entry bundles the images.
                        (POSTURES / name).write_bytes(image)
                        count += 1
                if count != catalog.get("total_images"):
                    raise ValueError(f"Batch {batch} count mismatch: {count}")
                (POSTURES / f"actions_catalog_batch{batch}.json").write_text(
                    json.dumps(catalog, indent=2, ensure_ascii=False),
                    encoding="utf-8",
                )
                total += count
                print(f"[HaloBerry postures] Batch {batch}: {count} validated WebP poses extracted")
        except (BadZipFile, KeyError, ValueError) as exc:
            raise RuntimeError(f"Batch {batch} ZIP validation failed: {exc}") from exc

    if total:
        print(f"[HaloBerry postures] {total} total illustrated poses installed.")
    else:
        print("[HaloBerry postures] No ZIPs committed; legacy posture sprites unchanged.")


if __name__ == "__main__":
    main()
