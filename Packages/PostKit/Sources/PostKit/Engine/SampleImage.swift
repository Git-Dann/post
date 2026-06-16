import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// A synthetic, colorful image used for development, previews, and the editor's "try it" entry
/// before real photo import lands. Rich enough that every adjustment is visibly felt.
public enum SampleImage {
    public static nonisolated func make(size: CGSize = CGSize(width: 1200, height: 1600)) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)

        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: 0, y: size.height)
        gradient.color0 = CIColor(red: 0.96, green: 0.58, blue: 0.23)
        gradient.point1 = CGPoint(x: size.width, y: 0)
        gradient.color1 = CIColor(red: 0.10, green: 0.18, blue: 0.42)
        var image = (gradient.outputImage ?? CIImage(color: .gray)).cropped(to: rect)

        // A soft "sun" highlight so brightness/contrast/fade read clearly.
        let sun = CIFilter.radialGradient()
        sun.center = CGPoint(x: size.width * 0.7, y: size.height * 0.72)
        sun.radius0 = 0
        sun.radius1 = Float(size.width * 0.45)
        sun.color0 = CIColor(red: 1, green: 0.95, blue: 0.8, alpha: 0.9)
        sun.color1 = CIColor(red: 1, green: 0.95, blue: 0.8, alpha: 0)
        if let sunImage = sun.outputImage?.cropped(to: rect) {
            image = sunImage.composited(over: image)
        }

        return image
    }
}
