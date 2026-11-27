# HaloBerry illustrated avatar action batches

Upload exactly these files into **this folder** on the `feature/haloberry-space100-asset-bosses` development branch:

- `spotmate_default_actions_batch1.zip` — Arjun, Kabir, Ananya, Meera (20 poses)
- `spotmate_default_actions_batch2.zip` — next characters (pending)
- `spotmate_default_actions_batch3.zip` — pending
- `spotmate_default_actions_batch4.zip` — pending
- `spotmate_default_actions_batch5.zip` — pending

**Choose "Commit directly to feature/haloberry-space100-asset-bosses", not "Create a new branch".**

`scripts/install_avatar_actions.py` validates each archive against its `actions_catalog.json` and extracts only its 1024px transparent WEBP files to `assets/avatars/postures/` before web builds. It also writes a per-batch action catalog. PNG and JPG duplicates are retained only in the ZIP to avoid unnecessarily bloating the app.

This preserves the seven existing `chair.webp`, `dance.webp`, `namaste.webp`, `relaxed.webp`, `signature.webp`, `thumb.webp`, and `wave.webp` legacy sprite sheets.

**Integration status:** Extraction is prepared. The new poses will not become selectable or animated until the avatar widget/picker is updated to use action catalogs after the remaining batches arrive. No production release is authorized by an upload.
