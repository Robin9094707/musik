# Simplex Music Player

A fully local iPhone/iPad music player in German and English, built with SwiftUI and iOS 26 Liquid Glass. No account, backend, Deezer catalogue or online search is used.

## Features

- Native document picker with broad provider-compatible selection, multiple files, copied imports, coordinated cloud access, progress, SHA-256 duplicate detection and per-file error reporting. Select a same-name LRC/TXT alongside audio to attach lyrics.
- Local search, sort, albums, artists, favorites, editable/reorderable playlists and import history.
- Full-screen player, seek, shuffle, repeat, editable upcoming queue, sleep timer, background audio, headphone controls, lock screen metadata, system volume and AirPlay.
- Plain lyrics and LRC timestamps with offsets, repeated timestamps, automatic scrolling and tap-to-seek. Lyrics are supplied locally, not fetched from a service.
- Embedded covers and a tag editor for title, artist, album, album artist, composer, genre, date, track/disc numbers and totals, BPM, comments, grouping, ISRC and lyrics. Add covers from Photos or Files. TagLib writes to a temporary copy before replacement; original source files remain unchanged. Export the edited audio through the share sheet. Library-only editing is available for formats with limited tag writing.
- Four generated, selectable Home Screen icons: Aurora, Ember, Glacier and Obsidian. Light, dark or system theme; automatic or explicit DE/EN language; four-page onboarding.
- Migration from the old three-field JSON library, with a backup before migration. The bundle ID stays `de.robin.nexusmusic` so existing data can survive an update signed with the same application identity. Corrupt indexes are preserved and never silently replaced.

## Audio support

SFBAudioEngine 0.14.0 and its codec dependencies cover MP3, AAC/M4A/ALAC, FLAC, WAV, AIFF, Ogg Vorbis, Opus, APE, WavPack, Musepack, Speex, TTA and additional formats. Actual support depends on codec/container; DRM-protected and unsupported files produce an import error. This is not a claim to play every audio format ever created. Tag capabilities depend on the format; arbitrary binary ID3 frames are not exposed in the editor.

## Build and validation

Install Xcode 26+ and XcodeGen, then run:

```sh
python3 scripts/prepare_assets.py
xcodegen generate
xcodebuild -resolvePackageDependencies -project SimplexMusic.xcodeproj -scheme SimplexMusic -clonedSourcePackagesDirPath build/SourcePackages
python3 scripts/licenses.py
xcodegen generate
xcodebuild -project SimplexMusic.xcodeproj -scheme SimplexMusic -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions builds an **unsigned** device IPA, runs simulator unit and UI tests and verifies alternate icon configuration before uploading the IPA. Tests cover real MP3/M4A/FLAC/Vorbis/Opus decoding, imported metadata, tag/artwork round trips, duplicate detection, migration, corrupt-index preservation, failed-write integrity, LRC sidecars, timestamp parsing and language parity. UI tests cover the library, document picker, player, lyrics, editor and German settings.

Use a valid signing certificate and provisioning profile to install the IPA. Third-party cloud provider behavior and real-device background playback still need device testing. Audio and playlists are local; back up important files separately.

## Open source

SFBAudioEngine: https://github.com/sbooth/SFBAudioEngine (MIT), with TagLib and codec dependencies under their respective licenses. The build collects resolved dependency license notices into the app's acknowledgements screen. Original generated icon artworks are in `IconSources/`.
