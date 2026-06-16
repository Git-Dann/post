import SwiftUI
import SwiftData
import PhotosUI
import Photos
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
/// artifacts) and an import flow that supports one-by-one or many photos, with an explicit
/// full-library-access option.
struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.modifiedAt, order: .reverse) private var projects: [Project]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var session: EditorSession?
    @State private var showSettings = false
    @State private var showImportOptions = false
    @State private var showPicker = false
    @State private var infoSheet: InfoSheet?
    @AppStorage("removeLocationOnExport") private var removeLocation = false

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
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $infoSheet) { sheet in MetadataView(rows: sheet.rows) }
        .photosPicker(isPresented: $showPicker, selection: $pickerItems, matching: .images, photoLibrary: .shared())
        .confirmationDialog("Add photos", isPresented: $showImportOptions, titleVisibility: .visible) {
            Button("Choose Photos") { showPicker = true }
            Button("Allow Full Library Access…") { requestFullAccessThenPick() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pick one or many. Post only ever reads photos you choose — grant full access only if you'd like to import freely.")
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importItems(items)
        }
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--seed-project"), projects.isEmpty { seedSampleProject() }
            if args.contains("--open-sample-editor") { openSample() }
            if args.contains("--open-settings") { showSettings = true }
            #endif
        }
    }

    // MARK: Header & title

    private var header: some View {
        HStack {
            GlassIconButton("gearshape") { showSettings = true }
            Spacer()
            GlassIconButton("plus", prominent: true) { showImportOptions = true }
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
                        .contextMenu {
                            Button("Info", systemImage: "info.circle") { showInfo(for: project) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                ProjectStore.delete(project, in: modelContext)
                            }
                        }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.l)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Button { showImportOptions = true } label: {
                VStack(spacing: Theme.Space.m) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.breathe)
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

    private func requestFullAccessThenPick() {
        Task {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            showPicker = true   // proceed regardless; the picker works either way
        }
    }

    private func importItems(_ items: [PhotosPickerItem]) {
        Task {
            defer { pickerItems = [] }
            var created: [(EditorModel, Project)] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let loaded = ImageLoader.makeLoaded(from: data) else { continue }
                let model = EditorModel(source: loaded.preview, originalData: data, previewScale: loaded.previewScale)
                if let project = ProjectStore.create(
                    originalData: data, state: model.state, thumbnail: model.thumbnailData(), in: modelContext
                ) {
                    created.append((model, project))
                }
            }
            // Open the editor only when a single photo was imported; bulk imports just populate the grid.
            if created.count == 1, let (model, project) = created.first {
                session = EditorSession(model: model, project: project)
            }
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
    }
}

#Preview {
    GalleryView()
        .modelContainer(for: Project.self, inMemory: true)
        .preferredColorScheme(.dark)
}
