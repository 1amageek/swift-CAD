import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Fillet Shell's shapes round a box's edge with a conic, a chordal arc or a curvature-continuous
/// quintic: the volume removed is the cross-section's area beyond the curve times the edge's length.
@Suite("Fillet shapes")
struct FilletShapeTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// A 20 mm box with its first generated edge filleted; the edge's length and the evaluated body.
    private func fillet(shape: FilletShape, tension: Double?, distance: Double) throws -> (EvaluatedDocument, Double) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let edge = try builder.stableSubshape(generatedBy: box, selector: .generated(role: .edge, index: 0))
        _ = try builder.fillet(target: box, edges: [edge], radius: length(distance), shape: shape, tension: tension)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "fillet"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return (evaluated, 0.02)
    }

    /// The area between a corner's two sides and the curve through `points` with `weights`,
    /// by Green's theorem over the rational Bézier and its two straight sides.
    private func removedArea(_ points: [(Double, Double)], weights: [Double]) -> Double {
        let n = points.count - 1
        func binomial(_ k: Int) -> Double { (0..<k).reduce(1.0) { $0 * Double(n - $1) / Double($1 + 1) } }
        func point(_ t: Double) -> (Double, Double) {
            var x = 0.0, y = 0.0, w = 0.0
            for (k, p) in points.enumerated() {
                let b = binomial(k) * pow(t, Double(k)) * pow(1 - t, Double(n - k)) * weights[k]
                x += b * p.0; y += b * p.1; w += b
            }
            return (x / w, y / w)
        }
        // Signed area of the closed loop corner → first contact → curve → second contact → corner.
        var area = 0.0
        let steps = 20_000
        var previous = point(0)
        for step in 1...steps {
            let next = point(Double(step) / Double(steps))
            area += previous.0 * next.1 - next.0 * previous.1
            previous = next
        }
        return abs(0.5 * area)
    }

    @Test(.timeLimit(.minutes(2)))
    func conicChordalAndCurvatureShapesRemoveTheirCrossSections() throws {
        let d = 0.004, box = 0.02 * 0.02 * 0.02
        // Corner at the origin, the first face along +x, the second along +y.
        let cases: [(FilletShape, Double?, [(Double, Double)], [Double])] = [
            (.conic, 0.5, [(d, 0), (0, 0), (0, d)], [1, 1, 1]),
            (.conic, 0.3, [(d, 0), (0, 0), (0, d)], [1, 0.3 / 0.7, 1]),
            (.chordal, nil, [(d / 2.0.squareRoot(), 0), (0, 0), (0, d / 2.0.squareRoot())], [1, 0.5.squareRoot(), 1]),
            (.curvature, 1, [(d, 0), (2 * d / 3, 0), (d / 3, 0), (0, d / 3), (0, 2 * d / 3), (0, d)], Array(repeating: 1, count: 6)),
        ]
        for (shape, tension, points, weights) in cases {
            let (evaluated, edgeLength) = try fillet(shape: shape, tension: tension, distance: d)
            // The removed region: the corner between the sides and the curve.
            let expected = box - removedArea(points, weights: weights) * edgeLength
            let volume = try evaluated.brep.volume(tolerance: .standard)
            #expect(abs(volume - expected) < 5e-12, "\(shape) \(String(describing: tension)): \(volume) vs \(expected)")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func shapesTakeOneEdgeAndTheirOwnTension() throws {
        #expect(throws: KernelError.self) {
            try FilletFeature(target: FilletTargetReference(featureID: FeatureID()), edges: [], radius: length(0.004),
                              allEdges: true, shape: .conic).validate()
        }
        #expect(throws: KernelError.self) { _ = try fillet(shape: .chordal, tension: 0.4, distance: 0.004) }
        #expect(throws: KernelError.self) { _ = try fillet(shape: .conic, tension: 1, distance: 0.004) }
    }

    @Test(.timeLimit(.minutes(2)))
    func aFullFilletRoundsARibsTopAcrossItsWidth() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A rib 20 mm wide, 40 mm long and 30 mm tall; its top's two long edges bound the round.
        let rib = try builder.box(width: length(0.02), depth: length(0.04), height: length(0.03))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rib"))
        let topEdges = try before.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == rib, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point,
                  abs(start.z - end.z) < 1e-12, abs(start.x - end.x) < 1e-12, abs(start.y - end.y) > 0.03 else { return nil }
            return (try before.brep.vertices[edge.startVertexID].map { abs($0.point.z - start.z) } ?? 1) < 1e-12 ? key : nil
        }
        let top = topEdges.filter { key in
            guard case let .edge(id) = before.subshapes.entries[key], let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return start.z > 0.02
        }
        #expect(top.count == 2)
        let edges = try top.map { try builder.stableSubshape($0) }
        // A radius other than the half width the faces fix is refused.
        var stated = builder
        _ = try stated.fillet(target: rib, edges: edges, radius: length(0.009), shape: .full)
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try stated.build(name: "rib"))
        }
        _ = try builder.fillet(target: rib, edges: edges, radius: length(0.01), shape: .full)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rib"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The top 10 mm of the cross-section becomes a half disc of radius 10 mm.
        let r = 0.01
        let expected = 0.02 * 0.04 * 0.03 - 0.04 * (2 * r * r - Double.pi * r * r / 2)
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
        // The highest point is the top's middle line, still at 30 mm.
        let highest = evaluated.brep.vertices.values.map(\.point.z).max() ?? 0
        #expect(highest < 0.03 - 1e-6)

        // Two edges that do not bound one face are refused.
        var wrong = DocumentBuilder(units: .meters, tolerance: .standard)
        let other = try wrong.box(width: length(0.02), depth: length(0.04), height: length(0.03))
        let twoEdges = try [0, 1].map { try wrong.stableSubshape(generatedBy: other, selector: .generated(role: .edge, index: $0)) }
        _ = try wrong.fillet(target: other, edges: twoEdges, radius: length(0.01), shape: .full)
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try wrong.build(name: "rib"))
        }
    }
}
