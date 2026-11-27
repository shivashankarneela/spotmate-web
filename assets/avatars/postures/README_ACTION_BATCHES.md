# HaloBerry illustrated avatar action batches

**Recommended: Upload just one final file** into this folder on `feature/haloberry-space100-asset-bosses`:

`HaloBerry_100_Postures_Aligned.zip` — all 100 transparent WebP poses, centered to exactly x=512 and anchored at baseline y=1004, plus all five catalogs. Build automatically extracts the 100 images, and excludes the ZIP from deployed assets.

Individual per-batch uploads below are supported only if the unified archive is unavailable:

- `spotmate_default_actions_batch1.zip` — Arjun, Kabir, Ananya, Meera (20 poses)
- `spotmate_default_actions_batch2.zip` — Rohan, Dev, Zoya, Kavya (20 poses; supplied and validated locally; GitHub upload pending)
- `spotmate_default_actions_batch3.zip` — Vikram, Aditya, Riya, Tara (20 poses; locally verified and optimized; GitHub upload pending)
- `spotmate_default_actions_batch4.zip` — Siddharth, Neel, Diya, Nisha (20 poses; validated and optimized; GitHub ZIP upload pending)
- `spotmate_default_actions_batch5.zip` — Ishan, Aryan, Priya, Sana (20 poses; verified and optimized; GitHub upload pending)

**Choose "Commit directly to feature/haloberry-space100-asset-bosses", not "Create a new branch".**

`scripts/install_avatar_actions.py` validates each archive against its `actions_catalog.json` and extracts only its 1024px transparent WEBP files to `assets/avatars/postures/` before web builds. It also writes a per-batch action catalog. PNG and JPG duplicates are retained only in the ZIP to avoid unnecessarily bloating the app.

This preserves the seven existing `chair.webp`, `dance.webp`, `namaste.webp`, `relaxed.webp`, `signature.webp`, `thumb.webp`, and `wave.webp` legacy sprite sheets.

**Integration status:** The Flutter avatar gallery, permanent posture selector, opt-in 30-second auto change, lobby rendering and profile persistence have been implemented on the development branch. Existing illustrated members in the production database have gender-matched avatar IDs. The actual artwork displays only after the aligned ZIP is committed and a new build is made. No production app deployment is authorized by an upload.
