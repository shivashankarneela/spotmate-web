# Spotmate secure Supabase integration — developer notes

## Scope of this branch
- Points Flutter to the new Supabase project: `mepulcdlighuiwgbutnx`.
- Reads the **public** Supabase publishable key from `SUPABASE_PUBLISHABLE_KEY` at Flutter build time; **never** embed service-role or secret keys.
- Uses the `join_hotspot_with_pin` RPC instead of directly inserting hotspot memberships; valid venue PIN check-ins grant one-hour sessions.
- Filters expired sessions and removes the previous client-side 30-minute fast-unlock bypass.
- Disables the misleading GPS verification button until real location proof is implemented.
- Uses private `chat_media` paths and signed image URLs rather than publicly accessible chat images.

## Build and release
The Vercel project currently serves existing prebuilt Flutter assets in `public/`. Editing Dart source **alone** does not rebuild `public/main.dart.js`. A Vercel READY status is not proof that the updated Flutter code is live.

Run with a compatible Flutter SDK:
```bash
flutter pub get
flutter analyze
flutter test
flutter build web --release --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```
Then deploy the freshly generated `build/web` output to Vercel (via the project's `public/` workflow or an explicit build pipeline). Do not commit environment secrets. Configure production/preview auth redirect URLs.

## Known limitations / blockers before merge
- No Flutter SDK was available in the authoring environment; static edits were made, but **compile, unit tests, browser tests and end-to-end tests are NOT verified**.
- No approved venues or venue PIN hashes have yet been provisioned; check-in cannot be exercised against real venues.
- Real GPS proof, video/audio transport, moderation and account lifecycle work remain incomplete.
- Supabase database compatibility with every existing Flutter query requires integration testing; especially authentication, connection requests, chat and calls.
- Private signed chat URLs expire; long-running conversations may need an expiry-aware refresh cache.
- Keep this work in a draft PR until a clean Flutter build and test pass; do not merge blindly.
