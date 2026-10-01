import Foundation
import Testing
import CADCore
import CADIR
@testable import CADKernel
@testable import SwiftCAD

/// Revolve's Normal, Binormal and Tangent axes come from the section: through its boundary's start,
/// along the boundary there, the section plane's normal and their cross product.
@Suite("Revolve section axes")
struct RevolveSectionAxisTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    @Test(.timeLimit(.minutes(2)))
    func aRectangleRevolvesAboutItsTangentAndBinormalAxes() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.01), height: length(0.005)) }
        let profile = ProfileReference(featureID: sketch.featureID, profileIndex: 0)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "axes"))
        let axes = try RevolveSectionAxis.Direction.allCases.map {
            ($0, try RevolveSectionAxis().axis($0, section: .profile(profile), in: evaluated))
        }
        let byDirection = Dictionary(uniqueKeysWithValues: axes.map { ($0.0, $0.1) })
        let (normal, tangent, binormal) = (try #require(byDirection[.normal]), try #require(byDirection[.tangent]), try #require(byDirection[.binormal]))
        // Normal is the sketch plane's; Tangent runs along a side from a corner; Binormal lies in the plane across it.
        #expect(abs(abs(normal.direction.z) - 1) < 1e-12)
        #expect(abs(tangent.direction.z) < 1e-12 && abs(binormal.direction.z) < 1e-12)
        #expect(abs(tangent.direction.dot(binormal.direction)) < 1e-12)
        #expect(normal.origin == tangent.origin && tangent.origin == binormal.origin)
        // Revolved a full turn about each in-plane axis: Pappus with the rectangle's centroid.
        // The rectangle's centroid: the middle of its corners.
        guard case let .sketch(source)? = evaluated.document.designGraph.nodes[sketch.featureID]?.operation else {
            Issue.record("The sketch is a sketch.")
            return
        }
        let loop = try SketchProfileExtractor(tolerance: .standard).extractProfiles(
            from: source, sourceFeatureID: sketch.featureID, parameters: evaluated.parameters)[0].outerLoop
        let ends = loop.boundarySegments.compactMap { segment -> Point3D? in
            if case let .line(line) = segment { return line.start }
            return nil
        }
        #expect(ends.count == 4)
        let centroid = Point3D.origin + ends.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * 0.25
        #expect(ends.contains { $0.isApproximatelyEqual(to: tangent.origin, tolerance: 1e-12) })
        for axis in [tangent, binormal] {
            var revolved = builder
            let body = try revolved.revolve(profile, axis: axis)
            let result = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try revolved.build(name: "axes"))
            try result.brep.validate(level: .volumetric, tolerance: .standard)
            let offset = centroid - axis.origin
            let direction = try axis.direction.normalized(tolerance: 1e-12)
            let distance = (offset - direction * offset.dot(direction)).length
            let volume = try result.brep.volume(tolerance: .standard)
            #expect(abs(volume - 2 * Double.pi * 0.01 * 0.005 * distance) < 1e-12, "\(body): \(volume)")
        }
    }
}
