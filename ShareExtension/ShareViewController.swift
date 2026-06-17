import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Photos
import PostKit

/// "Edit in Post" from any app's share sheet. Receives an image, hosts the shared `EditorView`,
/// then saves the edited result to the photo library (add-only) and finishes.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        loadSharedImage()
    }

    private func loadSharedImage() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
              }) else {
            finish()
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let data, let loaded = ImageLoader.makeLoaded(from: data) else {
                    self.finish()
                    return
                }
                self.showEditor(data: data, loaded: loaded)
            }
        }
    }

    private func showEditor(data: Data, loaded: ImageLoader.Loaded) {
        let model = EditorModel(source: loaded.preview, originalData: data, previewScale: loaded.previewScale)
        let editor = EditorView(
            model: model,
            exporter: { [weak self] state in await self?.exportToTempFile(data: data, state: state) },
            onDone: { [weak self] state in self?.saveAndFinish(model: model, state: state) },
            onCancel: { [weak self] in self?.finish() }
        )

        let host = UIHostingController(rootView: editor)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func exportToTempFile(data: Data, state: EditState) async -> URL? {
        let exporter = ImageExporter()
        guard let output = try? await exporter.export(imageData: data, state: state, format: .heic, stripLocation: ExportPrefs.removeLocation) else {
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

    private func saveAndFinish(model: EditorModel, state: EditState) {
        guard let data = model.originalData else { finish(); return }
        // Add it to the Post library (shared App Group store) so it shows up in the app.
        ProjectStore.create(
            originalData: data,
            state: state,
            thumbnail: model.thumbnailData(),
            in: ProjectStore.makeContainer().mainContext
        )
        Task {
            let exporter = ImageExporter()
            if let output = try? await exporter.export(imageData: data, state: state, format: .heic, stripLocation: ExportPrefs.removeLocation) {
                await saveToPhotos(output)
            }
            finish()
        }
    }

    private func saveToPhotos(_ data: Data) async {
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
