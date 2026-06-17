import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import CoreImage
import UniformTypeIdentifiers
import PostKit

/// Loads a picked photo while preserving its filename, so exports can read "Edited <name>".
/// Falls back to a plain data load (no name) when the picker won't vend a file representation.
private struct PickedPhoto: Transferable {
    let data: Data
    let name: String?
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let name = received.file.lastPathComponent
            let data = try Data(contentsOf: received.file)
            return PickedPhoto(data: data, name: name)
        }
    }
}

/// A re-editable session: the live editor model plus the project it persists to (nil for the
/// dev sample, which isn't saved).
private struct EditorSession: Identifiable {
    let id = UUID()
    let model: EditorModel
    let project: Project?
}

/// Per-project info sheet payload.
private struct InfoSheet: Identifiable {
    let id = UUID()
    let rows: [ImageLoader.MetaRow]
}

/// The home surface: a grid of re-editable projects with a clean floating glass header (no nav-bar
/// artifacts) and a privacy-first import flow — the system photo picker (out-of-process, no
/// library permission required) that imports one or many photos.
struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.modifiedAt, order: .reverse) private var projects: [Project]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var session: EditorSession?
    @State private var showSettings = false
    @State private var showPicker = false
    @State private var showBrowser = false
    @State private var showPrimer = false
    @State private var showTour = false
    @State private var infoSheet: InfoSheet?
    @State private var floatIcon = false
    @State private var loadError = false
    @State private var saveFailed = false
    /// Edits copied from one project, ready to paste onto another.
    @State private var copiedRecipe: EditState?
    /// Multi-select mode + the chosen project IDs, for bulk actions.
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var batchShareURLs: [URL] = []
    @State private var showBatchShare = false
    @AppStorage(ExportPrefs.removeLocationKey, store: .postShared) private var removeLocation = true
    @AppStorage("hasPrimedPhotoAccess") private var hasPrimedPhotoAccess = false
    @AppStorage("hasSeenTour") private var hasSeenTour = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoomNS

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: Theme.Space.m)]

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                titleBar
                if projects.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
        }
        // Bulk-action bar floats over the grid while selecting.
        .overlay(alignment: .bottom) {
            if selecting && !selection.isEmpty { selectionBar }
        }
        .sheet(isPresented: $showBatchShare) { ActivityView(items: batchShareURLs) }
        .fullScreenCover(item: $session) { session in
            EditorView(
                model: session.model,
                exporter: makeExporter(for: session.model),
                onDone: { state in finish(session, state: state) },
                onCancel: { self.session = nil }
            )
            // Native zoom: the editor grows out of the tapped photo and pushes back to its slot.
            .navigationTransition(.zoom(sourceID: session.project?.id ?? session.id, in: zoomNS))
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $infoSheet) { sheet in MetadataView(rows: sheet.rows) }
        .alert("Couldn't open photo", isPresented: $loadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This photo couldn't be loaded — it may have been removed or isn't downloaded from iCloud yet.")
        }
        .alert("Couldn't save to Photos", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Post needs permission to add photos. You can turn it on in Settings › Photos.")
        }
        // Out-of-process picker: no photo-library permission needed, supports one or many, and is
        // the most private option — Post only ever sees the photos you pick. (Using `.shared()`
        // here forced the in-process picker, which needed authorization and could present black.)
        .photosPicker(isPresented: $showPicker, selection: $pickerItems, matching: .images)
        .sheet(isPresented: $showBrowser) {
            LibraryBrowserView { datas in createProjects(from: datas.map { ($0, nil) }) }
        }
        .sheet(isPresented: $showPrimer, onDismiss: {
            // If they just granted access, take them straight into their library to pick photos —
            // otherwise granting appears to "do nothing".
            if PhotoLibrary.hasAccess { showBrowser = true }
        }) {
            PhotoAccessPrimer(
                onAllow: { Task { await PhotoLibrary.requestAccess(); finishPriming() } },
                onSkip: { finishPriming() }
            )
        }
        .sheet(isPresented: $showTour, onDismiss: {
            hasSeenTour = true
            primePhotoAccessIfNeeded()   // run the photo primer after the welcome, not on top of it
        }) {
            WelcomeTour { showTour = false }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importItems(items)
        }
        .task {
            // First launch: show the welcome tour once, then the photo primer on dismiss. Returning
            // users skip straight to the primer check.
            if !hasSeenTour { showTour = true } else { primePhotoAccessIfNeeded() }
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--seed-project"), projects.isEmpty { seedSampleProject() }
            if args.contains("--open-sample-editor") { openSample() }
            if args.contains("--open-settings") { showSettings = true }
            if args.contains("--open-browser") { showPrimer = false; showBrowser = true }
            #endif
        }
    }

    /// Tapping "+" or the empty-state: browse the library in-app when access is granted, otherwise
    /// fall back to the permission-free system picker.
    private func importTapped() {
        if PhotoLibrary.hasAccess { showBrowser = true } else { showPicker = true }
    }

    private func finishPriming() {
        hasPrimedPhotoAccess = true
        showPrimer = false
    }

    /// Offer full library access once. Skipping is fine — the picker works without it, and it can be
    /// enabled later in Settings.
    private func primePhotoAccessIfNeeded() {
        guard !hasPrimedPhotoAccess else { return }
        if PhotoLibrary.status == .notDetermined { showPrimer = true }
        else { hasPrimedPhotoAccess = true }
    }

    // MARK: Header & title

    private var header: some View {
        HStack {
            if selecting {
                Button("Done") { withAnimation(Theme.Motion.snappy) { exitSelection() } }
                    .font(.headline)
                    .tint(Theme.accent)
                Spacer()
                Button(selection.count == projects.count ? "Deselect All" : "Select All") {
                    toggleSelectAll()
                }
                .font(.subheadline)
                .tint(Theme.accent)
            } else {
                GlassIconButton("gearshape", label: "Settings") { showSettings = true }
                Spacer()
                if !projects.isEmpty {
                    GlassIconButton("checklist", label: "Select") {
                        withAnimation(Theme.Motion.snappy) { selecting = true }
                    }
                }
                GlassIconButton("plus", label: "Add photo", prominent: true) { importTapped() }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    private var titleBar: some View {
        HStack {
            Text(selecting ? "\(selection.count) Selected" : "Post")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.m)
    }

    private var grid: some View {
        // Capture the main-actor value into a local so the (Sendable) scrollTransition closure
        // doesn't reference the actor-isolated environment property directly.
        let reduceMotion = reduceMotion
        return ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                ForEach(projects) { project in
                    Button {
                        if selecting { toggleSelection(project) } else { open(project) }
                    } label: {
                        ProjectCard(project: project)
                            .overlay(alignment: .topLeading) {
                                if selecting { selectionBadge(on: selection.contains(project.id)) }
                            }
                            .opacity(selecting && !selection.contains(project.id) ? 0.6 : 1)
                    }
                        .buttonStyle(.plain)
                        // Source for the native zoom transition into the editor and back.
                        .matchedTransitionSource(id: project.id, in: zoomNS)
                        .contextMenu {
                            // No per-item menu while multi-selecting (the tap is a toggle).
                            if !selecting {
                                Button("Info", systemImage: "info.circle") { showInfo(for: project) }
                                if project.isEdited {
                                    Button("Copy Edits", systemImage: "doc.on.doc") {
                                        copiedRecipe = ProjectStore.recipe(for: project)
                                        Haptics.impact(.light)
                                    }
                                }
                                if copiedRecipe != nil {
                                    Button("Paste Edits", systemImage: "doc.on.clipboard") {
                                        pasteEdits(to: project)
                                    }
                                }
                                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                                    saveToPhotos(project)
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    ProjectStore.delete(project, in: modelContext)
                                }
                            }
                        }
                        // Subtle: cards ease in as they scroll into view.
                        .scrollTransition { content, phase in
                            content
                                .opacity(reduceMotion || phase.isIdentity ? 1 : 0.55)
                                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.94)
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.l)
            // Springy pop when a freshly-edited photo lands in the grid.
            .animation(reduceMotion ? .default : Theme.Motion.bounce, value: projects.count)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Button { importTapped() } label: {
                VStack(spacing: Theme.Space.m) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.breathe, isActive: !reduceMotion)
                        .offset(y: floatIcon ? -7 : 7)            // gentle, subtle float
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                                floatIcon = true
                            }
                        }
                    Text("Bring a photo to life")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Tap to import a photo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Spacer()
        }
    }

    // MARK: Actions

    private func importItems(_ items: [PhotosPickerItem]) {
        Task {
            defer { pickerItems = [] }
            var imported: [(Data, String?)] = []
            for item in items {
                // Prefer a name-preserving load so exports can read "Edited <original name>"; fall
                // back to raw data (no name) if the picker won't hand us a file representation.
                if let picked = try? await item.loadTransferable(type: PickedPhoto.self) {
                    imported.append((picked.data, picked.name))
                } else if let data = try? await item.loadTransferable(type: Data.self) {
                    imported.append((data, nil))
                }
            }
            createProjects(from: imported)
        }
    }

    /// Turn imported image data (from the picker or the in-app browser) into projects. Opens the
    /// editor when exactly one photo came in; bulk imports just populate the grid.
    private func createProjects(from items: [(data: Data, name: String?)]) {
        var created: [(EditorModel, Project)] = []
        for (data, name) in items {
            guard let loaded = ImageLoader.makeLoaded(from: data) else { continue }
            let model = EditorModel(source: loaded.preview, originalData: data,
                                    originalName: name, previewScale: loaded.previewScale)
            if let project = ProjectStore.create(
                originalData: data, state: model.state, thumbnail: model.thumbnailData(),
                originalName: name, in: modelContext
            ) {
                created.append((model, project))
            }
        }
        if created.count == 1, let (model, project) = created.first {
            session = EditorSession(model: model, project: project)
        } else if created.isEmpty && !items.isEmpty {
            loadError = true   // every chosen photo failed to import
        }
    }

    private func open(_ project: Project) {
        guard let data = ProjectStore.originalData(for: project),
              let loaded = ImageLoader.makeLoaded(from: data) else {
            loadError = true   // original missing/corrupt/locked — don't fail silently
            return
        }
        let model = EditorModel(source: loaded.preview, originalData: data,
                                originalName: project.originalName, previewScale: loaded.previewScale)
        model.load(recipe: ProjectStore.recipe(for: project))
        session = EditorSession(model: model, project: project)
    }

    /// Apply the copied edits to a project, re-rendering its thumbnail to match.
    private func pasteEdits(to project: Project) {
        guard let recipe = copiedRecipe,
              let data = ProjectStore.originalData(for: project),
              let loaded = ImageLoader.makeLoaded(from: data) else { return }
        let model = EditorModel(source: loaded.preview, originalData: data, previewScale: loaded.previewScale)
        model.load(recipe: recipe)
        ProjectStore.update(project, state: recipe, thumbnail: model.thumbnailData(), in: modelContext)
        Haptics.notify(.success)
    }

    // MARK: Multi-select

    private func selectionBadge(on selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .symbolRenderingMode(.palette)
            .foregroundStyle(selected ? .black : .white, selected ? Theme.accent : .white.opacity(0.25))
            .padding(8)
    }

    private var selectionBar: some View {
        HStack(spacing: Theme.Space.xl) {
            if copiedRecipe != nil { barButton("doc.on.clipboard", "Paste") { bulkPaste() } }
            barButton("square.and.arrow.down", "Save") { bulkSave() }
            barButton("square.and.arrow.up", "Export") { shareSelected() }
            barButton("trash", "Delete", tint: .red) { bulkDelete() }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.m)
        .glassEffect(in: .capsule)
        .padding(.bottom, Theme.Space.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func barButton(_ symbol: String, _ label: String, tint: Color = .white,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                Text(label).font(.caption2.weight(.medium))
            }
            .foregroundStyle(tint)
            .frame(minWidth: 56)
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(_ project: Project) {
        if selection.contains(project.id) { selection.remove(project.id) }
        else { selection.insert(project.id) }
        Haptics.selection()
    }

    private func exitSelection() {
        selecting = false
        selection.removeAll()
    }

    private func toggleSelectAll() {
        if selection.count == projects.count { selection.removeAll() }
        else { selection = Set(projects.map(\.id)) }
    }

    private func selectedProjects() -> [Project] { projects.filter { selection.contains($0.id) } }

    private func bulkDelete() {
        for project in selectedProjects() { ProjectStore.delete(project, in: modelContext) }
        withAnimation(Theme.Motion.snappy) { exitSelection() }
    }

    private func bulkPaste() {
        for project in selectedProjects() { pasteEdits(to: project) }
        withAnimation(Theme.Motion.snappy) { exitSelection() }
    }

    /// Render a project's saved recipe to encoded data using the user's export prefs.
    private func exportData(for project: Project, using exporter: ImageExporter) async -> Data? {
        guard let data = ProjectStore.originalData(for: project) else { return nil }
        return try? await exporter.export(
            imageData: data, state: ProjectStore.recipe(for: project),
            format: ExportPrefs.format, quality: ExportPrefs.quality,
            stripLocation: ExportPrefs.removeLocation, maxDimension: ExportPrefs.maxDimension)
    }

    /// Save the selected projects' edited images straight to the Photos library.
    private func bulkSave() {
        let chosen = selectedProjects()
        Task {
            let exporter = ImageExporter()
            var saved = 0
            for project in chosen {
                if let out = await exportData(for: project, using: exporter),
                   await PhotoLibrary.save(imageData: out) { saved += 1 }
            }
            if saved > 0 { Haptics.notify(.success) } else { saveFailed = true }
            withAnimation(Theme.Motion.snappy) { exitSelection() }
        }
    }

    /// Save a single project's edited image to the Photos library (from the card's long-press menu).
    private func saveToPhotos(_ project: Project) {
        Task {
            let exporter = ImageExporter()
            if let out = await exportData(for: project, using: exporter),
               await PhotoLibrary.save(imageData: out) {
                Haptics.notify(.success)
            } else {
                saveFailed = true
            }
        }
    }

    private func shareSelected() {
        let chosen = selectedProjects()
        let format = ExportPrefs.format
        Task {
            var urls: [URL] = []
            let exporter = ImageExporter()   // one context for the whole batch, not one per photo
            for project in chosen {
                if let out = await exportData(for: project, using: exporter) {
                    let url = exportURL(originalName: project.originalName, format: format)
                    if (try? out.write(to: url)) != nil { urls.append(url) }
                }
            }
            if !urls.isEmpty { batchShareURLs = urls; showBatchShare = true }
            exitSelection()
        }
    }

    private func showInfo(for project: Project) {
        guard let data = ProjectStore.originalData(for: project) else { return }
        infoSheet = InfoSheet(rows: ImageLoader.metadata(from: data))
    }

    private func finish(_ session: EditorSession, state: EditState) {
        if let project = session.project {
            ProjectStore.update(project, state: state, thumbnail: session.model.thumbnailData(), in: modelContext)
        }
        self.session = nil
    }

    private func makeExporter(for model: EditorModel) -> (EditState) async -> URL? {
        { state in
            guard let data = model.originalData else { return nil }
            let exporter = ImageExporter()
            let format = ExportPrefs.format
            guard let output = try? await exporter.export(
                imageData: data, state: state, format: format, quality: ExportPrefs.quality,
                stripLocation: ExportPrefs.removeLocation, maxDimension: ExportPrefs.maxDimension
            ) else { return nil }
            let url = exportURL(originalName: model.originalName, format: format)
            do { try output.write(to: url); return url } catch { return nil }
        }
    }

    /// A unique temp URL carrying a human-friendly export name ("Edited <original>.<ext>"), each in
    /// its own subfolder so two exports that share a name can't collide.
    private func exportURL(originalName: String?, format: ImageExporter.Format) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(
            ImageExporter.suggestedFileName(forOriginal: originalName, format: format))
    }

    #if DEBUG
    private func openSample() {
        let model = EditorModel(source: SampleImage.make(), previewScale: 1)
        session = EditorSession(model: model, project: nil)
    }

    private func seedSampleProject() {
        let sample = SampleImage.make()
        guard let data = CIContext().jpegRepresentation(
            of: sample, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]
        ) else { return }
        for fade in [0.0, 0.4, 0.7] {
            var state = EditState()
            state.fade = fade
            state.grain = fade > 0 ? 0.4 : 0
            let model = EditorModel(source: sample, previewScale: 1)
            model.load(recipe: state)
            ProjectStore.create(originalData: data, state: state, thumbnail: model.thumbnailData(), in: modelContext)
        }
    }
    #endif
}

/// A gallery tile showing a project's saved thumbnail.
private struct ProjectCard: View {
    let project: Project

    var body: some View {
        Group {
            if let data = project.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.canvas
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        // Small glass badge marking projects that carry adjustments.
        .overlay(alignment: .topTrailing) {
            if project.isEdited {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(7)
                    .glassEffect(.regular, in: .circle)
                    .padding(8)
            }
        }
    }
}

#Preview {
    GalleryView()
        .modelContainer(for: Project.self, inMemory: true)
        .preferredColorScheme(.dark)
}
