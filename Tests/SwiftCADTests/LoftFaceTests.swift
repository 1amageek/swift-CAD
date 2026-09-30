import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A planar face of a body lofts like a profile: from one box's top to another's bottom above it.
@Suite("Loft face")
struct LoftFaceTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "loft face"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    private func face(of box: FeatureID, facing z: Double, in builder: DocumentBuilder) throws -> SectionReference {
        let evaluated = try evaluate(builder)
        let key = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return (face.orientation == .forward ? plane.normal : plane.normal * -1).z * z > 0.99
        }?.key)
        return .face(FaceSectionReference(featureID: box, face: try builder.stableSubshape(key), bodyRole: .body))
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxsTopLoftsToAnotherBoxsBottom() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let lower = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let upper = try builder.box(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: 0.05), axis: .unitZ, referenceDirection: .unitX),
            width: length(0.02), depth: length(0.02), height: length(0.02)
        )
        let top = try face(of: lower, facing: 1, in: builder)
        let bottom = try face(of: upper, facing: -1, in: builder)
        _ = try builder.loft(sections: [LoftSectionReference(section: top), LoftSectionReference(section: bottom)])
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 3)
        // Two 20 mm cubes and the 20 × 20 × 30 mm block lofted between them.
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - (2 * 0.02 * 0.02 * 0.02 + 0.02 * 0.02 * 0.03)) < 1e-12)
    }
}
