import UIKit
import SwiftUI
import Photos
import PhotosUI
import PostKit

/// Edit non-destructively *inside* Apple Photos. Reads the photo (and any previously stored Post
/// recipe), hosts the chromeless `EditorView`, and on Done writes the rendered image plus the
/// recipe back as `adjustmentData` — so the edit stays reversible in Photos.
///
/// `@preconcurrency` conformance: `PHContentEditingController` predates strict concurrency, so its
/// requirements are nonisolated. Photos calls `startContentEditing` on the main thread (so we keep
/// it main-actor) and `finishContentEditing` on a background queue (kept `nonisolated`).
final class PhotoEditingViewController: UIViewController, @preconcurrency PHContentEditingController {

    private static let formatID = "co.gitwork.post.recipe"
    private static let formatVersion = "1"

    private var input: PHContentEditingInput?
    private var model: EditorModel?

    // MARK: PHContentEditingController

    nonisolated func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        adjustmentData.formatIdentifier == Self.formatID
    }

    func startContentEditing(with contentEditingInput: PHContentEditingInput, placeholderImage: UIImage) {
        self.input = contentEditingInput
        view.backgroundColor = .black

        guard let url = contentEditingInput.fullSizeImageURL,
              let data = try? Data(contentsOf: url),
              let loaded = ImageLoader.makeLoaded(from: data) else { return }

        var recipe = EditState()
        if let adjustment = contentEditingInput.adjustmentData,
           adjustment.formatIdentifier == Self.formatID,
           let decoded = try? JSONDecoder().decode(EditState.self, from: adjustment.data) {
            recipe = decoded
        }

        let model = EditorModel(source: loaded.preview, originalData: data, previewScale: loaded.previewScale)
        model.load(recipe: recipe)
        self.model = model

        let host = UIHostingController(rootView: EditorView(model: model, showsChrome: false))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    nonisolated func finishContentEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        let box = UncheckedSendable(completionHandler)
        Task { @MainActor in
            await renderOutput(completionHandler: box.value)
        }
    }

    nonisolated func cancelContentEditing() {}

    nonisolated var shouldShowCancelConfirmation: Bool { false }

    // MARK: Render

    @MainActor
    private func renderOutput(completionHandler: @escaping (PHContentEditingOutput?) -> Void) async {
        guard let input, let model else {
            completionHandler(nil)
            return
        }
        let output = PHContentEditingOutput(contentEditingInput: input)
        let state = model.state
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: Self.formatID,
            formatVersion: Self.formatVersion,
            data: (try? JSONEncoder().encode(state)) ?? Data()
        )

        guard let data = model.originalData else {
            completionHandler(output)
            return
        }

        // Also add the edit to the Post library (shared App Group store).
        ProjectStore.create(
            originalData: data,
            state: state,
            thumbnail: model.thumbnailData(),
            in: ProjectStore.makeContainer().mainContext
        )

        let exporter = ImageExporter()
        if let rendered = try? await exporter.export(imageData: data, state: state, format: .jpeg) {
            try? rendered.write(to: output.renderedContentURL)
        }
        completionHandler(output)
    }
}

/// Carries a non-Sendable value across an isolation hop where we can guarantee safety by hand
/// (Photos hands us the completion once; we invoke it once, on the main actor).
private nonisolated struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
