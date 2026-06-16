import SwiftUI
import MetalKit
import CoreImage

/// A Metal-backed view that renders a `CIImage` directly into the drawable texture — no
/// per-frame CPU bitmap copy — so the live editor scrubs at 60–120fps. The image is aspect-fit
/// and centered on a black canvas (the image is always the hero).
///
/// It is deliberately "dumb": hand it the already-filtered `CIImage` and it draws it. The
/// editor owns the `FilterPipeline`.
public struct MetalImageView: UIViewRepresentable {
    private let image: CIImage?

    public init(image: CIImage?) {
        self.image = image
    }

    public func makeCoordinator() -> Renderer { Renderer() }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.delegate = context.coordinator
        view.framebufferOnly = false                 // CIContext must WRITE the drawable texture
        view.colorPixelFormat = .rgba16Float          // wide-gamut, no banding on fades/grain
        // Free-running so the preview reflects every edit instantly during a drag (the draw loop
        // pulls the latest image each frame) rather than only updating when the gesture ends.
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        view.backgroundColor = .clear
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        }
        context.coordinator.displayImage = image
        return view
    }

    public func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.displayImage = image
        view.setNeedsDisplay()
    }

    /// MTKView delegate + Core Image renderer. Plain (non-isolated) class; all delegate calls
    /// arrive on the main thread, and `CIContext` is itself thread-safe.
    public final class Renderer: NSObject, MTKViewDelegate {
        let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private let ciContext: CIContext
        private let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

        /// Set on the main thread from `updateUIView`; read on the main thread in `draw`.
        var displayImage: CIImage?

        override init() {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue() else {
                fatalError("Metal is required for the editor preview.")
            }
            self.device = device
            self.commandQueue = queue
            self.ciContext = CIContext(mtlCommandQueue: queue, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
                .outputColorSpace: outputColorSpace,
                .cacheIntermediates: false,
                .name: "PostPreview"
            ])
            super.init()
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let displayImage,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            let size = view.drawableSize
            guard size.width > 0, size.height > 0 else { return }

            // Aspect-fit the image into the drawable, centered.
            let extent = displayImage.extent
            guard !extent.isInfinite, !extent.isNull, !extent.isEmpty else { return }
            let scale = min(size.width / extent.width, size.height / extent.height)
            let scaled = displayImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let tx = (size.width - scaled.extent.width) / 2 - scaled.extent.origin.x
            let ty = (size.height - scaled.extent.height) / 2 - scaled.extent.origin.y
            let positioned = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))

            // Composite over the canvas color so the letterbox is filled (clears the texture).
            let bounds = CGRect(origin: .zero, size: size)
            let canvas = CIImage(color: CIColor(red: 0.05, green: 0.05, blue: 0.06)).cropped(to: bounds)
            let frame = positioned.composited(over: canvas)

            ciContext.render(
                frame,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: bounds,
                colorSpace: outputColorSpace
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
