# MenuCompress

A macOS menu bar app for getting an image ready to upload. Drop an image on the menu bar icon, pick a crop, and drag the result into any folder.

- **Crop** to 2:1 (saved as 2048×1024) or 16:9 (1920×1080). The choice is a setting on the start view and is remembered.
- **Compress Without Cropping** keeps the whole image and its shape, shrinking it only as much as it needs to.
- Every result is a JPEG just under 1 MB (1,000,000 bytes), at the best quality that fits.

Images are resized with vImage's Lanczos filter and encoded with [jpegli](https://github.com/google/jpegli), which produces standard JPEGs that open anywhere but look noticeably better than Apple's encoder at the same file size. Color profiles such as Display P3 are kept; other metadata, including location, is stripped.

Requires macOS 14 or later.

## Building

Open `MenuCompress.xcodeproj` in Xcode and run. Sparkle comes in through Swift Package Manager. jpegli is vendored in `Packages/Jpegli` as a prebuilt universal static library, which `Packages/Jpegli/build-jpegli.sh` rebuilds from a pinned commit (needs `cmake` and `ninja`).

## Releasing

Updates ship through [Sparkle](https://sparkle-project.org). The feed is `docs/appcast.xml`, served by GitHub Pages, and each release zip is attached to a GitHub release.

1. Bump the version in Xcode and commit.
2. Run `scripts/release.sh "What changed"`.

The script bumps and commits the build number when it needs to, archives, signs with Developer ID, notarizes, signs the update for Sparkle, asks before publishing, then creates the GitHub release and pushes the updated feed. The one-time setup it needs is at the top of the script.

## License

MIT. Third-party licenses are in `MenuCompress/Acknowledgements.txt`, which also ships inside the app.
