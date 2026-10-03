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

    /// Plasticity lofts box faces G1 by default: the Loft leaves the lower box's top and arrives
    /// at the upper box's bottom as their walls run on, upright, though the upper box stands 20 mm
    /// over to the side; G0 leaves straight toward it, slanted.
    @Test(.timeLimit(.minutes(2)), arguments: [nil, SurfaceEdgeContinuity.Order.tangent, .curvature])
    func aFaceLoftsTangentToTheWallsAroundIt(order: SurfaceEdgeContinuity.Order?) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let lower = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let upper = try builder.box(
            placement: PrimitivePlacement(origin: Point3D(x: 0.02, y: 0, z: 0.05), axis: .unitZ, referenceDirection: .unitX),
            width: length(0.02), depth: length(0.02), height: length(0.02)
        )
        let top = try face(of: lower, facing: 1, in: builder)
        let bottom = try face(of: upper, facing: -1, in: builder)
        let continuity = order.map { LoftFaceContinuity(order: $0) }
        let loft = try builder.loft(sections: [LoftSectionReference(section: top, faceContinuity: continuity),
                                               LoftSectionReference(section: bottom, faceContinuity: continuity)])
        let evaluated = try evaluate(builder)
        let sides = evaluated.subshapes.entries.compactMap { key, value -> BSplineSurface3D? in
            guard key.featureID == loft, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .bSpline(surface)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return nil }
            return surface
        }
        #expect(sides.count == 4)
        // Each side's normal where it leaves and arrives: level (an upright side) for G1 and G2.
        var levels: [Bool] = []
        for side in sides {
            let u = (side.uKnots.first! + side.uKnots.last!) / 2
            for v in [side.vKnots.first!, side.vKnots.last!] {
                levels.append(abs(try side.normal(u: u, v: v, tolerance: .standard).z) < 1e-6)
            }
        }
        if order == nil {
            #expect(levels.contains(false))
        } else {
            #expect(levels.allSatisfy { $0 })
        }
    }
}
