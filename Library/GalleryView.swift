import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import CoreImage
import PostKit

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
    @State private var infoSheet: InfoSheet?
    @State private var floatIcon = false
    @AppStorage("removeLocationOnExport") private var removeLocation = false
    @AppStorage("hasPrimedPhotoAccess") private var hasPrimedPhotoAccess = false
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
        // Out-of-process picker: no photo-library permission needed, supports one or many, and is
        // the most private option — Post only ever sees the photos you pick. (Using `.shared()`
        // here forced the in-process picker, which needed authorization and could present black.)
        .photosPicker(isPresented: $showPicker, selection: $pickerItems, matching: .images)
        .sheet(isPresented: $showBrowser) {
            LibraryBrowserView { datas in createProjects(from: datas) }
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
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importItems(items)
        }
        .task {
            // First launch: offer full library access once. Skipping is fine — the picker works
            // without it, and it can be turned on later in Settings.
            if !hasPrimedPhotoAccess {
                if PhotoLibrary.status == .notDetermined { showPrimer = true }
                else { hasPrimedPhotoAccess = true }
            }
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

    // MARK: Header & title

    private var header: some View {
        HStack {
            GlassIconButton("gearshape") { showSettings = true }
            Spacer()
            GlassIconButton("plus", prominent: true) { importTapped() }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    private var titleBar: some View {
        HStack {
            Text("Post")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.m)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                ForEach(projects) { project in
                    Button { open(project) } label: { ProjectCard(project: project) }
                        .buttonStyle(.plain)
                        // Source for the native zoom transition into the editor and back.
                        .matchedTransitionSource(id: project.id, in: zoomNS)
                        .contextMenu {
                            Button("Info", systemImage: "info.circle") { showInfo(for: project) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                ProjectStore.delete(project, in: modelContext)
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
                        .symbolEffect(.breathe)
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
            var datas: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
            }
            createProjects(from: datas)
        }
    }

    /// Turn imported image data (from the picker or the in-app browser) into projects. Opens the
    /// editor when exactly one photo came in; bulk imports just populate the grid.
    private func createProjects(from datas: [Data]) {
        var created: [(EditorModel, Project)] = []
        for data in datas {
            guard let loaded = ImageLoader.makeLoaded(from: data) else { continue }
            let model = EditorModel(source: loaded.preview, originalData: data, previewScale: loaded.previewScale)
            if let project = ProjectStore.create(
                originalData: data, state: model.state, thumbnail: model.thumbnailData(), in: modelContext
            ) {
                created.append((model, project))
            }
        }
        if created.count == 1, let (model, project) = created.first {
            session = EditorSession(model: model, project: project)
        }
    }

    private func open(_ project: Project) {
        guard let data = Storage.readOriginal(fileName: project.originalFileName),
              let loaded = ImageLoader.makeLoaded(from: data) else { return }
        let model = EditorModel(source: loaded.preview, originalData: data, previewScale: loaded.previewScale)
        model.load(recipe: ProjectStore.recipe(for: project))
        session = EditorSession(model: model, project: project)
    }

    private func showInfo(for project: Project) {
        guard let data = Storage.readOriginal(fileName: project.originalFileName) else { return }
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
            guard let output = try? await exporter.export(
                imageData: data, state: state, format: .heic, stripLocation: removeLocation
            ) else { return nil }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Post-\(UUID().uuidString).heic")
            do { try output.write(to: url); return url } catch { return nil }
        }
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
