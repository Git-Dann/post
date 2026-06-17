import SwiftUI
import CoreImage
import Metal
import Observation

/// The editor's single source of truth. Owns the live `EditState`, recomputes the displayed
/// `CIImage` through the shared `FilterPipeline`, and manages undo/redo. The view stays dumb.
///
/// `@MainActor` (the module default) — it drives the UI and the Metal preview, both on main.
@Observable
public final class EditorModel: Identifiable {

    public let id = UUID()

    /// Downscaled preview source the editor scrubs against.
    public let source: CIImage
    /// Original encoded data, kept for full-resolution export (nil for synthetic/dev sources).
    public let originalData: Data?
    /// Preview edge ÷ full edge, used to match grain density between preview and export.
    public let previewScale: CGFloat

    public private(set) var state = EditState()
    public private(set) var displayImage: CIImage

    /// Currently selected adjustment tool, or nil for a neutral state (no dial shown).
    public var selectedTool: EditTool? = .exposure
    /// Whether the crop geometry overlay is presented.
    public var isCropping = false

    /// The currently applied style (if any). When set, the dial controls its intensity rather than
    /// individual tools; editing a tool "bakes" the style and clears this.
    public private(set) var activeStyle: Style?
    /// 0...1 strength of the active style (full at 1).
    public private(set) var styleIntensity: Double = 1
    public var hasActiveStyle: Bool { activeStyle != nil }

    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    private var interactionSnapshot: EditState?

    public init(source: CIImage, originalData: Data? = nil, previewScale: CGFloat = 1) {
        self.source = source
        self.originalData = originalData
        self.previewScale = previewScale
        self.displayImage = FilterPipeline.makeImage(
            source: source,
            state: EditState(),
            grainScale: max(1, 1 / previewScale)
        )
    }

    public var grainScale: CGFloat { max(1, 1 / previewScale) }

    /// Aspect ratio (w/h) of the currently displayed image, so the editor can size the framed
    /// card to the image and fill it with no letterbox. Reflects crop/rotation.
    public var aspect: CGFloat {
        let e = displayImage.extent
        guard e.height > 0, !e.isInfinite, !e.isNull else { return 1 }
        return e.width / e.height
    }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var hasEdits: Bool { !state.isIdentity }

    // MARK: Dial binding

    /// Current value of a tool.
    public func value(of tool: EditTool) -> Double { tool.value(in: state) }

    /// Live update from the dial (no undo snapshot — that happens at gesture boundaries).
    public func update(_ tool: EditTool, to newValue: Double) {
        if tool == .auto { setAutoStrength(newValue); return }
        tool.set(newValue, in: &state)
        recompute()
    }

    // MARK: Auto enhance

    /// Analyzed enhancement target for this image, computed once and cached.
    private var autoTarget: EditState?
    private static let analysisContext = CIContext(options: [.cacheIntermediates: false])

    /// Blend the auto target into the real fields by `strength` (0…1). The result is ordinary
    /// EditState values the other dials can then refine.
    public func setAutoStrength(_ strength: Double) {
        let target = autoTarget ?? {
            let t = AutoEnhance.target(for: source, context: Self.analysisContext)
            autoTarget = t
            return t
        }()
        state.autoStrength = min(max(strength, 0), 1)
        AutoEnhance.apply(target, strength: state.autoStrength, to: &state)
        recompute()
    }

    // MARK: Selective scope

    /// CIImage isn't `Sendable`; it's immutable here, so box it to cross to the detached
    /// segmentation task (and back) without tripping strict concurrency.
    private struct ImageBox: @unchecked Sendable { let image: CIImage }

    /// Cached subject mask for the preview source (white = subject), computed off-main on first use.
    private var subjectMask: CIImage?
    private var maskRequested = false
    /// True while the subject mask is being computed (the chip shows a brief progress state).
    public private(set) var isPreparingMask = false
    /// True once segmentation finished and found no subject — lets the UI explain the no-op.
    public private(set) var maskUnavailable = false

