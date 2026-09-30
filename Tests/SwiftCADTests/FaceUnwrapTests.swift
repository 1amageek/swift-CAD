import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Unwrap Face lays a face flat in the XY plane about the origin, beside its body: a quarter of a
/// cylinder's wall unrolls into a rectangle as long as its arc, and a curved sheet lays out its
/// arc lengths; the body stays as it was.
@Suite("Unwrap Face")
struct FaceUnwrapTests {
    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "unwrap"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func face(of feature: FeatureID, in builder: DocumentBuilder, where predicate: (Surface3D) -> Bool) throws -> StableSubshapeReference {
        let evaluated = try evaluate(builder)
        let key = try #require(evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == feature, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return predicate(surface)
        }.map(\.key).min())
        return try builder.stableSubshape(key)
    }

    /// The vertices of the body `feature` made.
    private func points(of feature: FeatureID, in evaluated: EvaluatedDocument) throws -> [Point3D] {
        let bodyID = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == feature, case .body = value else { return false }
            return true
        }.flatMap { entry -> BodyID? in
            if case let .body(id) = entry.value { return id }
            return nil
        })
        let scope = try BodyTopologyScope(bodyID: bodyID, model: evaluated.brep)
        return scope.references.compactMap { reference -> Point3D? in
            guard case let .vertex(id) = reference else { return nil }
            return evaluated.brep.vertices[id]?.point
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aQuarterOfACylindersWallUnrollsIntoARectangleAboutTheOrigin() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (radius, height) = (0.01, 0.02)
        let cylinder = try builder.cylinder(radius: .constant(.length(radius, unit: .meter)), height: .constant(.length(height, unit: .meter)))
        let wall = try face(of: cylinder, in: builder) { surface in
            switch surface {
            case .cylinder, .analytic(.cylinder): true
            default: false
            }
        }
        let flat = try builder.unwrapFace(target: cylinder, face: wall)
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 2)
        let corners = try points(of: flat, in: evaluated)
        #expect(corners.isEmpty == false)
        #expect(corners.allSatisfy { abs($0.z) < 1e-12 })
        let xs = corners.map(\.x), ys = corners.map(\.y)
        // The primitive's wall is four quarter faces.
        #expect(abs((xs.max() ?? 0) - (xs.min() ?? 0) - Double.pi / 2 * radius) < 1e-7)
        #expect(abs((ys.max() ?? 0) - (ys.min() ?? 0) - height) < 1e-7)
        #expect(abs((xs.max() ?? 0) + (xs.min() ?? 0)) < 1e-7 && abs((ys.max() ?? 0) + (ys.min() ?? 0)) < 1e-7)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCurvedSheetLaysOutItsArcLengths() throws {
        let s = 0.02
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A parabolic arch z = s·u·(1 − u), x = s·u, swept along y.
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: s / 2, y: y, z: s / 2), Point3D(x: s, y: y, z: 0)] }
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(s)]
        ))
        let only = try face(of: sheet, in: builder) { _ in true }
        let flat = try builder.unwrapFace(target: sheet, face: only)
        let corners = try points(of: flat, in: try evaluate(builder))
        // The parabola's length: ∫₀¹ s·√(1 + (1 − 2u)²) du.
        let length = s * (2.0.squareRoot() / 2 + asinh(1) / 2)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        #expect(abs((xs.max() ?? 0) - (xs.min() ?? 0) - length) < 1e-7)
        #expect(abs((ys.max() ?? 0) - (ys.min() ?? 0) - s) < 1e-7)
    }
}
