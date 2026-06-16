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
    @State private var showInfo = false
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
        .animation(Theme.Motion.settle, value: showInfo)
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
            #endif
        }
    }

    // MARK: Framed image (with the controls living inside it)

    private var framedImage: some View {
        MetalImageView(image: isComparing ? model.source : model.displayImage)
            .overlay(alignment: .topLeading) {
                if !showInfo { infoButton }
            }
            .overlay(alignment: .top) {
                if showInfo {
                    metadataPanel
                        .padding(Theme.Space.m)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if isComparing {
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
            // Press and hold the image to compare against the original.
            .onLongPressGesture(minimumDuration: 0.18, maximumDistance: 60) {
            } onPressingChanged: { pressing in
                guard model.hasEdits, !showStyles, !showInfo else { return }
                withAnimation(Theme.Motion.snappy) { isComparing = pressing }
                if pressing { Haptics.impact(.soft) }
            }
    }

    private var infoButton: some View {
        GlassIconButton("info", size: 38) {
            withAnimation(Theme.Motion.settle) { showInfo = true }
        }
        .disabled(model.originalData == nil)
        .opacity(model.originalData == nil ? 0.35 : 1)
        .padding(Theme.Space.m)
    }

    /// Inline, top-level metadata panel inside the image (format, size, dimensions, date).
    private var metadataPanel: some View {
        let rows = model.originalData.map { ImageLoader.topLevelMetadata(from: $0) } ?? []
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                GlassIconButton("xmark", size: 34) {
                    withAnimation(Theme.Motion.settle) { showInfo = false }
                }
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
        .glassEffect(in: .rect(cornerRadius: Theme.Radius.card))
    }

    /// The dial (or styles strip) that lives inside the bottom of the image, over a scrim.
    private var imageControls: some View {
        VStack(spacing: Theme.Space.s) {
            if showStyles {
                StyleStrip(source: model.source, styles: styleProvider.styles) { style in
                    model.applyRecipe(style.recipe)
                    withAnimation(Theme.Motion.settle) { showStyles = false }
                }
                .padding(.bottom, Theme.Space.s)
            } else {
                readout
                HapticDial(
                    value: dialBinding,
                    range: model.selectedTool.range,
                    detent: model.selectedTool.detent,
                    soundEnabled: soundEnabled,
                    onBegin: { model.beginInteraction() },
                    onCommit: { model.endInteraction() }
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

    /// The X beside Done: clears the current tool's edit, or closes the styles strip. Hidden when
    /// there's nothing to clear.
    @ViewBuilder
    private var resetButton: some View {
        if showStyles {
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
            editedTools: editedTools
        ) { tool in
            withAnimation(Theme.Motion.snappy) {
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
