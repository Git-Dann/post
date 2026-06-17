import Testing
import Foundation
import PostKit

@Suite("Styles")
struct StylesTests {
    @Test("Partial recipe decodes with neutral defaults")
    func partialRecipe() throws {
        let json = #"{"fade":0.6,"contrast":-0.12}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(EditState.self, from: json)
        #expect(state.fade == 0.6)
        #expect(state.contrast == -0.12)
        #expect(state.brightness == 0)
        #expect(state.saturation == 0)
        #expect(state.crop == .full)
        #expect(state.rotationQuarterTurns == 0)
    }

    @Test("Bundled styles load and include expected looks")
    func bundled() async throws {
        let manifest = try await BundledStyleSource().load()
        #expect(manifest.version >= 1)
        #expect(manifest.styles.count >= 8)
        #expect(manifest.styles.contains { $0.id == "film" })
        #expect(manifest.styles.contains { $0.id == "dream" })
        // Every shipped look must actually change the image.
        #expect(manifest.styles.allSatisfy { !$0.recipe.isIdentity })
        // Ids must be unique.
        #expect(Set(manifest.styles.map(\.id)).count == manifest.styles.count)
    }
}
