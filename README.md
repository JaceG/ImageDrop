<p align="center">
  <img src="docs/icon.png" width="128" alt="ImageDrop icon">
</p>

# ImageDrop

A tiny macOS menu bar app that converts images. Drop a file on it, pick a format
and a compression preset, and the converted copy is saved next to the original.

**[Download for Mac](https://github.com/JaceG/ImageDrop/releases/latest/download/ImageDrop.zip)** ·
[Website](https://jaceg.github.io/ImageDrop/) · Windows: coming soon

- **Formats:** PNG, JPEG, WebP, HEIC, TIFF, GIF, BMP (in and out)
- **Presets:** Original, Web page, Social media, Email / messaging, Thumbnail
- **Private:** runs entirely on your Mac, nothing is uploaded anywhere
- **Small:** one Swift file, no dependencies, ~200 KB

## Install

1. Download and unzip `ImageDrop.zip`, then drag **ImageDrop** into your Applications folder.
2. Open it. Because the app isn't notarized with Apple, macOS will refuse the first time.
   Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.
   Or from Terminal: `xattr -dr com.apple.quarantine /Applications/ImageDrop.app`
3. Look for the photo icon in your menu bar. Click it to open the drop panel.

WebP export uses Homebrew's `cwebp` (`brew install webp`) because macOS's ImageIO
can decode WebP but not encode it. Everything else is built in.

Requires macOS 12 or later.

## Build from source

No Xcode project, just `swiftc`:

```bash
./build.sh            # builds ImageDrop.app next to the script
./build.sh --install  # also copies it to /Applications and launches it
```

`main.swift` is the whole app. `make-icon.sh` regenerates `AppIcon.icns`, and
`release.sh <version>` zips a build and publishes it as a GitHub Release, which is
what the website's download button points at.

## Support the project

If ImageDrop saves you time, you can leave a tip from the website's **Donate** button.

## License

MIT — see [LICENSE](LICENSE).
