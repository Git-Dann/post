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
    @Namespace private var infoGlass
    @AppStorage("soundEffectsEnabled") private var soundEnabled = false

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
                    .aspectRatio(model.aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, Theme.Space.s)

                if showsChrome && !model.isCropping {
                    toolStrip
                    actionBar
                        .padding(.bottom, Theme.Space.s)
                }
            }

            if model.isCropping {
                CropOverlay(model: model)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.settle, value: model.isCropping)
        .animation(Theme.Motion.settle, value: showStyles)
        .statusBarHidden()
        .sheet(item: $shareItem) { item in ActivityView(items: [item.url]) }
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
            if args.contains("--open-crop") { model.isCropping = true }
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

    private var framedImage: some View {
        MetalImageView(image: isComparing ? model.source : model.displayImage)
            // Press and hold the image to compare against the original. Attached to the image itself,
            // BELOW the controls overlay, so it never competes with the dial drag — that competition
            // was hijacking the touch and pinning the preview to the original mid-drag (the cause of
            // "no live preview"). The `!isAdjustingDial` guard is a second line of defence.
            .onLongPressGesture(minimumDuration: 0.18, maximumDistance: 60) {
            } onPressingChanged: { pressing in
                guard model.hasEdits, !showStyles, !showInfo, !isAdjustingDial else { return }
                withAnimation(Theme.Motion.snappy) { isComparing = pressing }
                if pressing { Haptics.impact(.soft) }
            }
            .overlay(alignment: .topLeading) { infoMorph }
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
                        withAnimation { showInfo = true }
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
                    withAnimation { showInfo = false }
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

    /// The dial (or styles strip) that lives inside the bottom of the image, over a scrim.
    private var imageControls: some View {
        VStack(spacing: Theme.Space.s) {
            if showStyles {
                if model.hasActiveStyle {
                    // Selected style: the dial now controls the style's intensity.
                    styleReadout
                    HapticDial(
                        value: styleIntensityBinding,
                        range: 0...1,
                        detent: 0.025,
                        soundEnabled: soundEnabled,
                        onBegin: { model.beginInteraction() },
                        onCommit: { model.endInteraction() }
                    )
                    .padding(.horizontal, Theme.Space.l)
                } else {
                    StyleStrip(source: model.source, styles: styleProvider.styles) { style in
                        withAnimation(Theme.Motion.settle) { model.applyStyle(style) }
                    }
                    .padding(.bottom, Theme.Space.s)
                }
            } else {
                readout
                HapticDial(
                    value: dialBinding,
                    range: model.selectedTool.range,
                    detent: model.selectedTool.detent,
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

    /// The X beside Done: dismisses the active style (→ carousel), closes the styles strip, or
    /// clears the current tool's edit. Hidden when there's nothing to clear.
    @ViewBuilder
    private var resetButton: some View {
        if showStyles && model.hasActiveStyle {
            GlassIconButton("xmark") {
                withAnimation(Theme.Motion.settle) { model.dismissStyle() }
                Haptics.impact(.rigid)
            }
            .transition(.scale.combined(with: .opacity))
        } else if showStyles {
            GlassIconButton("xmark") {
                withAnimation(Theme.Motion.settle) { showStyles = false }
            }
            .transition(.scale.combined(with: .opacity))
        } else if model.value(of: model.selectedTool) != 0 {
            GlassIconButton("xmark") {
                model.beginInteraction()
                model.update(model.selectedTool, to: 0)
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

    // MARK: Top bar (on the canvas, above the image)

    private var topBar: some View {
        HStack {
            GlassIconButton("square.grid.2x2") { onCancel() }
            Spacer()
            HStack(spacing: Theme.Space.s) {
                GlassIconButton("arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo)
                    .opacity(model.canUndo ? 1 : 0.35)
                GlassIconButton("arrow.uturn.forward") { model.redo() }
                    .disabled(!model.canRedo)
                    .opacity(model.canRedo ? 1 : 0.35)
            }
            Spacer()
            GlassIconButton(isExporting ? "ellipsis" : "square.and.arrow.up") { share() }
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
                    withAnimation(Theme.Motion.settle) { showStyles = true }
                },
                ToolBarAction(id: "crop", title: "Crop & Rotate", systemImage: "crop.rotate", showsDot: geometryEdited) {
                    model.isCropping = true
                }
            ],
            selected: model.selectedTool,
            editedTools: editedTools,
            highlightSelection: !showStyles   // in Styles mode the Styles chip is the active one
        ) { tool in
            withAnimation(Theme.Motion.snappy) {
                // Reaching for a tool turns the active style into the manual starting point.
                if model.hasActiveStyle { model.bakeStyle() }
                showStyles = false
                model.selectedTool = tool
            }
        }
    }

    private var actionBar: some View {
        Button { onDone(model.state) } label: {
            Text("Done")
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, 14)
        }
        .buttonStyle(.glassProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { resetButton }
        .padding(.horizontal, Theme.Space.l)
    }

    private var readout: some View {
        VStack(spacing: 2) {
            Text(model.selectedTool.readout(in: model.state))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
            Text(model.selectedTool.title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .shadow(color: .black.opacity(0.4), radius: 4)
        .animation(Theme.Motion.snappy, value: model.value(of: model.selectedTool))
    }

    private func share() {
        guard let exporter, !isExporting else { return }
        isExporting = true
        Task {
            let url = await exporter(model.state)
            isExporting = false
            if let url { shareItem = ShareItem(url: url) }
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
            get: { model.value(of: model.selectedTool) },
            set: { model.update(model.selectedTool, to: $0) }
        )
    }
}
