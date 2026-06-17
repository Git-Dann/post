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
    @State private var shareItem: ShareItem?
    @State private var isExporting = false
    @State private var isComparing = false
    @State private var isAdjustingDial = false
    @State private var showInfo = false
    @State private var celebrate = false
    @State private var donePressed = false
    @State private var isCommitting = false
    @State private var exportFailed = false
    @Namespace private var infoGlass
    @AppStorage("soundEffectsEnabled") private var soundEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        toolStrip
                        actionBar
                            .padding(.bottom, Theme.Space.s)
                    }
                }
            }
        }
        .statusBarHidden()
        .sheet(item: $shareItem) { item in ActivityView(items: [item.url]) }
        .alert("Couldn't export this photo", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Something went wrong rendering the image. Please try again.")
        }
        .task {
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

    // MARK: Framed image (with the controls living inside it)

    @ViewBuilder
    private var framedImage: some View {
        Group {
            if model.isCropping {
                CropCanvas(model: model)
            } else {
                MetalImageView(image: isComparing ? model.source : model.displayImage)
            }
        }
        // Press and hold to compare against the original (disabled while cropping).
        .onLongPressGesture(minimumDuration: 0.18, maximumDistance: 60) {
        } onPressingChanged: { pressing in
            guard model.hasEdits, !showStyles, !showInfo, !isAdjustingDial, !model.isCropping else { return }
            withAnimation(Theme.Motion.snappy) { isComparing = pressing }
            if pressing { Haptics.impact(.soft) }
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
        // (i) hidden while cropping so it doesn't crowd the corner handle.
        .overlay(alignment: .topLeading) { if !model.isCropping { infoMorph } }
        // Aspect-ratio menu — top-right, taking the (i)'s place while cropping.
        .overlay(alignment: .topTrailing) { if model.isCropping { aspectMenu } }
        .overlay(alignment: .top) {
            if isComparing && !showInfo {
                GlassPill("Original")
                    .padding(.top, Theme.Space.m)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .overlay(alignment: .bottom) { imageControls }
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
            Button("Free") { model.setCropAspect(nil) }
            Button("Square") { model.setCropAspect(1) }
            Button("4 : 3") { model.setCropAspect(4.0 / 3.0) }
            Button("3 : 2") { model.setCropAspect(3.0 / 2.0) }
            Button("16 : 9") { model.setCropAspect(16.0 / 9.0) }
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

    /// The (i) button that morphs (Liquid Glass) into the metadata panel and back. Same
    /// `glassEffectID` on both states inside a `GlassEffectContainer` does the morph; the X ends up
    /// sitting where the (i) was.
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

    /// Inline, top-level metadata (format, size, dimensions, date). The X sits top-left, over where
    /// the (i) was.
    private var metadataPanelContent: some View {
        let rows = model.originalData.map { ImageLoader.topLevelMetadata(from: $0) } ?? []
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : .default) { showInfo = false }
                } label: {
                    Color.clear
                        .frame(width: 30, height: 30)
                        .overlay(Image(systemName: "xmark").font(.system(size: 14, weight: .bold)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            if rows.isEmpty {
                Text("No info available")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ForEach(rows) { row in
                    HStack {
                        Text(row.label).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(row.value).fontWeight(.medium).foregroundStyle(.white)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasBottomControls: Bool {
        model.isCropping || showStyles || model.selectedTool != nil
    }

    /// The dial (or styles strip) that lives inside the bottom of the image, over a scrim.
    @ViewBuilder
    private var imageControls: some View {
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
                if model.hasActiveStyle {
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
                    StyleStrip(source: model.source, styles: styleProvider.styles) { style in
                        // OG is a clean revert (no intensity dial); every other look applies as an
                        // active style the dial can then scale. No animation — instant.
                        if style.id == Style.original.id {
                            model.revertToOriginal()
                        } else {
                            model.applyStyle(style)
                        }
                    }
                    .padding(.bottom, Theme.Space.s)
                }
            } else if let tool = model.selectedTool {
                readout
                HapticDial(
                    value: dialBinding,
                    range: tool.range,
                    detent: tool.detent,
                    label: tool.title,
                    soundEnabled: soundEnabled,
                    onBegin: { isAdjustingDial = true; isComparing = false; model.beginInteraction() },
                    onCommit: { isAdjustingDial = false; model.endInteraction() }
                )
                .padding(.horizontal, Theme.Space.l)
            }
        }
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.m)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
      }
    }

    /// The X beside Done: dismisses the active style (→ carousel), closes the styles strip, or
    /// clears the current tool's edit. Hidden when there's nothing to clear.
    @ViewBuilder
    private var resetButton: some View {
        if showStyles && model.hasActiveStyle {
            GlassIconButton("xmark", label: "Remove style") {
                model.dismissStyle()
                Haptics.impact(.rigid)
            }
            .transition(.scale.combined(with: .opacity))
        } else if showStyles {
            GlassIconButton("xmark", label: "Close styles") {
                showStyles = false
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

    // MARK: Top bar (on the canvas, above the image)

    private var topBar: some View {
        HStack {
            GlassIconButton("square.grid.2x2", label: "Gallery") { onCancel() }
            Spacer()
            HStack(spacing: Theme.Space.s) {
                GlassIconButton("arrow.uturn.backward", label: "Undo") { model.undo() }
                    .disabled(!model.canUndo)
                    .opacity(model.canUndo ? 1 : 0.35)
                GlassIconButton("arrow.uturn.forward", label: "Redo") { model.redo() }
                    .disabled(!model.canRedo)
                    .opacity(model.canRedo ? 1 : 0.35)
            }
            Spacer()
            GlassIconButton(isExporting ? "ellipsis" : "square.and.arrow.up", label: "Share") { share() }
                .disabled(isExporting || exporter == nil)
                .opacity(exporter == nil ? 0.35 : 1)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    // MARK: Tool strip (underneath the image)

    private var toolStrip: some View {
        ToolBar(
            actions: [
                ToolBarAction(id: "styles", title: "Styles", systemImage: "wand.and.stars", tinted: showStyles) {
                    // Tapping Styles always lands on the picker — if a look is active, step back to it.
                    if model.hasActiveStyle { model.dismissStyle() }
                    showStyles = true
                },
                ToolBarAction(id: "crop", title: "Crop & Rotate", systemImage: "crop.rotate", showsDot: geometryEdited) {
                    model.beginCrop()
                }
            ],
            selected: model.selectedTool,
            editedTools: editedTools,
            highlightSelection: !showStyles   // in Styles mode the Styles chip is the active one
        ) { tool in
            // Reaching for a tool turns the active style into the manual starting point.
            if model.hasActiveStyle { model.bakeStyle() }
            showStyles = false
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

    private var cropToolStrip: some View {
        // 54pt buttons + 10 vertical padding == the ToolBar's height, so the image doesn't shift
        // size between the normal tools and crop.
        HStack(spacing: Theme.Space.l) {
            GlassIconButton("rotate.left", label: "Rotate left", size: 54) { model.rotateQuarter(-1); Haptics.impact(.light) }
            GlassIconButton("rotate.right", label: "Rotate right", size: 54) { model.rotateQuarter(1); Haptics.impact(.light) }
            GlassIconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Flip horizontally", size: 54) { model.toggleFlipH(); Haptics.impact(.light) }
            GlassIconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", label: "Flip vertically", size: 54) { model.toggleFlipV(); Haptics.impact(.light) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var cropActionBar: some View {
        Button {
            Haptics.impact(.soft)
            model.commitCrop()
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
            GlassIconButton("xmark", label: "Cancel crop") { model.cancelCrop() }
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
