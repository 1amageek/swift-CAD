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

    /// The middle control point pushed out: the face's edges stay on its surface, so it keeps them
    /// and bulges by d · w · h / 9 between them.
    @Test(.timeLimit(.minutes(2)))
    func aMovedMiddleControlPointBulgesTheFaceBetweenItsEdges() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(s), depth: length(s), height: length(s))
        let side = try face(of: box, in: builder, normal: .unitX)
        var surface = try raised(try FaceBSplineSurfaceConverter().surface(of: side, in: try evaluate(builder)))
        let d = 0.005
        surface.controlPoints[1][1] = surface.controlPoints[1][1] + Vector3D(x: d, y: 0, z: 0)
        let given = try builder.rebuildFaces(target: box, faces: [side], method: .given(surface))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let measured = try volume(given, in: evaluated)
        #expect(abs(measured - (s * s * s + d * s * s / 9)) < s * s * s * 1e-6, "\(measured)")
    }

    /// A whole box raised face by face (Plasticity's Raise Degree on a solid): each Rebuild Face
    /// names its face as the box made it, found through the ones before by lineage; the box keeps
    /// its volume with every face a degree-2 B-spline.
    @Test(.timeLimit(.minutes(2)))
    func everyFaceOfABoxIsRaisedThroughTheRebuildsBeforeIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(s), depth: length(s), height: length(s))
        let start = try evaluate(builder)
        let faces = try start.subshapes.entries.filter { key, value in
            guard key.featureID == box, case .face = value else { return false }
            return true
        }.keys.sorted().map { try builder.stableSubshape($0) }
        #expect(faces.count == 6)
        var tip = box
        for face in faces {
            let surface = try raised(try FaceBSplineSurfaceConverter().surface(of: face, in: start))
            tip = try builder.rebuildFaces(target: tip, faces: [face], method: .given(surface))
        }
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try volume(tip, in: evaluated) - s * s * s) < s * s * s * 1e-9)
        let splines = evaluated.brep.faces.values.filter { face in
            if case .bSpline? = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            return false
        }
        #expect(splines.count == 6)
    }

    /// A rounded box edge's round (a quarter cylinder) given control points: the exact rational
    /// surface on parameters of its own, raised; the face keeps its edges, their trimming curves
    /// rebuilt, and the box its volume.
    @Test(.timeLimit(.minutes(2)))
    func aRoundIsGivenItsExactRationalSurfaceAndRaised() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(s), depth: length(s), height: length(s))
        let start = try evaluate(builder)
        let corners = start.brep.vertices.values.map(\.point)
        let (xMax, zMax) = (corners.map(\.x).max() ?? 0, corners.map(\.z).max() ?? 0)
        let edgeKeys = start.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == box, case let .edge(id) = value, let edge = start.brep.edges[id],
                  let a = start.brep.vertices[edge.startVertexID]?.point, let b = start.brep.vertices[edge.endVertexID]?.point else { return nil }
            return abs(a.x - xMax) < 1e-12 && abs(b.x - xMax) < 1e-12 && abs(a.z - zMax) < 1e-12 && abs(b.z - zMax) < 1e-12 ? key : nil
        }.sorted()
        let edge = try builder.stableSubshape(try #require(edgeKeys.first))
        let rounded = try builder.fillet(target: box, edges: [edge], radius: length(0.004))
        let filleted = try evaluate(builder)
        let roundKeys = filleted.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == rounded, case let .face(id) = value, let face = filleted.brep.faces[id] else { return nil }
            switch filleted.brep.geometry.surfaces[face.surfaceID] {
            case .cylinder?, .analytic(.cylinder)?: return key
            default: return nil
            }
        }.sorted()
        let round = try builder.stableSubshape(try #require(roundKeys.first))
        let before = try volume(rounded, in: filleted)
        let rational = try FaceBSplineSurfaceConverter().surface(of: round, in: filleted)
        #expect(rational.uDegree == 2 && rational.vDegree == 1 && rational.weights.joined().contains { abs($0 - 1) > 1e-6 })
        // Exact: every point of it is the round's radius from the round's axis.
        let roundFace = try #require(filleted.brep.faces.values.first { face in
            switch filleted.brep.geometry.surfaces[face.surfaceID] {
            case .cylinder?, .analytic(.cylinder)?: return true
            default: return false
            }
        })
        let (origin, axis, radius): (Point3D, Vector3D, Double)
        switch filleted.brep.geometry.surfaces[roundFace.surfaceID] {
        case let .cylinder(cylinder)?: (origin, axis, radius) = (cylinder.origin, try cylinder.axis.normalized(tolerance: 1e-12), cylinder.radius)
        case let .analytic(.cylinder(o, a, r))?: (origin, axis, radius) = (o, try a.normalized(tolerance: 1e-12), r)
        default: throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: .standard, message: "No round.")
        }
        guard case let .closed(t0, t1) = Surface3D.bSpline(rational).uDomain, case let .closed(w0, w1) = Surface3D.bSpline(rational).vDomain else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: .standard, message: "No domain.")
        }
        for i in 0...20 {
            for j in 0...4 {
                let p = try rational.point(u: t0 + (t1 - t0) * Double(i) / 20, v: w0 + (w1 - w0) * Double(j) / 4, tolerance: .standard)
                let offset = p - origin
                #expect(abs((offset - axis * offset.dot(axis)).length - radius) < 1e-12)
            }
        }
        let given = try builder.rebuildFaces(target: rounded, faces: [round], method: .given(try raised(rational)))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The volume integrated over the rational round agrees to its quadrature's accuracy.
        let after = try volume(given, in: evaluated)
        #expect(abs(after - before) < before * 1e-6, "\(after) vs \(before)")
    }

    /// A drum's side closing round its seam and a ring's face given their exact rational surfaces
    /// and raised: each keeps its edges and the body its volume. A ball's octant, reaching a pole,
    /// is refused.
    @Test(.timeLimit(.minutes(4)), arguments: ["cylinder", "torus", "sphere"])
    func aRevolvedPrimitivesFaceIsGivenItsExactRationalSurface(_ kind: String) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let body: FeatureID
        switch kind {
        case "cylinder": body = try builder.cylinder(radius: length(0.01), height: length(0.02))
        case "sphere": body = try builder.sphere(radius: length(0.01))
        default: body = try builder.torus(majorRadius: length(0.02), minorRadius: length(0.005))
        }
        let start = try evaluate(builder)
        let faces = try start.subshapes.entries.filter { key, value in
            guard key.featureID == body, case let .face(id) = value, let face = start.brep.faces[id] else { return false }
            if case .plane? = start.brep.geometry.surfaces[face.surfaceID] { return false }
            return true
        }.keys.sorted().map { try builder.stableSubshape($0) }
        let face = try #require(faces.first)
        if kind == "sphere" {
            #expect(throws: KernelError.self) { try FaceBSplineSurfaceConverter().surface(of: face, in: start) }
            return
        }
        let before = try volume(body, in: start)
        let given = try builder.rebuildFaces(target: body, faces: [face], method: .given(try raised(try FaceBSplineSurfaceConverter().surface(of: face, in: start))))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let after = try volume(given, in: evaluated)
        #expect(abs(after - before) < before * 1e-6, "\(kind): \(after) vs \(before)")
    }
}
