import AppKit
import Foundation
import Virtualization

/// Captures the live framebuffer of a `VZVirtualMachineView` by rendering its
/// backing CALayer into an offscreen bitmap context.
///
/// Why CALayer.render and not a private VZ framebuffer hook? Apple does not
/// publish a supported framebuffer-read API on `VZVirtualMachineView`. The
/// CALayer.render path is the documented, App-Store-compatible way to grab
/// the on-screen pixels. It captures whatever the user is seeing — including
/// the GPU-rendered guest framebuffer — because by the time we render, the
/// frame has already been promoted onto the host CALayer tree.
///
/// This is a free helper rather than a method on the view representable so it
/// can be invoked from anywhere that holds a reference to the view (e.g. the
/// Sandbox screen for one-shot screenshots, or the future cinematic-tab
/// sampler).
enum SharedCompassVMFramebufferSampler {
    /// Captures the current contents of `view` as an `NSImage`. Returns nil if
    /// the view's layer has zero area or rendering fails.
    ///
    /// Must be called on the main thread.
    @MainActor
    static func captureSnapshot(of view: VZVirtualMachineView) -> NSImage? {
        guard let layer = view.layer else {
            // Force a layer; VZVirtualMachineView is layer-backed normally,
            // but be defensive in case a caller passes a freshly-allocated view.
            view.wantsLayer = true
            return nil
        }
        return renderLayer(layer, fallbackSize: view.bounds.size)
    }

    /// Renders an arbitrary CALayer into an NSImage. Exposed for unit-tests
    /// (Phase 6) so callers can build a deterministic CALayer offscreen and
    /// assert the rendered output has the expected dimensions.
    @MainActor
    static func renderLayer(_ layer: CALayer, fallbackSize: CGSize) -> NSImage? {
        var size = layer.bounds.size
        if size.width <= 0 || size.height <= 0 {
            size = fallbackSize
        }
        if size.width <= 0 || size.height <= 0 {
            return nil
        }

        let scale = layer.contentsScale > 0 ? layer.contentsScale : 1
        let pixelWidth = Int((size.width * scale).rounded(.up))
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }

    /// Encodes the supplied image as PNG. Convenience for callers that
    /// want to persist a snapshot to disk.
    static func encodePNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }
}
