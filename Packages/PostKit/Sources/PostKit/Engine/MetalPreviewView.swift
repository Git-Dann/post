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
    /// Pulled every frame by the free-running draw loop, so the preview always reflects the latest
    /// edit live — independent of SwiftUI re-render timing. (Autoclosure keeps call sites unchanged.)
    private let provider: @MainActor () -> CIImage?

    public init(image: @autoclosure @escaping @MainActor () -> CIImage?) {
        self.provider = image
    }

    public func makeCoordinator() -> Renderer { Renderer() }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.delegate = context.coordinator
        view.framebufferOnly = false                 // CIContext must WRITE the drawable texture
        view.colorPixelFormat = .rgba16Float          // wide-gamut, no banding on fades/grain
        // We drive drawing ourselves with a CADisplayLink in `.common` run-loop modes (see the
        // coordinator) so the preview keeps rendering DURING a dial drag — MTKView's own display
        // link doesn't fire while UIKit is in gesture-tracking mode, which froze live updates.
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        view.backgroundColor = .clear
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        }
        context.coordinator.provider = provider
        context.coordinator.startRendering(into: view)
        return view
    }

    public func updateUIView(_ view: MTKView, context: Context) {
        // Just refresh the source; the CADisplayLink draws once per frame. (Don't draw() here too —
        // a second draw in the same frame can't get a drawable and the render fails.)
        context.coordinator.provider = provider
    }

    public static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        coordinator.stopRendering()
    }

    /// MTKView delegate + Core Image renderer. Plain (non-isolated) class; all delegate calls
    /// arrive on the main thread, and `CIContext` is itself thread-safe.
    public final class Renderer: NSObject, MTKViewDelegate {
        let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private let ciContext: CIContext
        private let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

        /// Set on the main thread from `updateUIView`; invoked each frame on the main thread in `draw`.
        var provider: (@MainActor () -> CIImage?)?

        private weak var view: MTKView?
        private var displayLink: CADisplayLink?

        /// Drive `draw()` every frame via a CADisplayLink in `.common` modes — crucially, `.common`
        /// includes `UITrackingRunLoopMode`, so frames keep coming while a dial is being dragged.
        func startRendering(into view: MTKView) {
            self.view = view
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopRendering() {
            displayLink?.invalidate()
            displayLink = nil
            view = nil
        }

        @objc private func step() {
            // The link is added to the main run loop, so we're on the main thread here.
            MainActor.assumeIsolated { view?.draw() }
        }

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

        #if DEBUG
        /// Counts every draw() invocation — used by the `--tracking-test` hook to prove the preview
        /// keeps rendering while the run loop is in gesture-tracking mode.
        public static var debugDrawCount = 0
        #endif

        public func draw(in view: MTKView) {
            #if DEBUG
            Self.debugDrawCount += 1
            #endif
            // MTKView always calls draw on the main thread, so the main-actor provider is safe here.
            let displayImage = MainActor.assumeIsolated { provider?() }
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
