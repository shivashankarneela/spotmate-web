#!/usr/bin/env python3
"""Install the user-provided HaloBerry background and enemy artwork at build time.

The ZIP is deliberately a single optional source binary so no local shell steps are
needed. Once assets/space100/HaloBerry_Space100_Artwork_Pack.zip is checked into
this branch, Vercel's existing build script extracts it before Flutter compilation.
"""
from __future__ import annotations

from pathlib import Path
from zipfile import ZipFile, BadZipFile

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "assets/space100/HaloBerry_Space100_Artwork_Pack.zip"
DEST_ROOT = ROOT / "web/games/space_shooter/art"


def main() -> None:
    if not ARCHIVE.is_file():
        print("[Space100 art] Bundle not present; using built-in procedural art.")
        return
    backgrounds = {
        f"web/games/space_shooter/art/backgrounds/level_{i:03d}.webp"
        for i in range(1, 101)
    }
    enemies = {
        f"web/games/space_shooter/art/enemies/galaxy_{i:02d}.webp"
        for i in range(1, 11)
    }
    required = backgrounds | enemies
    try:
        with ZipFile(ARCHIVE) as source:
            names = set(source.namelist())
            missing = sorted(required - names)
            if missing:
                raise RuntimeError(
                    f"Missing {len(missing)} Space100 artwork files; first: {missing[0]}"
                )
            # Extract only the exact expected relative artwork paths.
            # Never allow supplied archives to write elsewhere in the repository.
            for entry in sorted(required):
                dest = ROOT / entry
                dest.resolve().relative_to(DEST_ROOT.resolve())
                dest.parent.mkdir(parents=True, exist_ok=True)
                payload = source.read(entry)
                if len(payload) < 500:
                    raise RuntimeError(f"Empty or invalid artwork file: {entry}")
                dest.write_bytes(payload)
            print("[Space100 art] Installed 100 backgrounds and 10 enemy sprite sheets.")
    except BadZipFile as exc:
        raise RuntimeError("Invalid Space100 artwork ZIP") from exc


if __name__ == "__main__":
    main()
