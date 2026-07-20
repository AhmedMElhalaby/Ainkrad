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

@Suite("CanvasDiagramRouting")
struct CanvasDiagramRoutingTests {
    private func element(kind: CanvasElementKind, body: String) -> CanvasElement {
        CanvasElement(id: "el-1", kind: kind, body: body)
    }

    @Test func emptyDiagramBodyRoutesToFallback() {
        let route = CanvasDiagramRouting.route(for: element(kind: .diagram, body: "   "))
        #expect(route == .diagramFallback)
    }

    @Test func nonEmptyDiagramBodyRoutesToDiagram() {
        let route = CanvasDiagramRouting.route(for: element(kind: .diagram, body: "graph TD; A-->B"))
        #expect(route == .diagram(source: "graph TD; A-->B"))
    }

    @Test func chartKindRoutesToChartWhenBarsParse() {
        let route = CanvasDiagramRouting.route(for: element(kind: .chart, body: "Ada,3\nBo,7"))
        #expect(route == .chart(bars: [
            CanvasChartBar(label: "Ada", value: 3),
            CanvasChartBar(label: "Bo", value: 7),
        ]))
    }

    @Test func chartKindRoutesToFallbackWhenBarsEmpty() {
        let route = CanvasDiagramRouting.route(for: element(kind: .chart, body: "junk"))
        #expect(route == .chartFallback)
    }

    @Test func nonDiagramNonChartKindRoutesLikeDiagram() {
        // Default (non-.chart) branch covers every other kind, e.g. .unknown.
        let route = CanvasDiagramRouting.route(for: element(kind: .unknown, body: ""))
        #expect(route == .diagramFallback)
    }
}
