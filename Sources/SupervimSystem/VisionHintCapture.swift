#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision
import SupervimCore

/// On-device text and rectangle recognition for apps whose accessibility tree
/// is empty. The image is not written to disk and is not uploaded.
///
/// Screen Recording is requested only the first time a capture is needed.
/// `SCScreenshotManager` is used on macOS 14 and later. Older systems, and a
/// failed ScreenCaptureKit capture, use `CGWindowListCreateImage`.
public final class SystemVisionHints: VisionHintServing, @unchecked Sendable {
    private let bundles: @Sendable () -> [String]
    private let queue = DispatchQueue(label: "com.lijigang.supervim.vision", qos: .userInitiated)
    private let lock = NSLock()
    private var didRequestAccess = false

    public init(bundles: @escaping @Sendable () -> [String] = { Settings.defaultVisionBundleIdentifiers }) {
        self.bundles = bundles
    }

    public func prepareHints(
        bundleIdentifier: String,
        axHitCount: Int,
        completion: @escaping @Sendable (VisionHintResult) -> Void
    ) {
        let allowed = bundles()
        guard VisionHintPolicy.shouldCapture(
            axHitCount: axHitCount,
            bundleIdentifier: bundleIdentifier,
            visionBundles: allowed
        ) else {
            completion(.skipped)
            return
        }
        queue.async { [weak self] in
            guard let self else {
                completion(.empty)
                return
            }
            completion(self.capture(bundleIdentifier: bundleIdentifier))
        }
    }

    private func capture(bundleIdentifier: String) -> VisionHintResult {
        guard let window = CGFrontWindowList.frontmost() else {
            ModeTrace.noteLine(VisionHintGeometry.logLine(
                permission: "no-window",
                pixelWidth: 0,
                pixelHeight: 0,
                boxes: 0,
                hits: 0
            ))
            return .empty
        }
        guard accessGranted() else {
            ModeTrace.noteLine(VisionHintGeometry.logLine(
                permission: "denied",
                pixelWidth: 0,
                pixelHeight: 0,
                boxes: 0,
                hits: 0
            ))
            _ = bundleIdentifier
            return .needsScreenRecording
        }
        let scale = backingScale(for: window.frame)
        guard let image = captureImage(window: window, scale: scale) else {
            ModeTrace.noteLine(VisionHintGeometry.logLine(
                permission: "granted",
                pixelWidth: 0,
                pixelHeight: 0,
                boxes: 0,
                hits: 0
            ))
            return .empty
        }
        let boxes = recognize(image)
        let captured = CapturedWindow(
            pixelWidth: image.width,
            pixelHeight: image.height,
            frame: HintRect(
                x: window.frame.x,
                y: window.frame.y,
                width: window.frame.width,
                height: window.frame.height
            ),
            backingScale: Double(image.width) / window.frame.width
        )
        let targets = VisionHintGeometry.targets(boxes: boxes, image: captured)
        ModeTrace.noteLine(VisionHintGeometry.logLine(
            permission: "granted",
            pixelWidth: image.width,
            pixelHeight: image.height,
            boxes: boxes.count,
            hits: targets.count
        ))
        return targets.isEmpty ? .empty : .targets(targets)
    }

    /// Prompts at most once per process. Later misses only report the denial.
    private func accessGranted() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        lock.lock()
        let shouldAsk = !didRequestAccess
        didRequestAccess = true
        lock.unlock()
        guard shouldAsk else {
            return false
        }
        let ask = { CGRequestScreenCaptureAccess() }
        let granted: Bool
        if Thread.isMainThread {
            granted = ask()
        } else {
            granted = DispatchQueue.main.sync(execute: ask)
        }
        return granted || CGPreflightScreenCaptureAccess()
    }

    private func captureImage(window: CGFrontWindowList.Window, scale: Double) -> CGImage? {
        if #available(macOS 14.0, *) {
            if let image = screenshot(windowID: window.id, frame: window.frame, scale: scale) {
                return image
            }
        }
        return legacyImage(window: window)
    }

    @available(macOS 14.0, *)
    private func screenshot(windowID: CGWindowID, frame: ActuatorRect, scale: Double) -> CGImage? {
        let slot = CapturedImageSlot()
        let pixelWidth = max(1, Int((frame.width * scale).rounded()))
        let pixelHeight = max(1, Int((frame.height * scale).rounded()))
        let work: @Sendable () async -> Void = {
            await Self.captureWindow(
                windowID: windowID,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                into: slot
            )
            slot.finish()
        }
        Task(operation: work)
        return slot.wait()
    }

    @available(macOS 14.0, *)
    private static func captureWindow(
        windowID: CGWindowID,
        pixelWidth: Int,
        pixelHeight: Int,
        into slot: CapturedImageSlot
    ) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let match = content.windows.first(where: { $0.windowID == windowID }) else {
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: match)
            let configuration = SCStreamConfiguration()
            configuration.width = pixelWidth
            configuration.height = pixelHeight
            configuration.showsCursor = false
            configuration.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            slot.store(image)
        } catch {
            return
        }
    }

    private func legacyImage(window: CGFrontWindowList.Window) -> CGImage? {
        let bounds = CGRect(
            x: window.frame.x,
            y: window.frame.y,
            width: window.frame.width,
            height: window.frame.height
        )
        return CGWindowListCreateImage(
            bounds,
            .optionIncludingWindow,
            window.id,
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    private func recognize(_ image: CGImage) -> [VisionBox] {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.recognitionLanguages = ["zh-Hans", "en-US"]
        text.usesLanguageCorrection = false
        let rectangles = VNDetectRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([text, rectangles])
        } catch {
            return []
        }
        var boxes: [VisionBox] = []
        for observation in text.results ?? [] {
            let value = observation.topCandidates(1).first?.string ?? ""
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            boxes.append(VisionBox(
                text: trimmed,
                normalized: normalized(observation.boundingBox),
                kind: .text
            ))
        }
        for observation in rectangles.results ?? [] {
            boxes.append(VisionBox(
                text: "",
                normalized: normalized(observation.boundingBox),
                kind: .rectangle
            ))
        }
        return boxes
    }

    private func normalized(_ box: CGRect) -> HintRect {
        HintRect(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height)
    }

    private func backingScale(for frame: ActuatorRect) -> Double {
        let screens = NSScreen.screens
        guard let primary = screens.first else {
            return 2
        }
        let centerY = frame.y + frame.height / 2
        let point = CGPoint(x: frame.x + frame.width / 2, y: primary.frame.height - centerY)
        for screen in screens where screen.frame.contains(point) {
            return Double(screen.backingScaleFactor)
        }
        return Double(primary.backingScaleFactor)
    }
}

/// Holds one screenshot across the capture task. The image is not sent anywhere.
private final class CapturedImageSlot: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var image: CGImage?

    func store(_ image: CGImage?) {
        lock.lock()
        self.image = image
        lock.unlock()
    }

    func finish() {
        semaphore.signal()
    }

    func wait() -> CGImage? {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return image
    }
}
#endif
