// ImageDrop — a macOS menu bar image converter.
// Drop any image (PNG, JPEG, WebP, HEIC, TIFF, GIF, BMP, ...) → convert to any other
// format with a compression preset. Output is saved next to the original.
//
// Build with ./build.sh (needs Xcode Command Line Tools). No Xcode project required.

import Cocoa
import ImageIO
import UniformTypeIdentifiers

// MARK: - Output formats

enum OutputFormat: String, CaseIterable {
    case png  = "PNG"
    case jpeg = "JPEG"
    case webp = "WebP"
    case heic = "HEIC"
    case tiff = "TIFF"
    case gif  = "GIF"
    case bmp  = "BMP"

    var uti: String {
        switch self {
        case .png:  return "public.png"
        case .jpeg: return "public.jpeg"
        case .webp: return "org.webmproject.webp"
        case .heic: return "public.heic"
        case .tiff: return "public.tiff"
        case .gif:  return "com.compuserve.gif"
        case .bmp:  return "com.microsoft.bmp"
        }
    }

    var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .jpeg: return "jpg"
        case .webp: return "webp"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .gif:  return "gif"
        case .bmp:  return "bmp"
        }
    }

    /// Extensions that count as "already this format" (used to name the output "-compressed").
    var matchingExtensions: [String] {
        switch self {
        case .jpeg: return ["jpg", "jpeg"]
        case .tiff: return ["tif", "tiff"]
        default:    return [fileExtension]
        }
    }

    var supportsAlpha: Bool { self != .jpeg && self != .bmp }
}

// MARK: - Compression presets

enum Preset: String, CaseIterable {
    case original  = "Original — no resize, max quality"
    case web       = "Web page — balanced (q82, ≤2560px)"
    case social    = "Social media (q78, ≤2048px)"
    case email     = "Email / messaging (q65, ≤1600px)"
    case thumbnail = "Thumbnail (q70, ≤512px)"

    /// 0–1 lossy quality (only affects JPEG / WebP / HEIC).
    var quality: CGFloat {
        switch self {
        case .original:  return 1.0
        case .web:       return 0.82
        case .social:    return 0.78
        case .email:     return 0.65
        case .thumbnail: return 0.70
        }
    }

    /// Longest side is scaled down to this if larger. nil = keep original size.
    var maxPixelSize: Int? {
        switch self {
        case .original:  return nil
        case .web:       return 2560
        case .social:    return 2048
        case .email:     return 1600
        case .thumbnail: return 512
        }
    }
}

struct ConversionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Converter (ImageIO)

enum Converter {

    static func convert(_ source: URL, to format: OutputFormat, preset: Preset) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0 else {
            throw ConversionError(message: "Can't read \(source.lastPathComponent)")
        }

        // Going through the thumbnail API (even with no resize) applies EXIF orientation,
        // so rotated phone photos come out the right way up.
        let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let fullSize = (w > 0 && h > 0) ? max(w, h) : 100_000
        let target = preset.maxPixelSize.map { min($0, fullSize) } ?? fullSize

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbOptions as CFDictionary) else {
            throw ConversionError(message: "Can't decode \(source.lastPathComponent)")
        }

        // JPEG/BMP have no alpha channel — flatten transparency onto white instead of black.
        if !format.supportsAlpha, hasAlpha(image) {
            image = flattenOnWhite(image)
        }

        let output = outputURL(for: source, format: format)
        let destOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: preset.quality
        ]

        if let dest = CGImageDestinationCreateWithURL(output as CFURL, format.uti as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, destOptions as CFDictionary)
            guard CGImageDestinationFinalize(dest) else {
                throw ConversionError(message: "Failed to write \(output.lastPathComponent)")
            }
            return output
        }

        // ImageIO can't create this destination. ImageIO decodes WebP (macOS 11+) but has no
        // WebP *encoder* (still true on macOS 26), so fall back to Homebrew's cwebp if installed.
        if format == .webp {
            try encodeWebPWithCwebp(image, quality: preset.quality, to: output)
            return output
        }
        throw ConversionError(message: "\(format.rawValue) export isn't supported on this macOS version")
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private static func flattenOnWhite(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    private static func outputURL(for source: URL, format: OutputFormat) -> URL {
        let dir = source.deletingLastPathComponent()
        var base = source.deletingPathExtension().lastPathComponent
        if format.matchingExtensions.contains(source.pathExtension.lowercased()) {
            base += "-compressed"
        }
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-\(n)").appendingPathExtension(format.fileExtension)
            n += 1
        }
        return candidate
    }

    private static func encodeWebPWithCwebp(_ image: CGImage, quality: CGFloat, to output: URL) throws {
        let candidates = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"]
        guard let cwebp = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ConversionError(message: "WebP export needs cwebp — run `brew install webp`")
        }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, "public.png" as CFString, 1, nil) else {
            throw ConversionError(message: "Couldn't create temp file")
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: cwebp)
        var args = ["-quiet"]
        if quality >= 0.999 { args.append("-lossless") } else { args += ["-q", String(Int(quality * 100))] }
        args += [tmp.path, "-o", output.path]
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw ConversionError(message: "cwebp failed on \(output.lastPathComponent)")
        }
    }
}

// MARK: - Drop zone view

