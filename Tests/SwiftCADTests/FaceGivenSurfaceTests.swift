import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A face of a solid given control points (Plasticity's Raise Degree on a box's face) and then a
/// control point moved: raised, the face keeps its shape and edges; moved, it bulges and the faces
/// beside it keep their planes, meeting it on re-solved edges, the box closed.
@Suite("Face given surface")
struct FaceGivenSurfaceTests {
    private let s = 0.02
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "given"))
    }

    private func face(of feature: FeatureID, in builder: DocumentBuilder, normal: Vector3D) throws -> StableSubshapeReference {
        let evaluated = try evaluate(builder)
        let keys = evaluated.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == feature, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .plane(plane)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return nil }
            let outward = plane.normal * (face.orientation == .forward ? 1 : -1)
            return outward.dot(normal) > 0.99 ? key : nil
        }.sorted()
        let key = try #require(keys.first)
        return try builder.stableSubshape(key)
    }

    private func volume(_ feature: FeatureID, in evaluated: EvaluatedDocument) throws -> Double {
        let bodyID = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == feature, case let .body(id) = value else { return nil }
            return id
        }.first)
        return try evaluated.brep.volume(of: bodyID, tolerance: .standard)
    }

    private func raised(_ surface: BSplineSurface3D) throws -> BSplineSurface3D {
        try surface.elevatingDegree(direction: .u, tolerance: .standard).elevatingDegree(direction: .v, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(2)))
    func aRaisedBoxFaceKeepsItsShapeAndEdges() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(s), depth: length(s), height: length(s))
        let top = try face(of: box, in: builder, normal: .unitZ)
        let flat = try FaceBSplineSurfaceConverter().surface(of: top, in: try evaluate(builder))
        #expect(flat.uDegree == 1 && flat.vDegree == 1 && flat.controlPoints.joined().count == 4)
        let surface = try raised(flat)
        let given = try builder.rebuildFaces(target: box, faces: [top], method: .given(surface))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try volume(given, in: evaluated) - s * s * s) < s * s * s * 1e-9)
        let splines = evaluated.brep.faces.values.compactMap { face -> BSplineSurface3D? in
            if case let .bSpline(spline)? = evaluated.brep.geometry.surfaces[face.surfaceID] { return spline }
            return nil
        }
        #expect(splines.count == 1 && splines.allSatisfy { $0.uDegree == 2 && $0.vDegree == 2 && $0.controlPoints.joined().count == 9 })
        // The method persists as it is.
        let decoded = try JSONDecoder().decode(FaceRebuildMethod.self, from: try JSONEncoder().encode(FaceRebuildMethod.given(surface)))
        #expect(decoded == .given(surface))
    }

    @Test(.timeLimit(.minutes(2)))
    func aMovedControlPointBulgesTheFaceAndItsNeighboursFollow() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(s), depth: length(s), height: length(s))
        let side = try face(of: box, in: builder, normal: .unitX)
        var surface = try raised(try FaceBSplineSurfaceConverter().surface(of: side, in: try evaluate(builder)))
        // The middle control point of the row along the top, moved 5 mm out of the box.
        let top = surface.controlPoints.joined().map(\.z).max() ?? 0
        let net = surface.controlPoints
        let candidates = net.indices.flatMap { r in net[r].indices.map { (r, $0) } }.filter { r, c in
            abs(net[r][c].z - top) < 1e-12 && (r == 1 || c == 1) && (r != 1 || c != 1)
        }
        let (row, column) = try #require(candidates.first)
        let d = 0.005
        surface.controlPoints[row][column] = surface.controlPoints[row][column] + Vector3D(x: d, y: 0, z: 0)
        let given = try builder.rebuildFaces(target: box, faces: [side], method: .given(surface))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The bulge is d times the face's area times the integrals of 2u(1 − u) and v² (1/3 each).
        let expected = s * s * s + d * s * s / 9
        let measured = try volume(given, in: evaluated)
        #expect(abs(measured - expected) < s * s * s * 1e-6, "\(measured) vs \(expected)")
        // The faces beside it keep their planes.
        let planes = evaluated.brep.faces.values.filter { face in
            if case .plane? = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            return false
        }
        #expect(planes.count == 5)
    }
}
