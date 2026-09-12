# PhoneRelay — tiny Android relay for PhoneLink

Two activities, one APK, no Gradle.

- **PhoneRelayActivity** — invisible flash-launch activity driven by the
  PhoneLink module over `adb shell am start`:
  - `--es mode write --es text "..."` or `--es mode write --es textfile <path>`:
    sets the phone clipboard from the invisible window, writes
    `files/ack.txt` (`OK`/`EMPTY`).
  - `--es mode read`: after the window settles, reads the clipboard into
    `files/clip.txt`. **Dead on this ROM** (itel A663LC): foreign clips
    always read empty even with READ_CLIPBOARD appop granted.
- **ShareRelayActivity** — ACTION_SEND target (`text/plain` + `*/*`), stores
  shared text/files into `Download/PhoneLinkInbox/` via MediaStore (no
  storage permission needed on API 29+). The PhoneLink pull browser sees
  that folder directly.

## Verified behavior on itel A663LC (Android 13, 2026-09-12)

- Writes SET the clip (clipboard-change observer fires) but this ROM's
  clipboard watcher **reaps relay-set clips within ~seconds when idle** —
  paste immediately, or prefer the share sheet.
- Reads of foreign clips: always empty (AppOps READ_CLIPBOARD + foreground
  flash both tested). Shell-uid clipboard is likewise blocked.
- Share-sheet registration + EXTRA_TEXT delivery: works.

## Build & install

```bash
./build.sh            # javac -> d8 -> aapt2 link -> zipalign -> apksigner
adb install -r out/phonerelay.apk
```

Requires JDK 17 (`mise use -g java@17`) and `~/Android/Sdk` with build-tools
+ platforms/android-34 (see repo memory; build-tools extract directly under
`~/Android/Sdk/build-tools/`). The keystore is a throwaway dev key. Test app
prototype lived at `~/dexlab`.