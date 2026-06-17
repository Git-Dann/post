import Testing
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PostKit

@Suite("EditState")
struct EditStateTests {
    @Test("Round-trips through Codable")
    func codable() throws {
        var state = EditState()
        state.brightness = 0.3
        state.fade = 0.5
        state.crop = CropRect(x: 0.1, y: 0.2, width: 0.6, height: 0.7)
        state.rotationQuarterTurns = 2

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(EditState.self, from: data)
        #expect(decoded == state)
    }

    @Test("Round-trips every field through Codable")
    func codableAllFields() throws {
        var s = EditState()
        s.exposure = 0.11; s.brightness = 0.22; s.contrast = 0.33
        s.highlights = -0.44; s.shadows = 0.55; s.saturation = -0.66
        s.vibrance = 0.77; s.hue = -0.12; s.warmth = 0.34; s.tint = -0.56
        s.fade = 0.6; s.grain = 0.5; s.sharpness = 0.7; s.vignette = 0.8
        s.crop = CropRect(x: 0.1, y: 0.15, width: 0.7, height: 0.6)
        s.straightenAngle = 0.2; s.rotationQuarterTurns = 3
        s.flippedHorizontally = true; s.flippedVertically = true

        let decoded = try JSONDecoder().decode(EditState.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)   // catches any field missed in CodingKeys / decodeIfPresent
    }

    @Test("Identity and tone detection")
    func identity() {
        #expect(EditState().isIdentity)
        #expect(!EditState().hasToneAdjustments)
        var s = EditState()
        s.saturation = 0.4
        #expect(!s.isIdentity)
        #expect(s.hasToneAdjustments)
    }
}

@Suite("FilterPipeline")
struct FilterPipelineTests {
    private func sample(_ w: CGFloat = 200, _ h: CGFloat = 100) -> CIImage {
        CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    @Test("Neutral recipe preserves extent")
    func neutral() {
        let src = sample()
        let out = FilterPipeline.makeImage(source: src, state: EditState())
        #expect(out.extent == src.extent)
    }

    @Test("Crop reduces extent")
    func crop() {
        let src = sample()
        var s = EditState()
        s.crop = CropRect(x: 0, y: 0, width: 0.5, height: 1)
        let out = FilterPipeline.makeImage(source: src, state: s)
        #expect(abs(out.extent.width - 100) < 1)
        #expect(abs(out.extent.height - 100) < 1)
        #expect(out.extent.origin == .zero)
    }

    @Test("90° rotation swaps dimensions")
    func rotate() {
        let src = sample()
        var s = EditState()
        s.rotationQuarterTurns = 1
        let out = FilterPipeline.makeImage(source: src, state: s)
        #expect(abs(out.extent.width - 100) < 1)
        #expect(abs(out.extent.height - 200) < 1)
    }

    /// A patterned source (edges + two colours + tonal range) so every kind of adjustment has
    /// something to act on — a flat colour wouldn't reveal e.g. sharpness.
    private func checkerboard(_ w: CGFloat = 64, _ h: CGFloat = 64) -> CIImage {
        let f = CIFilter.checkerboardGenerator()
        f.width = 8
        f.color0 = CIColor(red: 0.15, green: 0.25, blue: 0.5)
        f.color1 = CIColor(red: 0.85, green: 0.7, blue: 0.4)
        return (f.outputImage ?? CIImage(color: .gray)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    private func bytes(_ image: CIImage, _ ctx: CIContext) -> Data? {
        guard let cg = ctx.createCGImage(image, from: image.extent) else { return nil }
        return cg.dataProvider?.data as Data?
    }

    @Test("Every dial tool changes the rendered image")
    func toolsAffectOutput() {
        let src = checkerboard()
        let ctx = CIContext(options: [.cacheIntermediates: false])
        let neutral = bytes(FilterPipeline.makeImage(source: src, state: EditState()), ctx)
        #expect(neutral != nil)
        // Excluded: grain (its Metal kernel loads from the host app's metallib, absent in the test
        // bundle) and auto (it resolves through EditorModel, not a direct EditState field).
        for tool in EditTool.dialTools where tool != .grain && tool != .auto {
            var s = EditState()
            tool.set(tool.range.upperBound, in: &s)
            let out = bytes(FilterPipeline.makeImage(source: src, state: s), ctx)
            #expect(out != neutral, "Tool \(tool.title) produced no visible change")
            #expect(s.hasToneAdjustments, "Tool \(tool.title) isn't reflected in hasToneAdjustments")
        }
    }

    @Test("Tone + film adjustments render to a valid image")
    func renders() {
        let src = sample()
        var s = EditState()
        s.brightness = 0.4
        s.contrast = 0.5
        s.saturation = -0.3
        s.hue = 0.2
        s.fade = 0.6
        s.grain = 0.4
        let out = FilterPipeline.makeImage(source: src, state: s)
        #expect(out.extent.width == 200)

        let context = CIContext()
        let cg = context.createCGImage(out, from: out.extent)
        #expect(cg != nil)
    }
}

@Suite("ImageExporter")
struct ImageExporterTests {
    private func sampleJPEG(_ size: CGSize = CGSize(width: 96, height: 64)) -> Data {
        let image = CIImage(color: CIColor(red: 0.6, green: 0.3, blue: 0.2))
            .cropped(to: CGRect(origin: .zero, size: size))
        let context = CIContext()
        return context.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [:]
        ) ?? Data()
    }

    @Test("Exports non-empty HEIC")
    func heic() async throws {
        let data = sampleJPEG()
        #expect(!data.isEmpty)
        let exporter = ImageExporter()
        var s = EditState()
        s.contrast = 0.3
        s.grain = 0.2
        let out = try await exporter.export(imageData: data, state: s, format: .heic)
        #expect(!out.isEmpty)
    }

    @Test("Exports non-empty JPEG with crop")
    func jpeg() async throws {
        let data = sampleJPEG()
        let exporter = ImageExporter()
        var s = EditState()
        s.crop = CropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let out = try await exporter.export(imageData: data, state: s, format: .jpeg)
        #expect(!out.isEmpty)
    }
}
