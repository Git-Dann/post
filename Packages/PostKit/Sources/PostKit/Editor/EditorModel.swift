import SwiftUI
import CoreImage
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

    public var selectedTool: EditTool = .brightness
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
        tool.set(newValue, in: &state)
        recompute()
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

    // MARK: Undo / redo

    /// Snapshot before a continuous interaction (a dial drag, a crop session).
    public func beginInteraction() {
        if interactionSnapshot == nil { interactionSnapshot = state }
    }

    /// Commit the interaction; pushes an undo entry only if something actually changed.
    public func endInteraction() {
        defer { interactionSnapshot = nil }
        guard let snap = interactionSnapshot, snap != state else { return }
        undoStack.append(snap)
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
        state.brightness = recipe.brightness * i
        state.contrast = recipe.contrast * i
        state.saturation = recipe.saturation * i
        state.hue = recipe.hue * i
        state.fade = recipe.fade * i
        state.grain = recipe.grain * i
    }

    private func clearToneColorFilm() {
        state.brightness = 0
        state.contrast = 0
        state.saturation = 0
        state.hue = 0
        state.fade = 0
        state.grain = 0
    }

    private func recompute() {
        displayImage = FilterPipeline.makeImage(source: source, state: state, grainScale: grainScale)
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
