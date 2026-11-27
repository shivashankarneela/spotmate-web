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
    # The 20 original character illustrations were already uploaded to
    # assets/avatars/. Install only WebP artwork, not PNG/JPG copies.
    portraits = ROOT / "assets/avatars/HaloBerry_Default_20_Clean_Transparent.zip"
    cleaned_portraits = portraits.is_file()
    if not cleaned_portraits:
        portraits = ROOT / "assets/avatars/spotmate_default_avatars_20_hd.zip"
    if portraits.is_file():
        target = ROOT / "assets/avatars/default"
        target.mkdir(parents=True, exist_ok=True)
        with ZipFile(portraits) as z:
            catalog = json.loads(z.read("avatars_catalog.json"))
            avatars = catalog["avatars"]
            if len(avatars) != 20:
                raise ValueError("Expected 20 original avatar illustrations")
            found = set()
            for avatar in avatars:
                avatar_id = avatar["id"]
                path = avatar_id + ".webp" if cleaned_portraits else avatar["files"]["webp"]
                if avatar_id in found or not path.endswith(avatar_id + ".webp"):
                    raise ValueError(f"Unexpected default avatar: {avatar_id}")
                found.add(avatar_id)
                data = z.read(path)
                if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
                    raise ValueError(f"Invalid default WebP: {avatar_id}")
                (target / (avatar_id + ".webp")).write_bytes(data)
        portraits.unlink()
        print("[HaloBerry avatars] Installed 20 original character portraits")
    seen: set[str] = set()
    total = 0
    # Lightweight option: one authentic first-pose WebP per character.
    # Full five-batch artwork takes precedence when supplied later.
    single = POSTURES / "HaloBerry_Default_20_Posture_Images.zip"
    complete = any((POSTURES / name).is_file() for name in (
        "HaloBerry_100_Postures_Clean_Transparent.zip",
        "HaloBerry_100_Postures_Aligned.zip",
        "HaloBerry_100_Postures_All_Batches.zip",
    ))
    has_batches = any((POSTURES / f"spotmate_default_actions_batch{i}.zip").is_file()
                      for i in range(1, MAX_BATCH + 1))
    if single.is_file() and not complete and not has_batches:
        with ZipFile(single) as z:
            manifest = json.loads(z.read("default_postures_manifest.json"))
            characters = manifest.get("characters", {})
            if len(characters) != 20:
                raise ValueError("Default avatar pack must contain 20 characters")
            for character_id, info in characters.items():
                if not character_id.startswith(("boy_", "girl_")):
                    raise ValueError("Invalid avatar character")
                name = info["file"]
                if name != Path(name).name or not name.endswith(".webp"):
                    raise ValueError(f"Invalid avatar filename: {name}")
                data = z.read(name)
                if not data.startswith(b"RIFF") or data[8:12] != b"WEBP":
                    raise ValueError(f"Invalid default avatar WebP: {name}")
                (POSTURES / name).write_bytes(data)
            (POSTURES / "default_postures_manifest.json").write_text(
                json.dumps(manifest, indent=2), encoding="utf-8")
        single.unlink()
        print("[HaloBerry postures] Installed 20 original default illustrated poses")
        return
    # Prefer artwork with verified centered x-axis and matched foot baseline.
    combined = POSTURES / "HaloBerry_100_Postures_Clean_Transparent.zip"
    if not combined.is_file():
        combined = POSTURES / "HaloBerry_100_Postures_Aligned.zip"
    if not combined.is_file():
        combined = POSTURES / "HaloBerry_100_Postures_All_Batches.zip"
    if combined.is_file():
        # One-file deployment: unpack all 20 unique characters, 100 original
        # transparent WebP poses, plus their 5 signed-off catalogs.
        with ZipFile(combined) as z:
            files = z.namelist()
            catalogs = sorted(f for f in files if f.startswith("catalogs/") and f.endswith(".json"))
            if len(catalogs) != 5:
                raise ValueError("Combined archive must have five action catalogs")
            for catalog_path in catalogs:
                catalog = json.loads(z.read(catalog_path))
                count = 0
                for character in catalog["characters"]:
                    character_id = character["character_id"]
                    if not character_id.startswith(("boy_", "girl_")):
                        raise ValueError("Invalid character identifier")
                    for action in character["actions"]:
                        source = action["files"]["webp"]
                        parts = Path(source).parts
                        if len(parts) != 3 or parts[:2] != (character_id, "webp"):
                            raise ValueError(f"Invalid archived path: {source}")
                        filename = parts[-1]
                        if filename in seen: raise ValueError(f"Duplicate pose: {filename}")
                        seen.add(filename)
                        data = z.read(source)
                        if not data.startswith(b"RIFF") or data[8:12] != b"WEBP":
                            raise ValueError(f"Invalid WebP: {source}")
                        (POSTURES / filename).write_bytes(data)
                        count += 1
                if count != 20: raise ValueError(f"Unexpected batch image count: {count}")
                (POSTURES / Path(catalog_path).name).write_text(
                    json.dumps(catalog, indent=2, ensure_ascii=False), encoding="utf-8",
                )
                total += count
        if total != 100: raise ValueError(f"Expected 100 poses, got {total}")
        combined.unlink()  # no duplicate ZIP added to the Flutter asset bundle
        print("[HaloBerry postures] Installed all 100 poses from one ZIP")
        return
    # Small, curated pack: one neutral initial illustration for each of
    # the 20 original characters. Later full batches can replace this pack
    # to enable all five selectable poses.
    defaults = POSTURES / "HaloBerry_Default_20_Posture_Images.zip"
    if defaults.is_file():
        with ZipFile(defaults) as z:
            manifest = json.loads(z.read("default_postures_manifest.json"))
            characters = manifest.get("characters", {})
            expected = {f"{gender}_{n:02d}" for gender in ("boy", "girl") for n in range(1, 11)}
            if set(characters) != expected:
                raise ValueError("Default avatar pack must have exactly 10 boys and 10 girls")
            for character_id, record in characters.items():
                filename = record["file"]
                if "/" in filename or "\\\\" in filename or not filename.startswith(character_id + "_01_") or not filename.endswith(".webp"):
                    raise ValueError(f"Invalid default posture filename: {filename}")
                data = z.read(filename)
                if not data.startswith(b"RIFF") or data[8:12] != b"WEBP":
                    raise ValueError(f"Invalid WebP: {filename}")
                (POSTURES / filename).write_bytes(data)
            (POSTURES / "default_postures_manifest.json").write_text(
                json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8",
            )
        defaults.unlink()
        print("[HaloBerry postures] Installed 20 original stationary default illustrations")
        return
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
                # This ZIP is the source archive, not a runtime Flutter asset.
                # Remove it only in the ephemeral build checkout, after successful
                # extraction, so the 16 MB ZIP is not bundled into the web app.
                archive.unlink()
                print(f"[HaloBerry postures] Batch {batch}: {count} validated WebP poses extracted")
        except (BadZipFile, KeyError, ValueError) as exc:
            raise RuntimeError(f"Batch {batch} ZIP validation failed: {exc}") from exc

    if total:
        print(f"[HaloBerry postures] {total} total illustrated poses installed.")
    else:
        print("[HaloBerry postures] No ZIPs committed; legacy posture sprites unchanged.")


if __name__ == "__main__":
    main()
