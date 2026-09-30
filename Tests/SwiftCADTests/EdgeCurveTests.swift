import Foundation
import Testing
import CADCore
import CADExchange
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// An edge of a body stands for a curve: its exact curve over its trim, which a pipe follows.
@Suite("Edge curve")
struct EdgeCurveTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "edge curve"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    @Test(.timeLimit(.minutes(2)))
    func aPipeFollowsABoxsTopEdge() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let evaluated = try evaluate(builder)
        // A top edge along X: both ends at z = 20 mm and y = 0.
        let key = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                  let end = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
            return abs(start.z - 0.02) < 1e-12 && abs(end.z - 0.02) < 1e-12 && abs(start.y) < 1e-12 && abs(end.y) < 1e-12
        }?.key)
        let curves = try builder.edgeCurves(of: box, edges: [try builder.stableSubshape(key)])
        let curved = try evaluate(builder)
        let published = try #require(curved.curves[curves])
        #expect(published.count == 1 && published[0].exactCurve != nil && published[0].isClosed == false)

        _ = try builder.pipe(along: curves, diameter: length(0.004), approximationTolerance: length(1e-7))
        let piped = try evaluate(builder)
        #expect(piped.brep.bodies.count == 2)
        #expect(abs(try piped.brep.volume(tolerance: .standard) - (0.02 * 0.02 * 0.02 + Double.pi * 0.002 * 0.002 * 0.02)) < 1e-12)

        let document = try builder.build(name: "edge curve")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes == document.designGraph.nodes)
    }
}
