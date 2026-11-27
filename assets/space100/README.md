# HaloBerry Space Shooter artwork

The attached `HaloBerry_Space100_Artwork_Pack.zip` is the single bundle needed to activate the supplied art in Vercel previews.

Upload it to **this directory**, with the exact repository path:

`assets/space100/HaloBerry_Space100_Artwork_Pack.zip`

The existing build script automatically extracts 100 WEBP level backgrounds and 10 chapter enemy sprite sheets to:

- `web/games/space_shooter/art/backgrounds/level_001.webp` through `level_100.webp`
- `web/games/space_shooter/art/enemies/galaxy_01.webp` through `galaxy_10.webp`

The app fetches only the current level's background and enemy sheet. The archive is not required for the game to start: absent files use the procedural fallback, but **the user's source images are not visible until the archive is actually present here**.

The enemy ZIP is a ten-sheet catalogue of 123 regular enemies, **not** a complete collection of 100 unique boss illustrations. Boss artwork can be assigned later without changing the 100 attack scripts.

Do not put any passwords, tokens or account data in this ZIP.
