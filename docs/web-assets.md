# Pinned Anki web assets

Extracted without modification from the official public AnkiDroid backend AAR:

- Maven: `io.github.david-allison:anki-android-backend:0.1.72-anki26.09.3`
- AAR SHA256: `a859d4581922c5ba1e71615c8ab25832ffb24fc9e53531170ad9c73a25c1f8c2`
- Source: https://github.com/ankidroid/Anki-Android-Backend (Anki submodule 26.09.3)
- Files under `ios/AnkiPad/Resources/backend/` correspond to `assets/backend/`, except the additional `js/ankidroid-js-api.js` described below.
- `licenses-ts.json` and `licenses-cargo.json` retain the upstream dependency/license metadata.
- MathJax, jQuery and the compiled Svelte interface retain their original upstream notices.

Only public upstream assets are included. The supplied user APK is not uploaded.

The additional unmodified `js/ankidroid-js-api.js` is the public AnkiDroid JavaScript API wrapper from `AnkiDroid/src/main/assets/scripts/js-api.js` at tag `v2.26.0alpha7`, commit `44a4476361175a31d9e212b24d6726411f7f3a5c`. It is covered by the upstream GPL-3.0-or-later project license (full text: [AnkiDroid-GPL-3.0.txt](../licenses/AnkiDroid-GPL-3.0.txt)). The native iPad adapter currently implements current-card metadata, reveal/answer and current-card mutations, plus a separate native JavaScript TTS queue; other endpoints report unsupported explicitly. This is partial API compatibility, not a claim of full AnkiDroid API support.

`native/src/eta.rs` adapts the ETA algorithm from the same AnkiDroid tag, `libanki/src/main/java/com/ichi2/anki/libanki/sched/Scheduler.kt`; its GPL-3.0-or-later SPDX and original copyright notice are preserved. The backend aggregate is fixed and read-only; card scripts cannot supply SQL.
