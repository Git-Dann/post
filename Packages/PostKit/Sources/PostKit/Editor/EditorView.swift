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
    /// Save-a-look name prompt.
    @State private var showSaveLook = false
    @State private var newLookName = ""
    @State private var shareItem: ShareItem?
    @State private var isExporting = false
    @State private var isComparing = false
    // Press-and-hold "peek" at the original (distinct from the sticky compare toggle).
    @State private var comparePeek = false
    @State private var comparePeekTask: Task<Void, Never>?
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
    // Category-first tool strip: nil = the category overview; a group = that category's tools.
    @State private var openCategory: EditTool.Group?
    // Landscape (corner-dial) layout: which bank of up to four adjustments the corners are showing.
    @State private var bankIndex = 0
    // The bank name pill, flashed on a category swipe (and once on arrival, as the swipe's affordance).
    @State private var bankPillVisible = false
    @State private var bankPillTask: Task<Void, Never>?
    // Chrome dims itself out of the way a few seconds after you stop touching anything.
    @State private var chromeAwake = true
    @State private var idleTask: Task<Void, Never>?
    // The corner dial currently under a finger (hides the action cluster while you work).
    @State private var scrubbingTool: EditTool?
    // Selective-scope reveal: a brief dim of the un-edited region when a region is chosen.
    @State private var scopeRevealActive = false
    @State private var scopeMaskImage: CGImage?
    @State private var scopeRevealTask: Task<Void, Never>?
    @State private var celebrate = false
    @State private var donePressed = false
    @State private var isCommitting = false
    @State private var exportFailed = false
    @Namespace private var infoGlass
    @AppStorage("soundEffectsEnabled") private var soundEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.verticalSizeClass) private var vSize

    /// Corner-dial layout when the viewport is short & wide (iPhone landscape). iPad and portrait stay
    /// on the stacked layout (.regular height); extensions (no chrome) stay stacked too.
    private var isLandscape: Bool { showsChrome && vSize == .compact }

    /// The landscape editing layout: photo centred on the whole screen, four adjustments wrapped into
    /// the corners, categories swiped. Cropping keeps its own side-rail arrangement.
    private var isCornerLayout: Bool { isLandscape && !model.isCropping }

    /// The screen's corner radius, so the corner rulers can be concentric with it. There's no public
    /// API for it; the landscape side insets are the tell — a device with a sensor housing has deeply
    /// rounded glass, a flat-edged one barely any.
    private func displayCornerRadius(insets: EdgeInsets) -> CGFloat {
        insets.leading > 20 ? 55 : 14
    }

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
        .alert("Save Look", isPresented: $showSaveLook) {
            TextField("Name", text: $newLookName)
            Button("Save") { saveCurrentLook() }
            Button("Cancel", role: .cancel) { newLookName = "" }
        } message: {
            Text("Save the current adjustments as a reusable look in “Yours.”")
        }
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

    @ViewBuilder
    private var landscapeLayout: some View {
        if model.isCropping { cropLandscapeLayout } else { cornerLayout }
    }

    /// Landscape editing: the photo owns the whole screen (a landscape shot fills it edge to edge),
    /// and the controls wrap around it — four rulers following the outline of the screen, the action
    /// cluster on the left, categories swiped on the centre-right, Done and the modes along the bottom
    /// centre. Everything dims to a whisper a few seconds after your last touch (see `wakeChrome`).
    ///
    /// The layout is laid out in *display* coordinates, not safe-area ones: the rulers have to hug the
    /// glass to read as part of it. Every actual control is then inset by the safe area itself, so
    /// nothing tappable hides behind the sensor housing or the home indicator.
    private var cornerLayout: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let radius = displayCornerRadius(insets: insets)
            ZStack {
                framedImage
                    .aspectRatio(model.aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // The styles panel takes the bottom centre and the corners stand down while it's up.
                if !showStyles {
                    cornerDials(displayRadius: radius)
                    bankIndicator(insets: insets)
                }

                actionCluster(insets: insets)
                topChips(insets: insets)
                bottomCentre(insets: insets)
            }
            // Attached to the container (not an overlay) so it never steals a touch from the dials,
            // the buttons or the photo's own pinch-to-inspect — they all run alongside it.
            .simultaneousGesture(categorySwipe(in: geo.size, insets: insets, displayRadius: radius))
            .simultaneousGesture(TapGesture().onEnded { wakeChrome() })
        }
        .ignoresSafeArea()
        .onAppear {
            // Land on whatever was being edited in portrait, then flash the bank name once so the
            // swipe has an affordance the first time you turn the phone.
            if let tool = model.selectedTool, let index = DialBank.index(containing: tool) {
                bankIndex = index
            }
            flashBankPill()
            wakeChrome()
        }
        .onDisappear {
            idleTask?.cancel()
            bankPillTask?.cancel()
            chromeAwake = true
        }
    }

    /// Cropping in landscape keeps the side rails: it's a modal detour with its own chrome (handles,
    /// rotate/flip, straighten) and no adjustment dials to seat in the corners.
    private var cropLandscapeLayout: some View {
        HStack(spacing: Theme.Space.m) {
            actionRail
                .frame(width: 56)

            framedImage
                .aspectRatio(model.cropPreviewAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The "blank space" centre column — reserved a usable min width so a wide photo can't
            // squeeze the dial; a tall photo just leaves a wider gap (column grows toward maxWidth).
            VStack(spacing: Theme.Space.s) {
                Spacer(minLength: 0)
                dialSlot(scrim: false)
                cropActionBar
                Spacer(minLength: 0)
            }
            .frame(minWidth: 240, maxWidth: 320)

            VStack(spacing: Theme.Space.l) { cropButtons }
                .frame(width: 84)
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.s)
    }

    // MARK: Corner dials (landscape)

    private var bank: DialBank { DialBank.all[min(bankIndex, DialBank.all.count - 1)] }

    /// The active bank's tools, one per corner in reading order. Only the value needle moves when the
    /// bank changes — the rulers stay put, so a swipe reads as re-labelling the corners rather than a
    /// wholesale swap.
    private func cornerDials(displayRadius: CGFloat) -> some View {
        ZStack {
            ForEach(Array(bank.tools.enumerated()), id: \.element) { index, tool in
                let corner = DialBank.corners[index]
                CornerDial(
                    value: cornerBinding(tool),
                    range: tool.range,
                    detent: tool.detent,
                    corner: corner,
                    systemImage: tool.systemImage,
                    label: tool.title,
                    readout: tool.readout(in: model.state),
                    contour: DialContour(corner: corner, displayCornerRadius: displayRadius),
                    tint: tool.dialTint,
                    soundEnabled: soundEnabled,
                    onBegin: { beginCornerScrub(tool) },
                    onCommit: { endCornerScrub() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            }
        }
        .opacity(chromeAwake ? 1 : 0.25)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: chromeAwake)
    }

    private func cornerBinding(_ tool: EditTool) -> Binding<Double> {
        Binding(get: { model.value(of: tool) }, set: { model.update(tool, to: $0) })
    }

    /// Reaching for a corner dial behaves like reaching for a tool chip in portrait: it drops compare,
    /// bakes any applied look into the manual recipe, and becomes the selected tool (so rotating back
    /// to portrait lands on it).
    private func beginCornerScrub(_ tool: EditTool) {
        isComparing = false
        if model.hasActiveStyle { model.bakeStyle() }
        model.selectedTool = tool
        scrubbingTool = tool
        model.beginInteraction()
        wakeChrome()
    }

    private func endCornerScrub() {
        model.endInteraction()
        scrubbingTool = nil
        wakeChrome()
    }

    // MARK: Category swipe (landscape)

    /// Swipe up/down on the centre-right of the screen to move between banks. Only fires for a
    /// deliberate, mostly-vertical drag that starts in the clear stretch of trailing edge between the
    /// two right-hand dials, and never while the photo is zoomed (that gesture is panning) or the
    /// styles panel is up.
    private func categorySwipe(in size: CGSize, insets: EdgeInsets, displayRadius: CGFloat) -> some Gesture {
        let keepOut = DialContour(corner: .topLeading, displayCornerRadius: displayRadius).size.height + 16
        return DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard zoomScale <= 1, !showStyles, !model.isCropping else { return }
                guard inCategorySwipeZone(value.startLocation, size: size,
                                          insets: insets, keepOut: keepOut) else { return }
                let dy = value.translation.height, dx = value.translation.width
                guard abs(dy) > 44, abs(dy) > abs(dx) * 1.4 else { return }
                stepBank(by: dy < 0 ? 1 : -1)   // swipe up → the next category, like scrolling a list
            }
    }

    /// The live zone: right of centre and clear of the two trailing-edge dials. Each dial owns a known
    /// box in its corner, so the keep-out is simply the band between them — a scrub can never double as
    /// a category change. It also stops at the safe edge, since a thumb landing on the sensor housing
    /// registers nothing at all.
    private func inCategorySwipeZone(_ point: CGPoint, size: CGSize,
                                     insets: EdgeInsets, keepOut: CGFloat) -> Bool {
        guard point.x > size.width * 0.55, point.x < size.width - insets.trailing else { return false }
        return point.y > keepOut && point.y < size.height - keepOut
    }

    private func stepBank(by delta: Int) {
        let banks = DialBank.all
        guard banks.count > 1 else { return }
        let next = (bankIndex + delta + banks.count) % banks.count
        guard next != bankIndex else { return }
        withAnimation(reduceMotion ? nil : Theme.Motion.snappy) { bankIndex = next }
        Haptics.selection()
        announce(bank.displayTitle)
        flashBankPill()
        wakeChrome()
    }

    private func flashBankPill() {
        bankPillTask?.cancel()
        withAnimation(reduceMotion ? nil : Theme.Motion.snappy) { bankPillVisible = true }
        bankPillTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { bankPillVisible = false }
        }
    }

    /// Where you are in the swipe cycle — one mark per bank up the right edge, the active one drawn
    /// as an accent bar. Doubles as the hint that the right side is swipeable.
    private func bankIndicator(insets: EdgeInsets) -> some View {
        HStack(spacing: Theme.Space.s) {
            if bankPillVisible {
                GlassPill(bank.displayTitle)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            VStack(spacing: 7) {
                ForEach(DialBank.all) { entry in
                    let active = entry.id == bank.id
                    Capsule()
                        .fill(active ? Theme.accent : .white.opacity(0.35))
                        .frame(width: active ? 4 : 3, height: active ? 18 : 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, insets.trailing + Theme.Space.xs)
        .opacity(chromeAwake ? 1 : 0.25)
        .animation(reduceMotion ? nil : Theme.Motion.snappy, value: bankIndex)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: chromeAwake)
        .allowsHitTesting(false)
        // Decorative to the eye, but it's also how VoiceOver moves between categories — the swipe
        // itself isn't something a screen-reader user can perform.
        .accessibilityElement()
        .accessibilityLabel("Adjustment category")
        .accessibilityValue(bank.displayTitle)
        .accessibilityHint("Swipe up or down on the right of the screen to change category")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: stepBank(by: 1)
            case .decrement: stepBank(by: -1)
            default: break
            }
        }
    }

    // MARK: Idle chrome

    /// Any touch brings the chrome back to full strength and restarts the countdown; three seconds
    /// later the dials fade to a whisper and the action cluster steps out of the photo's way.
    private func wakeChrome() {
        idleTask?.cancel()
        if !chromeAwake {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { chromeAwake = true }
        }
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            guard scrubbingTool == nil else { wakeChrome(); return }   // still working — hold off
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) { chromeAwake = false }
        }
    }

    // MARK: Framed image (with the controls living inside it)

    /// The image shown in the single persistent Metal view: the uncropped frame while cropping,
    /// the original while comparing, otherwise the live edit.
    private var baseImage: CIImage {
        if model.isCropping { return model.cropDisplayImage }
        return showingOriginal ? model.source : model.displayImage
    }

    /// Show the untouched original — either the sticky compare toggle or a press-and-hold peek.
    private var showingOriginal: Bool { isComparing || comparePeek }

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
            // Selective reveal: when a region is chosen, briefly dim everything *outside* it so it's
            // obvious what the edit affects. Same ZStack as the image, so it aligns to the pixels.
            if scopeRevealActive, let scopeMaskImage, !model.isCropping {
                IridescentGlow()
                    .mask(alignment: .center) { scopeSelectedMask(scopeMaskImage) }
                    .blendMode(.plusLighter)
                    .opacity(0.9)
                    .allowsHitTesting(false)
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
        // Subject segmentation finishes async; if it found nothing, tell VoiceOver (the chip shows
        // it visually) so a scoped edit's silent fall-back to whole-photo isn't a mystery.
        .onChange(of: model.maskUnavailable) { _, unavailable in
            if unavailable, model.scope.isRegional { announce("No subject detected. Adjusting the whole photo.") }
        }
        // When the mask arrives after a region was already chosen, flash the selection then.
        .onChange(of: model.subjectMaskReady) { _, ready in
            if ready, model.scope.isRegional { revealScope() }
        }
        // Compare-to-original is now an explicit top-left control (tap to toggle, hold to peek) —
        // see `compareButton`. The image itself no longer steals taps, so it never clashes.
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
        // Top-left: compare-to-original (replaces the parked (i) — the gallery's long-press Info
        // covers metadata). A constant control: tap toggles original on/off, press-and-hold peeks;
        // disabled (dimmed, inert) until there's an edit to compare against. In the corner layout the
        // image's corners belong to the dials, so compare and scope move to the top-centre cluster.
        .overlay(alignment: .topLeading) {
            if !model.isCropping && !isCornerLayout { compareButton }
        }
        // Aspect-ratio menu — top-right while cropping; the scope chip takes the same corner while a
        // tonal tool is active (the two modes never overlap).
        .overlay(alignment: .topTrailing) { if model.isCropping { aspectMenu } }
        .overlay(alignment: .topTrailing) { if showsScopeChip && !isCornerLayout { scopeChip } }
        .overlay(alignment: .top) {
            if showingOriginal {
                GlassPill("Original")
                    // Clears the top-centre chip cluster in the corner layout.
                    .padding(.top, isCornerLayout ? 64 : Theme.Space.m)
                    .transition(.opacity.combined(with: .scale))
                    .allowsHitTesting(false)
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

    /// Compare-to-original, inset in the image's top-left corner (portrait / crop).
    private var compareButton: some View {
        compareControl.padding(Theme.Space.m)
    }

    /// Compare-to-original control. A quick tap toggles the original on/off (sticky); a press-and-hold
    /// peeks at the original and returns on release. One gesture distinguishes the two by press
    /// duration, so they never fight.
    private var compareControl: some View {
        let active = showingOriginal
        let enabled = model.hasEdits
        return Color.clear
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: active ? "eye.fill" : "eye")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(!enabled ? .white.opacity(0.35) : (active ? Theme.accent : .white))
                    .symbolEffect(.bounce, value: showingOriginal)   // subtle confirm on toggle
            )
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            .opacity(enabled ? 1 : 0.55)
            .allowsHitTesting(enabled)
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 40, perform: {}) { pressing in
                if pressing {
                    comparePeekTask?.cancel()
                    comparePeekTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(180))   // past this = a hold, not a tap
                        guard !Task.isCancelled else { return }
                        withAnimation(reduceMotion ? nil : Theme.Motion.snappy) { comparePeek = true }
                    }
                } else {
                    comparePeekTask?.cancel()
                    if comparePeek {
                        withAnimation(reduceMotion ? nil : Theme.Motion.snappy) { comparePeek = false }
                    } else {
                        withAnimation(reduceMotion ? nil : Theme.Motion.snappy) { isComparing.toggle() }
                        Haptics.impact(.soft)
                    }
                }
            }
            .accessibilityLabel(isComparing ? "Show edited" : "Show original")
            .accessibilityHint("Tap to toggle, or touch and hold to peek at the original")
    }

    /// Aspect-ratio picker shown top-right while cropping (mirrors the scope chip top-right).
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

    /// Capture the current look (tone/colour/film only — geometry isn't part of a reusable look).
    private func saveCurrentLook() {
        var recipe = model.state
        recipe.crop = .full
        recipe.straightenAngle = 0
        recipe.rotationQuarterTurns = 0
        recipe.flippedHorizontally = false
        recipe.flippedVertically = false
        styleProvider.saveUserStyle(name: newLookName, recipe: recipe)
        newLookName = ""
        Haptics.notify(.success)
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
                               userStyles: styleProvider.userStyles,
                               activeStyleID: model.activeStyle?.id,
                               onSaveCurrent: model.hasEdits ? { showSaveLook = true } : nil,
                               onDelete: { styleProvider.removeUserStyle(id: $0.id) }) { style in
                        // Instant (no animated swap): cross-fading the dial-slot content renders the
                        // outgoing and incoming dial at once, which shows as a brief "double".
                        if style.id == Style.original.id {
                            model.revertToOriginal()
                            announce("Original restored")
                        } else {
                            model.applyStyle(style)
                            announce("\(style.name) applied")
                        }
                        browsingStyles = false
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
                    tint: tool.dialTint,
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
                model.dismissStyle()
                Haptics.impact(.rigid)
            }
            .transition(.scale.combined(with: .opacity))
        } else if showStyles {
            // List mode → the X closes styles (back to the tools), keeping any applied look.
            GlassIconButton("xmark", label: "Close styles") {
                showStyles = false; browsingStyles = false
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

    private func galleryButton(size: CGFloat = 48) -> some View {
        GlassIconButton("square.grid.2x2", label: "Gallery", size: size) { onCancel() }
    }
    private func undoButton(size: CGFloat = 48) -> some View {
        GlassIconButton("arrow.uturn.backward", label: "Undo", size: size) { model.undo() }
            .disabled(!model.canUndo)
            .opacity(model.canUndo ? 1 : 0.35)
    }
    private func redoButton(size: CGFloat = 48) -> some View {
        GlassIconButton("arrow.uturn.forward", label: "Redo", size: size) { model.redo() }
            .disabled(!model.canRedo)
            .opacity(model.canRedo ? 1 : 0.35)
    }
    /// Sits between Undo and Redo: revert every change back to the original (one step, undoable).
    /// Uses the "reset adjustments" glyph (sliders + reset loop) rather than another u-turn arrow.
    private func revertButton(size: CGFloat = 48) -> some View {
        GlassIconButton("slider.horizontal.2.arrow.trianglehead.counterclockwise",
                        label: "Revert all changes", size: size) {
            guard model.hasEdits else { return }
            model.reset()   // instant — animating the dial-slot mode change would double the dial
            Haptics.impact(.rigid)
        }
        .disabled(!model.hasEdits)
        .opacity(model.hasEdits ? 1 : 0.35)
    }
    private func shareButton(size: CGFloat = 48) -> some View {
        GlassIconButton(isExporting ? "ellipsis" : "square.and.arrow.up", label: "Share", size: size) { share() }
            .disabled(isExporting || exporter == nil)
            .opacity(exporter == nil ? 0.35 : (isExporting ? 0.5 : 1))   // dim while working
    }

    /// Portrait: Gallery | Undo · Revert · Redo | Share across the top.
    /// Grouped in a GlassEffectContainer so the system batches the glass (Apple's recommended pattern
    /// for multiple glass effects).
    private var topBar: some View {
        GlassEffectContainer {
            HStack {
                galleryButton()
                Spacer()
                HStack(spacing: Theme.Space.s) { undoButton(); revertButton(); redoButton() }
                Spacer()
                shareButton()
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    /// Landscape (corner layout): the same buttons as a compact two-row cluster on the left, sized to
    /// drop into the gap between the two left-hand tick fans. It fades right out while you scrub a
    /// dial or once the chrome goes idle — a tap anywhere brings it back.
    private func actionCluster(insets: EdgeInsets) -> some View {
        let visible = chromeAwake && scrubbingTool == nil
        // 44pt buttons: two rows of them clear the side runs of the dials above and below.
        return GlassEffectContainer {
            VStack(spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    undoButton(size: 44)
                    revertButton(size: 44)
                    redoButton(size: 44)
                }
                HStack(spacing: Theme.Space.s) {
                    galleryButton(size: 44)
                    shareButton(size: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, insets.leading + Theme.Space.s)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: visible)
    }

    /// Landscape: compare and the scope chip sit together at the top centre, between the upper dials.
    private func topChips(insets: EdgeInsets) -> some View {
        GlassEffectContainer {
            HStack(spacing: Theme.Space.s) {
                if !model.isCropping { compareControl }
                if showsScopeChip { scopeControl }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, insets.top + Theme.Space.s)
        .opacity(chromeAwake ? 1 : 0.25)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: chromeAwake)
    }

    /// Landscape: the modes that aren't dials (Auto · Crop · Styles) with Done, along the bottom
    /// centre. The styles panel, when open, sits directly above this row in place of the corner dials.
    private func bottomCentre(insets: EdgeInsets) -> some View {
        VStack(spacing: Theme.Space.s) {
            if showStyles {
                dialSlot(scrim: false)
                    .frame(maxWidth: 520)
            }
            HStack(spacing: Theme.Space.s) {
                GlassIconButton("sparkles", label: "Auto", size: 44) { handleToolSelect(.auto) }
                GlassIconButton("crop.rotate", label: "Crop & Rotate", size: 44) {
                    isComparing = false
                    withAnimation(cropMotion) { model.beginCrop() }
                }
                GlassIconButton("wand.and.stars", label: "Styles", size: 44) {
                    isComparing = false
                    browsingStyles = true
                    showStyles = true
                }
                compactDoneButton
                // Only the styles branches of the X are meaningful here (remove the look / close the
                // list) — a corner dial resets with a double-tap on its glyph, and Revert-all lives in
                // the action cluster.
                if showStyles { resetButton }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, insets.bottom + Theme.Space.xs)
        .opacity(chromeAwake ? 1 : 0.25)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: chromeAwake)
    }

    /// Done, sized to its label (the portrait bar stretches; here it shares a row).
    private var compactDoneButton: some View {
        Button { commitDone() } label: {
            Text("Done")
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, 12)
        }
        .buttonStyle(.glass)
        .tint(donePressed ? Theme.accent : .white)
    }

    /// Landscape: the same buttons as a left rail — Gallery top, Undo · Revert · Redo centred,
    /// Share bottom. (Used by the crop detour, which keeps the side rails.)
    private var actionRail: some View {
        GlassEffectContainer {
            VStack(spacing: Theme.Space.m) {
                galleryButton()
                Spacer(minLength: 0)
                undoButton()
                revertButton()
                redoButton()
                Spacer(minLength: 0)
                shareButton()
            }
        }
        .padding(.vertical, Theme.Space.s)
    }

    // MARK: Tool strip (underneath the image)

    /// Category-first tool strip. Level 1 shows category chips (Auto · Light · Colour · Effects ·
    /// Crop · Styles); tapping a category reveals its tools (level 2, with a Back chip). One ToolBar
    /// instance whose actions/tools swap by `openCategory`, so the chips animate in/out.
    private func toolStrip(axis: Axis) -> some View {
        let level2 = openCategory != nil
        return ToolBar(
            actions: level2 ? [backAction] : categoryActions,
            selected: model.selectedTool,
            tools: openCategory?.tools ?? [],
            editedTools: editedTools,
            highlightSelection: level2,   // tool highlight only inside a category
            axis: axis,
            onSelect: handleToolSelect
        )
    }

    private var backAction: ToolBarAction {
        ToolBarAction(id: "back", title: "Back", systemImage: "chevron.backward") {
            withAnimation(reduceMotion ? nil : Theme.Motion.snappy) {
                openCategory = nil
                model.selectedTool = nil   // backing out hides the dial for a clean overview
            }
        }
    }

    private var categoryActions: [ToolBarAction] {
        let edited = editedTools
        func groupHasEdit(_ g: EditTool.Group) -> Bool { g.tools.contains { edited.contains($0) } }
        return [
            ToolBarAction(id: "auto", title: "Auto", systemImage: EditTool.auto.systemImage) {
                handleToolSelect(.auto)   // one-tap action, no drill-in
            },
            ToolBarAction(id: "light", title: EditTool.Group.light.title,
                          systemImage: EditTool.Group.light.systemImage, showsDot: groupHasEdit(.light)) {
                drillInto(.light)
            },
            ToolBarAction(id: "colour", title: EditTool.Group.colour.title,
                          systemImage: EditTool.Group.colour.systemImage, showsDot: groupHasEdit(.colour)) {
                drillInto(.colour)
            },
            ToolBarAction(id: "effects", title: EditTool.Group.finishing.title,
                          systemImage: EditTool.Group.finishing.systemImage, showsDot: groupHasEdit(.finishing)) {
                drillInto(.finishing)
            },
            ToolBarAction(id: "crop", title: "Crop & Rotate", systemImage: "crop.rotate", showsDot: geometryEdited) {
                isComparing = false
                withAnimation(cropMotion) { model.beginCrop() }
            },
            ToolBarAction(id: "styles", title: "Styles", systemImage: "wand.and.stars", tinted: showStyles) {
                // Open the list. If a look is active, BROWSE it (keep applied, land on it).
                isComparing = false
                browsingStyles = true
                showStyles = true
            }
        ]
    }

    /// Drill into a category's tools.
    private func drillInto(_ g: EditTool.Group) {
        isComparing = false
        if model.hasActiveStyle { model.bakeStyle() }
        showStyles = false
        browsingStyles = false
        withAnimation(reduceMotion ? nil : Theme.Motion.snappy) { openCategory = g }
    }

    private func handleToolSelect(_ tool: EditTool) {
        // Auto is a one-tap ACTION, not a mode: it bakes an auto-enhance into the real tools
        // (Exposure/Contrast/Warmth/Vibrance) as one undoable edit, then it's done — nothing stays
        // "selected", so it never sits there looking active. The touched tools light up as edited
        // (which they are), and you refine or undo from there.
        if tool == .auto {
            if model.hasActiveStyle { model.bakeStyle() }
            model.applyAutoEnhance()
            Haptics.impact(.soft)
            triggerCelebrate()
            return
        }
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
            // Instant: animating the swap cross-fades the old/new ruler (different tick sets), which
            // reads as a brief "double". The chip's own selection animation still plays.
            model.selectedTool = tool
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

    /// Whether the selective-scope chip is shown — present for every adjustment tool (the scope
    /// confines the whole edit), but not over the styles strip or while cropping. In the corner layout
    /// four adjustments are always live, so it's always relevant there.
    private var showsScopeChip: Bool {
        guard showsChrome, !model.isCropping, !showStyles else { return false }
        return isCornerLayout || model.selectedTool != nil
    }

    /// The scope chip, inset in the image's top-right corner (portrait / crop).
    private var scopeChip: some View {
        scopeControl.padding(Theme.Space.m)
    }

    /// The selective-scope chip (top-right in portrait, in the top-centre cluster in landscape). Tap
    /// for a native menu of Whole Photo / Subject / Background (on-device Vision). Subtle by default;
    /// accent-ringed and labelled while a region is active, so it's obvious you're editing just part
    /// of the photo.
    private var scopeControl: some View {
        let regional = model.scope.isRegional
        let noSubject = model.maskUnavailable && regional && !model.isPreparingMask
        let tint: Color = noSubject ? .orange : (regional ? Theme.accent : .white)
        return Menu {
            // Plain text rows — no icons, no checkmark. The active scope is tinted in the accent
            // colour so only it reads as chosen.
            ForEach(SelectiveScope.allCases, id: \.self) { s in
                Button { selectScope(s) } label: {
                    Text(s.title)
                        .foregroundStyle(model.scope == s ? Theme.accent : Color.primary)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if model.isPreparingMask {
                    ProgressView().controlSize(.mini).tint(tint)
                } else {
                    Image(systemName: noSubject ? "exclamationmark.triangle.fill" : model.scope.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolEffect(.bounce, value: model.scope)   // gentle bounce when scope changes
                }
                Text(noSubject ? "No subject" : model.scope.shortTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay {   // an accent ring makes "a region is active" unmistakable
            if regional && !noSubject {
                Capsule().strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
        .overlay {   // iridescent ring while on-device detection runs — the "finding the subject" cue
            if model.isPreparingMask {
                IridescentGlow()
                    .mask(Capsule().strokeBorder(lineWidth: 2.5))
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.snappy, value: model.scope)
        .accessibilityLabel("Adjustment area")
        .accessibilityValue(model.scope.title)
        .accessibilityHint("Confines tonal edits to the subject or background")
    }

    /// Masks the iridescent glow so it lands on the region being EDITED (subject scope → over the
    /// subject; background scope → over the background). The mask image is white on the subject.
    @ViewBuilder
    private func scopeSelectedMask(_ cg: CGImage) -> some View {
        let img = Image(decorative: cg, scale: displayScale).resizable()
        switch model.scope {
        case .background: img.colorInvert().luminanceToAlpha()   // glow where mask is dark (background)
        default:          img.luminanceToAlpha()                 // glow where mask is light (subject)
        }
    }

    private func selectScope(_ scope: SelectiveScope) {
        guard model.scope != scope else { return }
        model.setScope(scope)
        Haptics.selection()
        announce(scope.announcement)
        revealScope()
    }

    /// Flash an iridescent shimmer over the selected region, then fade. No-op for whole-photo or
    /// while the mask is still computing (the async path re-triggers this once it's ready). The hold
    /// is ~1s so the shimmer's sweep reads before it goes.
    private func revealScope() {
        guard model.scope.isRegional, let cg = model.scopeMaskDisplayImage() else { return }
        scopeMaskImage = cg
        scopeRevealTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scopeRevealActive = true }
        scopeRevealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.45)) { scopeRevealActive = false }
        }
    }

    /// Speak a state change to VoiceOver (a no-op when VoiceOver is off). Used for changes that
    /// aren't reflected in a focused control — scope, applied style, finished export.
    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
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
                announce("Photo ready to share")
                shareItem = ShareItem(url: url)
            } else {
                Haptics.notify(.error)
                announce("Export failed")
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
