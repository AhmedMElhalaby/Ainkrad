import Foundation
import Testing
@testable import Ainkrad

@Suite("CanvasChartParse")
struct CanvasDiagramTests {
    @Test func parsesValidCSVRows() {
        let bars = CanvasChartParse.bars(from: "Ada,3\nBo,7")
        #expect(bars == [
            CanvasChartBar(label: "Ada", value: 3),
            CanvasChartBar(label: "Bo", value: 7),
        ])
    }

    @Test func skipsMalformedRowsButKeepsGoodOnes() {
        // "junk" has no comma → not exactly two cells; "Cy,x" has a
        // non-numeric value. Both are dropped, "Ada,3" survives.
        let bars = CanvasChartParse.bars(from: "junk\nAda,3\nCy,x")
        #expect(bars == [CanvasChartBar(label: "Ada", value: 3)])
    }

    @Test func allMalformedRowsGiveEmptyResult() {
        #expect(CanvasChartParse.bars(from: "junk\nmore junk").isEmpty)
    }

    @Test func emptyBodyGivesEmptyResult() {
        #expect(CanvasChartParse.bars(from: "").isEmpty)
    }

    @Test func negativeValuesAreDropped() {
        let bars = CanvasChartParse.bars(from: "Ada,-3\nBo,4")
        #expect(bars == [CanvasChartBar(label: "Bo", value: 4)])
    }

    @Test func allNegativeValuesGiveEmptyResult() {
        #expect(CanvasChartParse.bars(from: "Ada,-3\nBo,-4").isEmpty)
    }

    @Test func zeroValuesAreKept() {
        let bars = CanvasChartParse.bars(from: "Ada,0\nBo,5")
        #expect(bars == [
            CanvasChartBar(label: "Ada", value: 0),
            CanvasChartBar(label: "Bo", value: 5),
        ])
    }

    @Test func emptyLabelIsDropped() {
        let bars = CanvasChartParse.bars(from: ",5\nBo,4")
        #expect(bars == [CanvasChartBar(label: "Bo", value: 4)])
    }
}
