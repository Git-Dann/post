import Testing
import PostKit

@Suite("PostKit smoke")
struct SmokeTests {
    @Test("Design tokens are sane")
    func tokens() {
        #expect(Theme.Space.m == 16)
        #expect(Theme.Radius.image > Theme.Radius.control)
    }
}
