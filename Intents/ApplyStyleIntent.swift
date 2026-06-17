import AppIntents
import PostKit
import Foundation

/// The bundled looks, exposed to Shortcuts and the Action button. Kept in sync with `styles.json`.
enum StyleChoice: String, AppEnum {
    case faded, warm, film, punch, mono, noir, cool, vivid, sepia, dream

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Look" }

    static var caseDisplayRepresentations: [StyleChoice: DisplayRepresentation] {
        [
            .faded: "Faded",
            .warm: "Warm",
            .film: "Film",
            .punch: "Punch",
            .mono: "Mono",
            .noir: "Noir",
            .cool: "Cool",
            .vivid: "Vivid",
            .sepia: "Sepia",
            .dream: "Dream"
        ]
    }
}

/// A headless App Intent: apply a one-tap look to an image and return the edited result. Runs in
/// Shortcuts, the Action button, and Spotlight — everything stays on device.
struct ApplyStyleIntent: AppIntent {
    static var title: LocalizedStringResource { "Apply a Look" }
    static var description: IntentDescription {
        IntentDescription("Apply one of Post's film looks to a photo, entirely on device.")
    }

    @Parameter(title: "Photo", supportedContentTypes: [.image])
    var image: IntentFile

    @Parameter(title: "Look")
    var style: StyleChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$style) to \(\.$image)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let data = try await image.data(contentType: .image)

        let manifest = try await BundledStyleSource().load()
        let recipe = manifest.styles.first { $0.id == style.rawValue }?.recipe ?? EditState()

        let exporter = ImageExporter()
        let format = ExportPrefs.format
        let output = try await exporter.export(
            imageData: data, state: recipe, format: format, quality: ExportPrefs.quality,
            stripLocation: ExportPrefs.removeLocation, maxDimension: ExportPrefs.maxDimension)

        let result = IntentFile(data: output, filename: "Post-\(style.rawValue).\(format.fileExtension)",
                                type: format.utType)
        return .result(value: result)
    }
}