final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onClick: (() -> Void)?

    private var highlighted = false { didSet { needsDisplay = true } }
    private let label = NSTextField(labelWithString: "Drop images here\nor click to choose files")

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        (highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.10) : NSColor.clear).setFill()
        path.fill()
        (highlighted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
    }

    private func imageURLs(from info: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: NSImage.imageTypes
        ]
        return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = !imageURLs(from: sender).isEmpty
        highlighted = ok
        return ok ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlighted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        let urls = imageURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private let formatPopup = NSPopUpButton()
    private let presetPopup = NSPopUpButton()
    private let dropView = DropView(frame: .zero)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let queue = DispatchQueue(label: "imagedrop.convert", qos: .userInitiated)

    private let panelWidth: CGFloat = 330

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "ImageDrop")
            button.target = self
            button.action = #selector(togglePanel)
        }
        buildPanel()
        // First launch: show the panel so it's obvious the app is running in the menu bar.
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            showPanel()
        }
    }

    // Double-clicking the app in Finder / the Applications folder while it's already
    // running would otherwise do nothing visible — show the panel instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    // Files dropped onto the app icon / "Open With" also convert with the current settings.
    // When the app is *launched* by opening a file, AppKit delivers this before
    // applicationDidFinishLaunching, so make sure the UI (and the popups that hold the
    // saved format/preset) exists first — otherwise the selection falls back to index 0.
    func application(_ application: NSApplication, open urls: [URL]) {
        if panel == nil { buildPanel() }
        convert(urls)
    }

    // MARK: UI

    private func buildPanel() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 10),
                        styleMask: [.titled, .closable, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.title = "ImageDrop"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let defaults = UserDefaults.standard
        formatPopup.addItems(withTitles: OutputFormat.allCases.map(\.rawValue))
        presetPopup.addItems(withTitles: Preset.allCases.map(\.rawValue))
        formatPopup.selectItem(at: OutputFormat.allCases.firstIndex { $0.rawValue == defaults.string(forKey: "format") } ?? 1)
        presetPopup.selectItem(at: Preset.allCases.firstIndex { $0.rawValue == defaults.string(forKey: "preset") } ?? 1)
        formatPopup.target = self; formatPopup.action = #selector(saveSelection)
        presetPopup.target = self; presetPopup.action = #selector(saveSelection)

        dropView.translatesAutoresizingMaskIntoConstraints = false
        dropView.heightAnchor.constraint(equalToConstant: 130).isActive = true
        dropView.onDrop = { [weak self] in self?.convert($0) }
        dropView.onClick = { [weak self] in self?.chooseFiles() }

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 4
        statusLabel.preferredMaxLayoutWidth = panelWidth - 28
        statusLabel.stringValue = "Converted files are saved next to the originals."

        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        quit.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let bottom = NSStackView(views: [statusLabel, quit])
        bottom.orientation = .horizontal
        bottom.alignment = .top
        bottom.spacing = 8
        quit.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [
            labeledRow("Convert to", formatPopup),
            labeledRow("Optimize for", presetPopup),
            dropView,
            bottom
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: panelWidth)
        ])
        panel.contentView = content
        panel.layoutIfNeeded()
        panel.setContentSize(content.fittingSize)
    }

    private func labeledRow(_ title: String, _ popup: NSPopUpButton) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 84).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    @objc private func saveSelection() {
        UserDefaults.standard.set(formatPopup.titleOfSelectedItem, forKey: "format")
        UserDefaults.standard.set(presetPopup.titleOfSelectedItem, forKey: "preset")
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        if panel == nil { buildPanel() }
        positionPanelUnderStatusItem()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func positionPanelUnderStatusItem() {
        guard let button = statusItem.button, let window = button.window else { return }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonRect.midX - panel.frame.width / 2
        let y = buttonRect.minY - panel.frame.height - 6
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func chooseFiles() {
        let open = NSOpenPanel()
        open.allowsMultipleSelection = true
        open.canChooseDirectories = false
        open.allowedContentTypes = [.image]
        open.level = .floating
        if open.runModal() == .OK {
            convert(open.urls)
        }
    }

    // MARK: Conversion

    private func convert(_ urls: [URL]) {
        let format = OutputFormat.allCases[max(formatPopup.indexOfSelectedItem, 0)]
        let preset = Preset.allCases[max(presetPopup.indexOfSelectedItem, 0)]
        statusLabel.stringValue = "Converting \(urls.count) file\(urls.count == 1 ? "" : "s")…"

        queue.async {
            var outputs: [URL] = []
            var errors: [String] = []
            var inBytes = 0, outBytes = 0

            for url in urls {
                do {
                    let out = try Converter.convert(url, to: format, preset: preset)
                    outputs.append(out)
                    inBytes += Self.fileSize(url)
                    outBytes += Self.fileSize(out)
                } catch {
                    errors.append(error.localizedDescription)
                }
            }

            DispatchQueue.main.async {
                var lines: [String] = []
                if !outputs.isEmpty {
                    let n = outputs.count
                    lines.append("Saved \(n) \(format.rawValue) file\(n == 1 ? "" : "s") · \(Self.human(inBytes)) → \(Self.human(outBytes))")
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                }
                lines.append(contentsOf: errors)
                self.statusLabel.stringValue = lines.joined(separator: "\n")
            }
        }
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private static func human(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
