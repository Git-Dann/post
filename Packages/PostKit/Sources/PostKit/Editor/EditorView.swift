import SwiftUI

/// The hero editing screen. Full-bleed image on a near-black canvas with floating Liquid Glass
/// chrome: a top bar (close / undo-redo / share), the value readout + haptic dial, the tool strip,
/// and the action row. Shared by the app and both extensions.
public struct EditorView: View {
    private let model: EditorModel
    private let onDone: (EditState) -> Void
    private let onCancel: () -> Void
    private let exporter: ((EditState) async -> URL?)?
    private let exportFormatLabel: String
    private let showsChrome: Bool

    @State private var styleProvider: StyleProvider
    @State private var showStyles = false
    @State private var shareItem: ShareItem?
    @State private var isExporting = false
    @State private var isComparing = false
    @AppStorage("soundEffectsEnabled") private var soundEnabled = false

    /// - Parameters:
    ///   - exporter: produces a shareable file URL for the given recipe (full-res export),
    ///     provided by the host so the engine stays UI-agnostic. Returns nil on failure.
    ///   - showsChrome: when false, the top bar and Done/Cancel action row are hidden — used by the
    ///     Photos editing extension, where the host (Photos) provides its own Done/Cancel chrome.
    public init(
        model: EditorModel,
        exportFormatLabel: String = "HEIC",
        styleSource: StyleSource = BundledStyleSource(),
        showsChrome: Bool = true,
        exporter: ((EditState) async -> URL?)? = nil,
        onDone: @escaping (EditState) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.model = model
        self.exportFormatLabel = exportFormatLabel
        self.showsChrome = showsChrome
        self.exporter = exporter
        self.onDone = onDone
        self.onCancel = onCancel
        _styleProvider = State(initialValue: StyleProvider(source: styleSource))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MetalImageView(image: isComparing ? model.source : model.displayImage)
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    if isComparing {
                        GlassPill("Original")
                            .padding(.top, 80)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                // Press and hold anywhere on the image to compare against the original.
                .onLongPressGesture(minimumDuration: 0.18, maximumDistance: 60) {
                } onPressingChanged: { pressing in
                    guard model.hasEdits else { return }
                    withAnimation(Theme.Motion.snappy) { isComparing = pressing }
                    if pressing { Haptics.impact(.soft) }
                }

            VStack(spacing: 0) {
                if showsChrome { topBar }
                Spacer(minLength: 0)
                if !model.isCropping {
                    if showStyles {
                        stylePanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        bottomControls
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
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
        .task {
            await styleProvider.loadIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--show-styles") {
                showStyles = true
            }
            #endif
        }
    }

    // MARK: Top bar

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
            HStack(spacing: Theme.Space.s) {
                GlassPill(exportFormatLabel)
                GlassIconButton(isExporting ? "ellipsis" : "square.and.arrow.up") { share() }
                    .disabled(isExporting || exporter == nil)
                    .opacity(exporter == nil ? 0.35 : 1)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
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

    // MARK: Bottom controls

    private var bottomControls: some View {
        VStack(spacing: Theme.Space.m) {
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

            ToolBar(
                actions: [
                    ToolBarAction(id: "styles", title: "Styles", systemImage: "wand.and.stars", tinted: true) {
                        withAnimation(Theme.Motion.settle) { showStyles = true }
                    },
                    ToolBarAction(id: "crop", title: "Crop & Rotate", systemImage: "crop.rotate") {
                        model.isCropping = true
                    }
                ],
                selected: model.selectedTool
            ) { tool in
                withAnimation(Theme.Motion.snappy) { model.selectedTool = tool }
            }

            if showsChrome { actionRow }
        }
        .padding(.vertical, Theme.Space.l)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var stylePanel: some View {
        VStack(spacing: Theme.Space.m) {
            HStack {
                Text("Styles")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                GlassIconButton("xmark") {
                    withAnimation(Theme.Motion.settle) { showStyles = false }
                }
            }
            .padding(.horizontal, Theme.Space.l)

            StyleStrip(source: model.source, styles: styleProvider.styles) { style in
                model.applyRecipe(style.recipe)
                withAnimation(Theme.Motion.settle) { showStyles = false }
            }
        }
        .padding(.vertical, Theme.Space.l)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
    }

    private var readout: some View {
        VStack(spacing: 2) {
            Text(model.selectedTool.readout(in: model.state))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
            Text(model.selectedTool.title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .animation(Theme.Motion.snappy, value: model.value(of: model.selectedTool))
    }

    private var actionRow: some View {
        HStack {
            GlassIconButton("xmark") { onCancel() }
            Spacer()
            Button { onDone(model.state) } label: {
                Text("Done")
                    .font(.system(.headline, design: .rounded))
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .foregroundStyle(.black)
            Spacer()
            GlassIconButton("trash") { model.reset() }
                .disabled(!model.hasEdits)
                .opacity(model.hasEdits ? 1 : 0.35)
        }
        .padding(.horizontal, Theme.Space.l)
    }

    private var dialBinding: Binding<Double> {
        Binding(
            get: { model.value(of: model.selectedTool) },
            set: { model.update(model.selectedTool, to: $0) }
        )
    }
}
