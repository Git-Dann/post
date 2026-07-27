import Testing
import PostKit

@Suite("Landscape dial banks")
struct DialBankTests {

    @Test("Every adjustment tool is reachable from some bank")
    func coversEveryTool() {
        let banked = Set(DialBank.all.flatMap(\.tools))
        // Auto isn't a bank tool — it stays a one-tap action, like Crop and Styles.
        let expected = Set(EditTool.dialTools.filter { $0.group != .auto })
        #expect(banked == expected)
    }

    @Test("A bank never asks for more corners than there are")
    func fitsTheCorners() {
        for bank in DialBank.all {
            #expect(!bank.tools.isEmpty)
            #expect(bank.tools.count <= DialBank.corners.count)
        }
    }

    @Test("Pages are as few as possible, and balanced")
    func paginationIsBalanced() {
        #expect(DialBank.paginate([]).isEmpty)
        #expect(DialBank.paginate([.exposure, .contrast]).map(\.count) == [2])
        #expect(DialBank.paginate(EditTool.Group.light.tools).map(\.count) == [3, 2])
        #expect(DialBank.paginate(EditTool.Group.finishing.tools).map(\.count) == [4])
    }

    @Test("Paged categories label their pages; single-page ones don't")
    func pageLabels() {
        let light = DialBank.banks(for: .light)
        #expect(light.count == 2)
        #expect(light[0].pageLabel == "1 of 2")
        #expect(light[0].displayTitle == "Light · 1 of 2")

        let effects = DialBank.banks(for: .finishing)
        #expect(effects.count == 1)
        #expect(effects[0].pageLabel == nil)
        #expect(effects[0].displayTitle == "Effects")
    }

    @Test("A tool resolves back to the bank holding it")
    func findsBankForTool() {
        for (index, bank) in DialBank.all.enumerated() {
            for tool in bank.tools {
                #expect(DialBank.index(containing: tool) == index)
            }
        }
        #expect(DialBank.index(containing: .auto) == nil)
    }
}
