import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A thin curve extrusion: the curve's sheet thickened into a solid wall on the curve's left about
/// the extrusion — a line's slab beside it, a circle's ring inside it.
@Suite("Extrude curve thickness")
struct ExtrudeCurveThicknessTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    private func solid(_ feature: FeatureID, in builder: DocumentBuilder) throws -> (volume: Double, points: [Point3D]) {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "thin"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let bodyID = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == feature, case let .body(id) = value else { return nil }
            return id
        }.first)
        let scope = try BodyTopologyScope(bodyID: bodyID, model: evaluated.brep)
        let points = scope.references.compactMap { reference -> Point3D? in
            guard case let .vertex(id) = reference else { return nil }
            return evaluated.brep.vertices[id]?.point
        }
        return (try evaluated.brep.volume(of: bodyID, tolerance: .standard), points)
    }

    @Test(.timeLimit(.minutes(2)))
    func aLineIsThickenedIntoASlabOnItsLeft() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let line = try builder.sketch(on: .xy) { $0.line(from: point(0, 0), to: point(0.02, 0)) }.featureID
        let wall = try builder.extrude(curve: CurveSectionReference(featureID: line), distance: length(0.01), thickness: length(0.002))
        let (volume, points) = try solid(wall, in: builder)
        #expect(abs(volume - 0.02 * 0.002 * 0.01) < 1e-12)
        #expect(points.allSatisfy { $0.y > -1e-12 && $0.y < 0.002 + 1e-12 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aCircleIsThickenedIntoARingInsideIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let circle = try builder.sketch(on: .xy) { $0.circle(center: point(0, 0), radius: length(0.01)) }.featureID
        let ring = try builder.extrude(curve: CurveSectionReference(featureID: circle), distance: length(0.005), thickness: length(0.001))
        let (volume, points) = try solid(ring, in: builder)
        #expect(abs(volume - Double.pi * (0.01 * 0.01 - 0.009 * 0.009) * 0.005) < 1e-12)
        #expect(points.allSatisfy { Vector3D(x: $0.x, y: $0.y, z: 0).length < 0.01 + 1e-9 })
    }
}