    /// The current selective scope (mirrors `state.scope` for the view).
    public var scope: SelectiveScope { state.scope }

    /// Change the selective scope. The first time a region is chosen this kicks off on-device
    /// subject segmentation; the preview re-renders (masked) as soon as the mask is ready.
    public func setScope(_ newScope: SelectiveScope) {
        guard state.scope != newScope else { return }
        beginInteraction()
        state.scope = newScope
        endInteraction()
        if newScope.isRegional { ensureSubjectMask() }
        recompute()
    }

    private func ensureSubjectMask() {
        guard subjectMask == nil, !maskRequested else { return }
        maskRequested = true
        isPreparingMask = true
        maskUnavailable = false
        let box = ImageBox(image: source)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ImageBox? in
                SubjectMask.foregroundMask(for: box.image).map(ImageBox.init)
            }.value
            self.subjectMask = result?.image
            self.maskUnavailable = (result == nil)
            self.isPreparingMask = false
            self.recompute()
        }
    }

    // MARK: Geometry

    public func apply(crop: CropRect, straighten: Double, quarterTurns: Int,
                      flipH: Bool, flipV: Bool) {
        beginInteraction()
        state.crop = crop
        state.straightenAngle = straighten
        state.rotationQuarterTurns = quarterTurns
        state.flippedHorizontally = flipH
        state.flippedVertically = flipV
        recompute()
        endInteraction()
    }

    // MARK: In-place crop (working state while `isCropping`, committed on Done)

    /// The crop rectangle being edited — normalized, top-left origin (UI space).
    public var cropWorkingRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    public private(set) var cropStraighten: Double = 0
    public private(set) var cropQuarterTurns: Int = 0
    public private(set) var cropFlipH = false
    public private(set) var cropFlipV = false
    /// Locked crop aspect (final width÷height in pixels); nil = Free (handles resize freely).
    public private(set) var cropAspectRatio: Double?
    /// Cached uncropped preview the crop canvas shows (recomputed only when geometry changes).
    public private(set) var cropDisplayImage: CIImage = CIImage.empty()

    /// Aspect (w/h) of the crop preview, so the editor card fits the full image while cropping.
    public var cropPreviewAspect: CGFloat {
        let e = cropDisplayImage.extent
        guard e.height > 0, !e.isInfinite, !e.isNull, !e.isEmpty else { return aspect }
        return e.width / e.height
    }

    /// Enter crop: seed the working state from the current recipe.
    public func beginCrop() {
        let c = state.crop
        cropWorkingRect = CGRect(x: c.x, y: 1 - c.y - c.height, width: c.width, height: c.height)
        cropStraighten = state.straightenAngle
        cropQuarterTurns = state.rotationQuarterTurns
        cropFlipH = state.flippedHorizontally
        cropFlipV = state.flippedVertically
        cropAspectRatio = nil
        recomputeCropDisplay()
        isCropping = true
    }

    public func setCropStraighten(_ value: Double) { cropStraighten = value; recomputeCropDisplay() }
    public func rotateQuarter(_ delta: Int) { cropQuarterTurns = (cropQuarterTurns + delta + 4) % 4; recomputeCropDisplay() }
    public func toggleFlipH() { cropFlipH.toggle(); recomputeCropDisplay() }
    public func toggleFlipV() { cropFlipV.toggle(); recomputeCropDisplay() }

    private func recomputeCropDisplay() {
        cropDisplayImage = croplessImage(
            straighten: cropStraighten, quarterTurns: cropQuarterTurns, flipH: cropFlipH, flipV: cropFlipV
        )
    }

    /// Commit the crop into the recipe.
    public func commitCrop() {
        let r = cropWorkingRect
        let imageCrop = CropRect(x: r.minX, y: 1 - r.minY - r.height, width: r.width, height: r.height)
        apply(crop: imageCrop, straighten: cropStraighten,
              quarterTurns: cropQuarterTurns, flipH: cropFlipH, flipV: cropFlipV)
        isCropping = false
        selectedTool = nil   // finishing a crop shouldn't leave an adjustment tool active
    }

    public func cancelCrop() { isCropping = false }

    /// Set the crop to a centered rectangle of the given width-over-height ratio (nil = Free/full).
    /// The ratio is remembered so the handles stay locked to it while resizing.
    public func setCropAspect(_ ratio: Double?) {
        cropAspectRatio = ratio
        guard let ratio else {
            cropWorkingRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        let e = cropDisplayImage.extent
        let imageAspect = e.height > 0 ? e.width / e.height : 1
        var w = 1.0, h = 1.0
        if ratio > imageAspect { h = imageAspect / ratio } else { w = ratio / imageAspect }
        cropWorkingRect = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    // MARK: Undo / redo

    /// Snapshot before a continuous interaction (a dial drag, a crop session).
    public func beginInteraction() {
        if interactionSnapshot == nil { interactionSnapshot = state }
    }

    private static let undoLimit = 50

    /// Commit the interaction; pushes an undo entry only if something actually changed.
    public func endInteraction() {
        defer { interactionSnapshot = nil }
        guard let snap = interactionSnapshot, snap != state else { return }
        undoStack.append(snap)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
        activeStyle = nil
        recompute()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
        activeStyle = nil
        recompute()
    }

    /// Restore a persisted recipe when reopening a project. Resets undo history.
    public func load(recipe: EditState) {
        state = recipe
        activeStyle = nil
        undoStack.removeAll()
        redoStack.removeAll()
        if state.scope.isRegional { ensureSubjectMask() }
        recompute()
    }

    public func reset() {
        guard !state.isIdentity else { return }
        undoStack.append(state)
        redoStack.removeAll()
        state = EditState()
        activeStyle = nil
        recompute()
    }

    // MARK: Styles

    /// Apply a style as the active look at full intensity (a jumping-off point). Geometry kept.
    public func applyStyle(_ style: Style) {
        beginInteraction()
        activeStyle = style
        styleIntensity = 1
        applyActiveStyleToState()
        recompute()
        endInteraction()
    }

    /// Live intensity change from the style dial (snapshots happen at gesture boundaries).
    public func setStyleIntensity(_ value: Double) {
        guard activeStyle != nil else { return }
        styleIntensity = min(max(value, 0), 1)
        applyActiveStyleToState()
        recompute()
    }

    /// Remove the active style entirely, returning to a clean image (geometry kept).
    public func dismissStyle() {
        guard activeStyle != nil else { return }
        beginInteraction()
        activeStyle = nil
        clearToneColorFilm()
        recompute()
        endInteraction()
    }

    /// Revert the look to the original image — clears tone/colour/film and any active style (geometry
    /// kept), without entering the intensity flow. Used by the "OG" baseline card (a clean revert).
    public func revertToOriginal() {
        beginInteraction()
        activeStyle = nil
        clearToneColorFilm()
        recompute()
        endInteraction()
    }

    /// The user reached for a tool — keep the current (scaled) look as the new manual base and stop
    /// treating it as a live style.
    public func bakeStyle() {
        activeStyle = nil
    }

    /// Write the active style's recipe (scaled by intensity) into the tone/color/film fields,
    /// leaving geometry untouched.
    private func applyActiveStyleToState() {
        guard let recipe = activeStyle?.recipe else { return }
        let i = styleIntensity
        state.exposure = recipe.exposure * i
        state.brightness = recipe.brightness * i
        state.contrast = recipe.contrast * i
        state.highlights = recipe.highlights * i
        state.shadows = recipe.shadows * i
        state.saturation = recipe.saturation * i
        state.vibrance = recipe.vibrance * i
        state.warmth = recipe.warmth * i
        state.tint = recipe.tint * i
        state.hue = recipe.hue * i
        state.sharpness = recipe.sharpness * i
        state.vignette = recipe.vignette * i
        state.fade = recipe.fade * i
        state.grain = recipe.grain * i
    }

    private func clearToneColorFilm() {
        // Reset everything except geometry, so it tracks EditState's tone/colour/film fields.
        let geometry = (state.crop, state.straightenAngle, state.rotationQuarterTurns,
                        state.flippedHorizontally, state.flippedVertically)
        state = EditState()
        (state.crop, state.straightenAngle, state.rotationQuarterTurns,
         state.flippedHorizontally, state.flippedVertically) = geometry
    }

    private func recompute() {
        let mask = state.scope.isRegional ? subjectMask : nil
        displayImage = FilterPipeline.makeImage(source: source, state: state,
                                                grainScale: grainScale, mask: mask)
    }

    private static let thumbnailContext = CIContext(options: [.cacheIntermediates: false])

    /// A small JPEG of the current edited image for the gallery grid.
    public func thumbnailData(maxEdge: CGFloat = 400) -> Data? {
        let extent = displayImage.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty else { return nil }
        let scale = min(1, maxEdge / max(extent.width, extent.height))
        let small = displayImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return Self.thumbnailContext.jpegRepresentation(
            of: small,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [:]
        )
    }

    // MARK: Pinch-to-inspect (full-resolution tile)

    private var fullSourceCache: CIImage?
    /// GPU-backed so a full-res region renders fast (a software context would stutter on big photos).
    private static let inspectContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()
    private static let inspectColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    /// Full-resolution source, decoded once and cached. Falls back to the preview source for
    /// synthetic/dev images that have no original data (still works, just not truly full-res).
    private func fullSource() -> CIImage {
        if let fullSourceCache { return fullSourceCache }
        if let data = originalData, let img = ImageLoader.fullImage(from: data) {
            fullSourceCache = img
            return img
        }
        return source
    }

    /// Render a crisp tile of the visible region at full source resolution — true pixel-peeping for
    /// the pinch-to-inspect zoom. `unitRect` is the visible region in normalized, top-left-origin
    /// coordinates (0…1); `pixelWidth` is the desired output width in device pixels. Core Image only
    /// processes the requested region (plus filter support), so this stays cheap even for huge photos.
    public func inspectTile(unitRect: CGRect, pixelWidth: CGFloat) -> CGImage? {
        let edited = FilterPipeline.makeImage(source: fullSource(), state: state, grainScale: 1)
        let e = edited.extent
        guard !e.isInfinite, !e.isNull, !e.isEmpty, pixelWidth > 0 else { return nil }
        // Map the top-left-origin unit rect onto Core Image's bottom-left extent.
        let region = CGRect(
            x: e.minX + unitRect.minX * e.width,
            y: e.maxY - unitRect.maxY * e.height,
            width: unitRect.width * e.width,
            height: unitRect.height * e.height
        ).intersection(e)
        guard !region.isNull, region.width > 1, region.height > 1 else { return nil }
        let f = max(0.01, pixelWidth / region.width)   // scale the region to the on-screen pixel size
        let scaled = edited.transformed(by: CGAffineTransform(scaleX: f, y: f))
        let outRect = region.applying(CGAffineTransform(scaleX: f, y: f))
        return Self.inspectContext.createCGImage(
            scaled, from: outRect, format: .RGBA8, colorSpace: Self.inspectColorSpace
        )
    }

    /// The image as it looks with the given geometry but *no crop* — what the crop overlay shows
    /// so the user can re-frame freely. Tone/film adjustments are included for a true preview.
    public func croplessImage(straighten: Double, quarterTurns: Int,
                              flipH: Bool, flipV: Bool) -> CIImage {
        var s = state
        s.crop = .full
        s.straightenAngle = straighten
        s.rotationQuarterTurns = quarterTurns
        s.flippedHorizontally = flipH
        s.flippedVertically = flipV
        return FilterPipeline.makeImage(source: source, state: s, grainScale: grainScale)
    }
}
