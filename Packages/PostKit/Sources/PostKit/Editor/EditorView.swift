import SwiftUI

/// The hero editing screen. A large, framed image sits on the black canvas with the value readout
/// + haptic dial (or the styles strip) floating *inside* the image, the (i) info inside the image's
/// top-left, the tool strip *underneath* the image, and Done at the bottom. Shared by the app and
/// both extensions.
public struct EditorView: View {
    private let model: EditorModel
    private let onDone: (EditState) -> Void
    private let onCancel: () -> Void
    private let exporter: ((EditState) async -> URL?)?
    private let showsChrome: Bool

    @State private var styleProvider: StyleProvider
    @State private var showStyles = false
    /// Browsing the styles list while a look is still applied (so the list shows instead of the
    /// intensity dial, and reopening the list lands on the active look rather than the front).
    @State private var browsingStyles = false
    /// One-time entrance: the dial slot slides up from the image on first appear.
    @State private var revealControls = false
    @State private var shareItem: ShareItem?
    @State private var isExporting = false
    @State private var isComparing = false
    // Pinch-to-inspect: zoom into the preview to check detail/grain. View-only — never touches the recipe.
    @State private var zoomScale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var fitSize: CGSize = .zero
    @State private var zoomGestureActive = false
    @State private var inspectTile: CGImage?     // crisp full-res tile shown when settled & zoomed
    @State private var tileTask: Task<Void, Never>?
    @State private var showInfo = false
    @State private var celebrate = false
    @State private var donePressed = false
    @State private var isCommitting = false
    @State private var exportFailed = false
    @Namespace private var infoGlass
    @AppStorage("soundEffectsEnabled") private var soundEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.verticalSizeClass) private var vSize

    /// Side-rail layout when the viewport is short & wide (iPhone landscape). iPad and portrait stay
    /// on the stacked layout (.regular height); extensions (no chrome) stay stacked too.
    private var isLandscape: Bool { showsChrome && vSize == .compact }

    /// - Parameters:
    ///   - exporter: produces a shareable file URL for the given recipe (full-res export),
    ///     provided by the host so the engine stays UI-agnostic. Returns nil on failure.
    ///   - showsChrome: when false, the top bar, tool strip and Done are hidden — used by the Photos
    ///     editing extension, where the host (Photos) provides its own Done/Cancel chrome.
    public init(
        model: EditorModel,
        styleSource: StyleSource = BundledStyleSource(),
        showsChrome: Bool = true,
        exporter: ((EditState) async -> URL?)? = nil,
        onDone: @escaping (EditState) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.model = model
        self.showsChrome = showsChrome
        self.exporter = exporter
        self.onDone = onDone
        self.onCancel = onCancel
        _styleProvider = State(initialValue: StyleProvider(source: styleSource))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // One control set, two arrangements. Only the black canvas bleeds under the safe area;
            // the content respects insets so the rails clear the landscape notch / home indicator.
            Group {
                if isLandscape { landscapeLayout } else { portraitLayout }
            }
        }
        .statusBarHidden()
        // NB: deliberately no `.animation(value: isLandscape)` here. Animating the portrait⇄landscape
        // swap cross-fades BOTH layout trees at once, and each carries its own dial/image — which
        // showed as a brief "double". The system's own rotation animation already provides a clean
        // transition with only one tree live, so we let it own the motion.
        // The editor dismisses only via its Done/Gallery buttons. Disabling interactive dismissal
        // stops the zoom-transition's pull/pinch-to-dismiss from hijacking the pinch-to-inspect
        // gesture (which was skewing the whole presentation away).
        .interactiveDismissDisabled()
        .sheet(item: $shareItem) { item in ActivityView(items: [item.url]) }
        .alert("Couldn't export this photo", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Something went wrong rendering the image. Please try again.")
        }
        .task {
            // Slide the dial up from the image into place on first load.
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { revealControls = true }
            await styleProvider.loadIfNeeded()
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--show-styles") { showStyles = true }
            if args.contains("--demo-edit") {
                model.selectedTool = .contrast
                model.update(.contrast, to: 0.5)
                model.update(.saturation, to: -0.4)
            }
            if args.contains("--show-info") { showInfo = true }
            if args.contains("--demo-grain") {
                model.selectedTool = .grain
                model.update(.grain, to: 0.9)
            }
            if args.contains("--demo-straighten") {
                model.apply(crop: model.state.crop, straighten: 0.2,
                            quarterTurns: 0, flipH: false, flipV: false)
            }
            if args.contains("--open-crop") { model.beginCrop() }
            if args.contains("--live-test") {
                Task {
                    for i in 0..<80 {
                        model.update(.brightness, to: (Double(i % 16) / 16.0 - 0.5))
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                }
            }
            if args.contains("--demo-style") {
                showStyles = true
                if let style = styleProvider.styles.first(where: { $0.id == "film" }) {
                    model.applyStyle(style)
                    model.setStyleIntensity(0.75)
                }
            }
            #endif
        }
    }

    // MARK: Layouts (portrait stacked / landscape side-rail)

    /// Today's portrait layout: actions on top, image, tools + Done below; the dial overlays the
    /// image bottom (see `framedImage`).
    private var portraitLayout: some View {
        VStack(spacing: Theme.Space.s) {
            if showsChrome { topBar }

            framedImage
                .aspectRatio(model.isCropping ? model.cropPreviewAspect : model.aspect,
                             contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.Space.s)

            if showsChrome {
                if model.isCropping {
                    cropToolStrip
                    cropActionBar
                        .padding(.bottom, Theme.Space.s)
                } else {
                    toolStrip(axis: .horizontal)
                    actionBar
                        .padding(.bottom, Theme.Space.s)
                }
            }
        }
    }

    /// Landscape: actions rail (left) | image | dial + Done in the centre gap | tools rail (right).
    private var landscapeLayout: some View {
        HStack(spacing: Theme.Space.m) {
            actionRail
                .frame(width: 56)

            framedImage
                .aspectRatio(model.isCropping ? model.cropPreviewAspect : model.aspect,
                             contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The "blank space" centre column — reserved a usable min width so a wide photo can't
            // squeeze the dial; a tall photo just leaves a wider gap (column grows toward maxWidth).
            VStack(spacing: Theme.Space.s) {
                Spacer(minLength: 0)
                dialSlot(scrim: false)
                if model.isCropping { cropActionBar } else { actionBar }
                Spacer(minLength: 0)
            }
            .frame(minWidth: 240, maxWidth: 320)

            // Tool rail (or the rotate/flip rail while cropping).
            Group {
                if model.isCropping {
                    VStack(spacing: Theme.Space.l) { cropButtons }
                } else {
                    toolStrip(axis: .vertical)
                }
            }
            .frame(width: 84)
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.s)
    }

    // MARK: Framed image (with the controls living inside it)

    /// The image shown in the single persistent Metal view: the uncropped frame while cropping,
    /// the original while comparing, otherwise the live edit.
    private var baseImage: CIImage {
        if model.isCropping { return model.cropDisplayImage }
        return isComparing ? model.source : model.displayImage
    }

    private var framedImage: some View {
        // ONE MetalImageView for every mode — its source switches, but the view (and its MTKView)
        // is never torn down, so entering/leaving crop is seamless (no blank-frame flash).
        ZStack {
            MetalImageView(image: baseImage)
                .scaleEffect(model.isCropping ? 1 : zoomScale)
                .offset(model.isCropping ? .zero : zoomOffset)
            // Once a zoom settles, swap in a crisp full-res tile of the visible region for true
            // pixel-peeping; it sits on top of (and matches) the scaled preview.
            if !model.isCropping, let inspectTile, zoomScale > 1, !zoomGestureActive {
                Image(decorative: inspectTile, scale: displayScale)
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)
            }
            // Crop chrome (dim + grid + move) overlays the same image while cropping.
            if model.isCropping {
                CropCanvas(model: model)
                    .transition(.opacity)
            }
        }
        .background(   // measure the fit size (unscaled) for pan clamping + tile mapping
            GeometryReader { geo in
                Color.clear
                    .onAppear { fitSize = geo.size }
                    .onChange(of: geo.size) { _, s in fitSize = s }
            }
        )
        // Pinch/pan to inspect when not cropping; while cropping, hand touches to the crop chrome.
        .gesture(inspectGesture, including: model.isCropping ? .subviews : .all)
        .onChange(of: model.isCropping) { _, _ in resetZoom(animated: false) }
        .onChange(of: model.selectedTool) { _, _ in resetZoom(animated: false) }
        .onChange(of: model.state) { _, _ in inspectTile = nil; scheduleInspectTile() }
        // Tap the photo to compare against the original (a sticky toggle). This catcher sits BELOW
        // the dial/controls overlay (declared earlier in the chain), so a tap on the dial scrubs and
        // never flips the comparison — and grabbing the dial clears it instantly (see the dial's
        // onBegin). The (i) and aspect controls are layered above too, so they win in their corners.
        .overlay {
            // Only while at fit — when zoomed in, the catcher steps aside so pan/pinch own the photo.
            if !model.isCropping && zoomScale == 1 {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard model.hasEdits, !showStyles, !showInfo else { return }
                        withAnimation(Theme.Motion.snappy) { isComparing.toggle() }
                        Haptics.impact(.soft)
                    }
            }
        }
        .overlay {
            if celebrate {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce, value: celebrate)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        // Tap anywhere on the image to dismiss the open info panel — the native way (no close button).
        .overlay {
            if showInfo {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(reduceMotion ? nil : .default) { showInfo = false } }
            }
        }
        // (i) hidden while cropping so it doesn't crowd the corner handle.
        .overlay(alignment: .topLeading) { if !model.isCropping { infoMorph } }
        // Aspect-ratio menu — top-right, taking the (i)'s place while cropping.
        .overlay(alignment: .topTrailing) { if model.isCropping { aspectMenu } }
        .overlay(alignment: .top) {
            if isComparing && !showInfo {
                GlassPill("Original")
                    .padding(.top, Theme.Space.m)
                    .transition(.opacity.combined(with: .scale))
                    .allowsHitTesting(false)   // tap passes through to the catcher to toggle back
            }
        }
        // Portrait: the dial overlays the image bottom (with a scrim). Landscape: it lives in the
        // centre column instead, so suppress the overlay here.
        .overlay(alignment: .bottom) { if !isLandscape { dialSlot(scrim: true) } }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.image, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.image, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        // Resize grips drawn OUTSIDE the clip so they're never cut off by the rounded corners.
        .overlay { if model.isCropping { CropHandles(model: model) } }
    }

    /// Aspect-ratio picker shown top-right while cropping (mirrors the (i) top-left).
    private var aspectMenu: some View {
        Menu {
            Button("Free") { chooseAspect(nil) }
            Button("Square") { chooseAspect(1) }
            Button("4 : 3") { chooseAspect(4.0 / 3.0) }
            Button("3 : 2") { chooseAspect(3.0 / 2.0) }
            Button("16 : 9") { chooseAspect(16.0 / 9.0) }
        } label: {
            Color.clear
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: "aspectratio").font(.system(size: 15, weight: .semibold)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .padding(Theme.Space.m)
        .accessibilityLabel("Aspect ratio")
    }

    private func chooseAspect(_ ratio: Double?) {
        model.setCropAspect(ratio)
        Haptics.selection()
    }

    /// Smooth spring for entering/leaving crop, so the card's aspect and the chrome morph rather
    /// than snap (respects Reduce Motion).
    private var cropMotion: Animation? { reduceMotion ? nil : .smooth(duration: 0.35) }

    // MARK: Pinch-to-inspect

    /// Pinch to zoom the preview up to 4× and two-finger / one-finger drag to pan while zoomed.
    /// Purely a viewing aid (never mutates the recipe); springs back to fit when you pinch below 1×.
    private var inspectGesture: some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { v in
                    zoomGestureActive = true
                    isComparing = false       // zooming exits compare so the tile can't mismatch
                    inspectTile = nil          // show the live (scaled) preview while interacting
                    zoomScale = min(max(committedScale * v.magnification, 1), 4)
                    zoomOffset = clampedOffset(committedOffset)
                }
                .onEnded { _ in
                    zoomGestureActive = false
                    if zoomScale <= 1.01 {
                        resetZoom(animated: true)
                    } else {
                        committedScale = zoomScale
                        committedOffset = zoomOffset
                        scheduleInspectTile()
                    }
                },
            DragGesture()
                .onChanged { v in
                    guard zoomScale > 1 else { return }   // panning only makes sense when zoomed in
                    zoomGestureActive = true
                    inspectTile = nil
                    zoomOffset = clampedOffset(CGSize(width: committedOffset.width + v.translation.width,
                                                      height: committedOffset.height + v.translation.height))
                }
                .onEnded { _ in
                    guard zoomScale > 1 else { return }
                    committedOffset = zoomOffset
                    zoomGestureActive = false
                    scheduleInspectTile()
                }
        )
    }

    /// Debounced: render the crisp full-res tile a beat after the zoom/pan settles (or after an
    /// edit), then fade it in. Cancels in flight if anything changes again.
    private func scheduleInspectTile() {
        tileTask?.cancel()
        guard zoomScale > 1, !zoomGestureActive, fitSize.width > 0 else { return }
        let scale = displayScale
        tileTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled, zoomScale > 1, !zoomGestureActive, fitSize.width > 0 else { return }
            let z = zoomScale, w = fitSize.width, h = fitSize.height
            let half = 1 / (2 * z)
            let unit = CGRect(x: 0.5 - zoomOffset.width / (z * w) - half,
                              y: 0.5 - zoomOffset.height / (z * h) - half,
                              width: 1 / z, height: 1 / z)
            if let cg = model.inspectTile(unitRect: unit, pixelWidth: w * scale) {
                withAnimation(.easeOut(duration: 0.15)) { inspectTile = cg }
            }
        }
    }

    /// Keep the panned image covering the frame — no empty gaps at the edges.
    private func clampedOffset(_ o: CGSize) -> CGSize {
        let maxX = max(0, fitSize.width * (zoomScale - 1) / 2)
        let maxY = max(0, fitSize.height * (zoomScale - 1) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX),
                      height: min(max(o.height, -maxY), maxY))
    }

    private func resetZoom(animated: Bool) {
        tileTask?.cancel()
        inspectTile = nil
        let apply = { zoomScale = 1; committedScale = 1; zoomOffset = .zero; committedOffset = .zero }
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { apply() }
        } else {
            apply()
        }
    }

    /// The (i) button that morphs (Liquid Glass) into the metadata panel and back. Same
    /// `glassEffectID` on both states inside a `GlassEffectContainer` drives the morph. There's no
    /// close button: the panel dismisses on tap (itself or anywhere on the image), the way the system
    /// camera/settings panels do.
    private var infoMorph: some View {
        GlassEffectContainer {
            Group {
                if showInfo {
                    metadataPanelContent
                        .glassEffect(in: .rect(cornerRadius: Theme.Radius.card))
                        .glassEffectID("info", in: infoGlass)
                } else {
                    Button {
                        withAnimation(reduceMotion ? nil : .default) { showInfo = true }
                    } label: {
                        Color.clear
                            .frame(width: 38, height: 38)
                            .overlay(Image(systemName: "info").font(.system(size: 16, weight: .semibold)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("info", in: infoGlass)
                }
            }
        }
        .padding(Theme.Space.m)
        // The native glassEffectID morph is driven by the withAnimation transaction on the buttons —
        // a single driver (no competing .animation(value:)), so it doesn't step on close.
    }

    /// Inline, top-level metadata (format, dimensions, size, date), laid out like the system camera
    /// settings panel: uppercase secondary labels in a left column, values aligned beside them. No
    /// close button — tap the panel (or anywhere on the image) to morph it back to the (i).
    private var metadataPanelContent: some View {
        let rows = model.originalData.map { ImageLoader.topLevelMetadata(from: $0) } ?? []
        return Group {
            if rows.isEmpty {
                Text("No info available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: Theme.Space.s) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.label.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(row.value)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .gridColumnAlignment(.leading)
                        }
                    }
                }
            }
        }
        .padding(Theme.Space.l)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(reduceMotion ? nil : .default) { showInfo = false } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Image info: " + rows.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
        .accessibilityHint("Tap to close")
    }

    private var hasBottomControls: Bool {
        model.isCropping || showStyles || model.selectedTool != nil
    }

    /// The dial (or styles strip). Portrait mounts it as a bottom overlay on the image with a scrim;
    /// landscape mounts it bare in the centre column (`scrim: false`). Same content either way.
    @ViewBuilder
    private func dialSlot(scrim: Bool) -> some View {
      if hasBottomControls {
        VStack(spacing: Theme.Space.s) {
            if model.isCropping {
                // Crop uses the same dial slot — for straighten, like every other tool.
                straightenReadout
                HapticDial(
                    value: straightenBinding,
                    range: -0.4...0.4,
                    detent: 0.0175,   // ≈ 1° steps
                    label: "Straighten",
                    soundEnabled: soundEnabled
                )
                .padding(.horizontal, Theme.Space.l)
            } else if showStyles {
                if model.hasActiveStyle && !browsingStyles {
                    // Selected style: the dial now controls the style's intensity.
                    styleReadout
                    HapticDial(
                        value: styleIntensityBinding,
                        range: 0...1,
                        detent: 0.025,
                        label: "Style strength",
                        soundEnabled: soundEnabled,
                        onBegin: { model.beginInteraction() },
                        onCommit: { model.endInteraction() }
                    )
                    .padding(.horizontal, Theme.Space.l)
                } else {
                    // The list — opens scrolled to the active look, which stays applied while you browse.
                    StyleStrip(source: model.source, styles: styleProvider.styles,
                               activeStyleID: model.activeStyle?.id) { style in
                        withAnimation(Theme.Motion.snappy) {
                            // OG is a clean revert (no intensity dial); every other look applies as
                            // an active style the dial can then scale.
                            if style.id == Style.original.id {
                                model.revertToOriginal()
                            } else {
                                model.applyStyle(style)
                            }
                            browsingStyles = false
                        }
                    }
                    .padding(.bottom, Theme.Space.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else if let tool = model.selectedTool {
                readout
                HapticDial(
                    value: dialBinding,
                    range: tool.range,
                    detent: tool.detent,
                    label: tool.title,
                    soundEnabled: soundEnabled,
                    onBegin: { isComparing = false; model.beginInteraction() },
                    onCommit: { model.endInteraction() }
                )
                .padding(.horizontal, Theme.Space.l)
            }
        }
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.m)
        .frame(maxWidth: .infinity)
        .background {
            if scrim {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
        }
        // First-load entrance: slide up from the image and fade in (see revealControls in `.task`).
        .offset(y: revealControls ? 0 : 28)
        .opacity(revealControls ? 1 : 0)
      }
    }

    /// The X beside Done: dismisses the active style (→ carousel), closes the styles strip, or
    /// clears the current tool's edit. Hidden when there's nothing to clear.
    @ViewBuilder
    private var resetButton: some View {
        if showStyles && model.hasActiveStyle && !browsingStyles {
            // Intensity-dial mode → the X removes the look (back to the list).
            GlassIconButton("xmark", label: "Remove style") {
                withAnimation(Theme.Motion.snappy) { model.dismissStyle() }
                Haptics.impact(.rigid)
            }
            .transition(.scale.combined(with: .opacity))
        } else if showStyles {
            // List mode → the X closes styles (back to the tools), keeping any applied look.
            GlassIconButton("xmark", label: "Close styles") {
                withAnimation(Theme.Motion.snappy) { showStyles = false; browsingStyles = false }
            }
            .transition(.scale.combined(with: .opacity))
        } else if let tool = model.selectedTool, model.value(of: tool) != 0 {
            GlassIconButton("xmark", label: "Reset \(tool.title)") {
                model.beginInteraction()
                model.update(tool, to: 0)
                model.endInteraction()
                Haptics.impact(.rigid)
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var styleReadout: some View {
        VStack(spacing: 2) {
            Text("\(Int((model.styleIntensity * 100).rounded()))%")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
            Text(model.activeStyle?.name ?? "Style")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            if let artist = model.activeStyle?.artist {
                Text("by \(artist)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 4)
        .animation(Theme.Motion.snappy, value: model.styleIntensity)
    }

    private var styleIntensityBinding: Binding<Double> {
        Binding(get: { model.styleIntensity }, set: { model.setStyleIntensity($0) })
    }

    private var straightenReadout: some View {
        VStack(spacing: 2) {
            Text(String(format: "%+.0f°", model.cropStraighten * 180 / .pi))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
            Text("Straighten")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .shadow(color: .black.opacity(0.4), radius: 4)
        .animation(Theme.Motion.snappy, value: model.cropStraighten)
    }

    private var straightenBinding: Binding<Double> {
        Binding(get: { model.cropStraighten }, set: { model.setCropStraighten($0) })
    }

    // MARK: Action buttons (top bar in portrait, left rail in landscape — same buttons)

    private var galleryButton: some View {
        GlassIconButton("square.grid.2x2", label: "Gallery") { onCancel() }
    }
    private var undoButton: some View {
        GlassIconButton("arrow.uturn.backward", label: "Undo") { model.undo() }
            .disabled(!model.canUndo)
            .opacity(model.canUndo ? 1 : 0.35)
    }
    private var redoButton: some View {
        GlassIconButton("arrow.uturn.forward", label: "Redo") { model.redo() }
            .disabled(!model.canRedo)
            .opacity(model.canRedo ? 1 : 0.35)
    }
    /// Sits between Undo and Redo: revert every change back to the original (one step, undoable).
    private var revertButton: some View {
        GlassIconButton("arrow.counterclockwise", label: "Revert all changes") {
            guard model.hasEdits else { return }
            withAnimation(Theme.Motion.snappy) { model.reset() }
            Haptics.impact(.rigid)
        }
        .disabled(!model.hasEdits)
        .opacity(model.hasEdits ? 1 : 0.35)
    }
    private var shareButton: some View {
        GlassIconButton(isExporting ? "ellipsis" : "square.and.arrow.up", label: "Share") { share() }
            .disabled(isExporting || exporter == nil)
            .opacity(exporter == nil ? 0.35 : (isExporting ? 0.5 : 1))   // dim while working
    }

    /// Portrait: Gallery | Undo · Revert · Redo | Share across the top.
    /// Grouped in a GlassEffectContainer so the system batches the glass (Apple's recommended pattern
    /// for multiple glass effects).
    private var topBar: some View {
        GlassEffectContainer {
            HStack {
                galleryButton
                Spacer()
                HStack(spacing: Theme.Space.s) { undoButton; revertButton; redoButton }
                Spacer()
                shareButton
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    /// Landscape: the same buttons as a left rail — Gallery top, Undo · Revert · Redo centred,
    /// Share bottom.
    private var actionRail: some View {
        GlassEffectContainer {
            VStack(spacing: Theme.Space.m) {
                galleryButton
                Spacer(minLength: 0)
                undoButton
                revertButton
                redoButton
                Spacer(minLength: 0)
                shareButton
            }
        }
        .padding(.vertical, Theme.Space.s)
    }

    // MARK: Tool strip (underneath the image)

    private func toolStrip(axis: Axis) -> some View {
        ToolBar(
            actions: [
                ToolBarAction(id: "styles", title: "Styles", systemImage: "wand.and.stars", tinted: showStyles) {
                    // Tapping Styles opens the list. If a look is active, BROWSE it: keep the look
                    // applied and land the list on that look (don't revert or jump to the front).
                    isComparing = false
                    withAnimation(Theme.Motion.snappy) {
                        browsingStyles = true
                        showStyles = true
                    }
                },
                ToolBarAction(id: "crop", title: "Crop & Rotate", systemImage: "crop.rotate", showsDot: geometryEdited) {
                    isComparing = false
                    withAnimation(cropMotion) { model.beginCrop() }
                }
            ],
            selected: model.selectedTool,
            editedTools: editedTools,
            highlightSelection: !showStyles,   // in Styles mode the Styles chip is the active one
            axis: axis,
            onSelect: handleToolSelect
        )
    }

    private func handleToolSelect(_ tool: EditTool) {
        let wasShowingStyles = showStyles
        // Reaching for a tool turns the active style into the manual starting point.
        if model.hasActiveStyle { model.bakeStyle() }
        showStyles = false
        browsingStyles = false
        // Tapping the already-selected tool that carries an edit reverts it to 0 — the same action
        // as its X, just on the chip itself. (Not when arriving from Styles mode, where the tap is
        // really a selection.)
        if !wasShowingStyles, model.selectedTool == tool, model.value(of: tool) != 0 {
            model.beginInteraction()
            model.update(tool, to: 0)
            model.endInteraction()
            Haptics.impact(.rigid)
        } else {
            withAnimation(Theme.Motion.snappy) { model.selectedTool = tool }
        }
    }

    private var actionBar: some View {
        Button { commitDone() } label: {
            Text("Done")
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, 14)
        }
        // Native translucent Liquid Glass; on tap it fills with the accent colour as confirmation.
        .buttonStyle(.glass)
        .tint(donePressed ? Theme.accent : .white)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { resetButton }
        .padding(.horizontal, Theme.Space.l)
    }

    private func commitDone() {
        guard !isCommitting else { return }   // ignore a second tap during the confirm beat
        isCommitting = true
        Haptics.impact(.soft)
        // Snapshot the recipe now, so what we commit can't drift if anything mutates the model
        // during the brief confirmation animation.
        let state = model.state
        guard !reduceMotion else { onDone(state); return }   // no cosmetic delay under Reduce Motion
        withAnimation(.easeOut(duration: 0.18)) { donePressed = true }
        Task {
            try? await Task.sleep(for: .milliseconds(170))
            onDone(state)
        }
    }

    // MARK: Crop chrome (rotate/flip where the tool chips sit; Done + X like the editor)

    /// Rotate/flip buttons — laid out in an HStack (portrait) or VStack (landscape rail).
    @ViewBuilder
    private var cropButtons: some View {
        GlassIconButton("rotate.left", label: "Rotate left", size: 54) { model.rotateQuarter(-1); Haptics.impact(.light) }
        GlassIconButton("rotate.right", label: "Rotate right", size: 54) { model.rotateQuarter(1); Haptics.impact(.light) }
        GlassIconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Flip horizontally", size: 54) { model.toggleFlipH(); Haptics.impact(.light) }
        GlassIconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", label: "Flip vertically", size: 54) { model.toggleFlipV(); Haptics.impact(.light) }
    }

    private var cropToolStrip: some View {
        // 54pt buttons + 10 vertical padding == the ToolBar's height, so the image doesn't shift
        // size between the normal tools and crop.
        HStack(spacing: Theme.Space.l) { cropButtons }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private var cropActionBar: some View {
        Button {
            Haptics.impact(.soft)
            withAnimation(cropMotion) { model.commitCrop() }
        } label: {
            Text("Done")
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, 14)
        }
        .buttonStyle(.glass)
        .tint(.white)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            GlassIconButton("xmark", label: "Cancel crop") { withAnimation(cropMotion) { model.cancelCrop() } }
        }
        .padding(.horizontal, Theme.Space.l)
    }

    private var readout: some View {
        VStack(spacing: 2) {
            Text(model.selectedTool?.readout(in: model.state) ?? "")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
            Text(model.selectedTool?.title ?? "")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .shadow(color: .black.opacity(0.4), radius: 4)
        .animation(Theme.Motion.snappy, value: model.selectedTool.map { model.value(of: $0) })
    }

    private func share() {
        guard let exporter, !isExporting else { return }
        isExporting = true
        Task {
            let url = await exporter(model.state)
            isExporting = false
            if let url {
                Haptics.notify(.success)
                triggerCelebrate()
                shareItem = ShareItem(url: url)
            } else {
                Haptics.notify(.error)
                exportFailed = true
            }
        }
    }

    /// A brief sparkle when an export is ready — a small "ta-da" for saving/sharing a photo.
    private func triggerCelebrate() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { celebrate = true }
        Task {
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.easeOut(duration: 0.4)) { celebrate = false }
        }
    }

    private var editedTools: Set<EditTool> {
        Set(EditTool.dialTools.filter { model.value(of: $0) != 0 })
    }

    private var geometryEdited: Bool {
        let s = model.state
        return !s.crop.isFull || s.straightenAngle != 0 || s.rotationQuarterTurns != 0
            || s.flippedHorizontally || s.flippedVertically
    }

    private var dialBinding: Binding<Double> {
        Binding(
            get: { model.selectedTool.map { model.value(of: $0) } ?? 0 },
            set: { v in if let t = model.selectedTool { model.update(t, to: v) } }
        )
    }
}
