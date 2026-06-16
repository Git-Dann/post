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

/// The home surface: a grid of re-editable projects with a PhotosPicker import. Tapping a project
/// reopens it with its saved recipe restored; finishing an edit saves the recipe and a thumbnail.
struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.modifiedAt, order: .reverse) private var projects: [Project]

    @State private var pickerItem: PhotosPickerItem?
    @State private var session: EditorSession?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: Theme.Space.m)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                if projects.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Post")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.tint(Theme.accent).interactive(), in: .circle)
                    }
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
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--seed-project"), projects.isEmpty {
                seedSampleProject()
            }
            if args.contains("--open-sample-editor") {
                openSample()
            }
            #endif
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                ForEach(projects) { project in
                    Button { open(project) } label: { ProjectCard(project: project) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                ProjectStore.delete(project, in: modelContext)
                            }
                        }
                }
            }
            .padding(Theme.Space.l)
        }
    }

    private var emptyState: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
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
            .padding(Theme.Space.xl)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func importPhoto(_ item: PhotosPickerItem) {
        Task {
            defer { pickerItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let loaded = ImageLoader.makeLoaded(from: data) else { return }
            let model = EditorModel(source: loaded.preview, originalData: data, previewScale: loaded.previewScale)
            let project = ProjectStore.create(
                originalData: data,
                state: model.state,
                thumbnail: model.thumbnailData(),
                in: modelContext
            )
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

    private func finish(_ session: EditorSession, state: EditState) {
        if let project = session.project {
            ProjectStore.update(project, state: state, thumbnail: session.model.thumbnailData(), in: modelContext)
        }
        self.session = nil
    }

    /// Full-resolution HEIC export to a temp file for the share sheet. Heavy render runs on the
    /// `ImageExporter` actor, off the main thread.
    private func makeExporter(for model: EditorModel) -> (EditState) async -> URL? {
        { state in
            guard let data = model.originalData else { return nil }
            let exporter = ImageExporter()
            guard let output = try? await exporter.export(imageData: data, state: state, format: .heic) else {
                return nil
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Post-\(UUID().uuidString).heic")
            do {
                try output.write(to: url)
                return url
            } catch {
                return nil
            }
        }
    }

    #if DEBUG
    private func openSample() {
        let model = EditorModel(source: SampleImage.make(), previewScale: 1)
        session = EditorSession(model: model, project: nil)
    }

    /// Seed a couple of saved projects (with looks applied) to exercise persistence + the grid.
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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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
