import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Rebuild Face refits a face's surface on its own parameters: a sheet of one face to an explicit
/// layout or widened past its edges, and faces sharing edges in place within a tolerance, tangent
/// neighbours and open edges and all; a face sharing edges refitted coarser than the modeling
/// tolerance is refused.
@Suite("Rebuild Face")
struct FaceRebuildTests {
    private let s = 0.02

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rebuild"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func faces(of feature: FeatureID, in builder: DocumentBuilder, where predicate: (Surface3D) -> Bool = { _ in true }) throws -> [(StableSubshapeReference, Surface3D)] {
        let evaluated = try evaluate(builder)
        return try evaluated.subshapes.entries.compactMap { key, value -> (SubshapeID, Surface3D)? in
            guard key.featureID == feature, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID], predicate(surface) else { return nil }
            return (key, surface)
        }.sorted { $0.0 < $1.0 }.map { (try builder.stableSubshape($0.0), $0.1) }
    }

    private func isPlane(_ surface: Surface3D) -> Bool {
        switch surface {
        case .plane, .analytic(.plane): true
        default: false
        }
    }

    private func isCylinder(_ surface: Surface3D) -> Bool {
        switch surface {
        case .cylinder, .analytic(.cylinder): true
        default: false
        }
    }

    private func volume(of feature: FeatureID, in evaluated: EvaluatedDocument) throws -> Double {
        let bodyID = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == feature, case .body = value else { return false }
            return true
        }.flatMap { entry -> BodyID? in
            if case let .body(id) = entry.value { return id }
            return nil
        })
        return try evaluated.brep.volume(of: bodyID, tolerance: .standard)
    }

    private func arch(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: s / 2, y: y, z: s / 2), Point3D(x: s, y: y, z: 0)] }
        return try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(s)]
        ))
    }

    @Test(.timeLimit(.minutes(2)))
    func aSheetTakesAnExplicitLayoutOnItsOwnParameters() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try arch(&builder)
        let (face, before) = try #require(try faces(of: sheet, in: builder).first)
        let rebuilt = try builder.rebuildFaces(
            target: sheet, faces: [face], method: .explicit(SurfaceControlLayout(uDegree: 3, vDegree: 3, uSpans: 4, vSpans: 2))
        )
        let (_, after) = try #require(try faces(of: rebuilt, in: builder).first)
        guard case let .bSpline(surface) = after else { Issue.record("A rebuilt face is a B-spline surface."); return }
        #expect(surface.uDegree == 3 && surface.vDegree == 3)
        #expect(surface.uKnots.count == 4 + 3 + 4 && surface.vKnots.count == 2 + 3 + 4)
        // A quadratic by linear arch is reproduced exactly by cubics interpolating it.
        for (u, v) in [(0.0, 0.0), (0.3, 0.7), (0.5, 0.5), (1.0, 1.0)] {
            let a = try before.differentialGeometry(u: u, v: v, tolerance: .standard).position
            let b = try after.differentialGeometry(u: u, v: v, tolerance: .standard).position
            #expect((a - b).length < 1e-12)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func anExtendedSheetReachesPastItsEdgesAndKeepsThem() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try arch(&builder)
        let (face, before) = try #require(try faces(of: sheet, in: builder).first)
        let rebuilt = try builder.rebuildFaces(target: sheet, faces: [face], method: .tolerance(.constant(.length(1e-7, unit: .meter))), extendU: 0.25)
        let evaluated = try evaluate(builder)
        let (_, after) = try #require(try faces(of: rebuilt, in: builder).first)
        guard case let .bSpline(surface) = after else { Issue.record("A rebuilt face is a B-spline surface."); return }
        #expect(abs((surface.uKnots.first ?? 0) + 0.25) < 1e-12 && abs((surface.uKnots.last ?? 0) - 1.25) < 1e-12)
        // Past u = 1 the arch carries on as its parabola; the face still ends at its old edges.
        let beyond = try after.differentialGeometry(u: 1.2, v: 0, tolerance: .standard).position
        #expect(abs(beyond.z - s * 1.2 * (1 - 1.2)) < 1e-7)
        let corner = try before.differentialGeometry(u: 1, v: 1, tolerance: .standard).position
        #expect(evaluated.brep.vertices.values.contains { ($0.point - corner).length < 1e-9 })
        #expect(evaluated.brep.vertices.values.allSatisfy { $0.point.x < s + 1e-9 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxsTopIsRebuiltInPlace() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let side = CADExpression.constant(.length(0.02, unit: .meter))
        let box = try builder.box(width: side, depth: side, height: side)
        let (top, _) = try #require(try faces(of: box, in: builder) { surface in
            guard case let .plane(plane) = surface else { return false }
            return plane.normal.z > 0.99
        }.first)
        let volume = try volume(of: box, in: try evaluate(builder))
        let rebuilt = try builder.rebuildFaces(target: box, faces: [top], method: .tolerance(.constant(.length(1e-7, unit: .meter))))
        let evaluated = try evaluate(builder)
        #expect(try faces(of: rebuilt, in: builder) { if case .bSpline = $0 { return true }; return false }.count == 1)
        #expect(abs(try self.volume(of: rebuilt, in: evaluated) - volume) < volume * 1e-9)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCylinderWallBesideItsTangentNeighboursIsRebuiltInPlace() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cylinder = try builder.cylinder(radius: .constant(.length(0.01, unit: .meter)), height: .constant(.length(0.02, unit: .meter)))
        let (wall, _) = try #require(try faces(of: cylinder, in: builder) { isCylinder($0) }.first)
        let volume = try volume(of: cylinder, in: try evaluate(builder))
        let rebuilt = try builder.rebuildFaces(target: cylinder, faces: [wall], method: .tolerance(.constant(.length(1e-8, unit: .meter))))
        let evaluated = try evaluate(builder)
        let (_, after) = try #require(try faces(of: rebuilt, in: builder) { if case .bSpline = $0 { return true }; return false }.first)
        guard case let .bSpline(surface) = after, let u0 = surface.uKnots.first, let u1 = surface.uKnots.last else {
            Issue.record("A rebuilt wall is a B-spline surface.")
            return
        }
        let point = try after.differentialGeometry(u: (u0 + u1) / 2, v: 0.01, tolerance: .standard).position
        #expect(abs(Vector3D(x: point.x, y: point.y, z: 0).length - 0.01) < 1e-8)
        #expect(abs(try self.volume(of: rebuilt, in: evaluated) - volume) < volume * 1e-5)
    }

    @Test(.timeLimit(.minutes(2)))
    func anEnclosedFaceRebuiltCoarselyIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cylinder = try builder.cylinder(radius: .constant(.length(0.01, unit: .meter)), height: .constant(.length(0.02, unit: .meter)))
        let (wall, _) = try #require(try faces(of: cylinder, in: builder) { isCylinder($0) }.first)
        _ = try builder.rebuildFaces(target: cylinder, faces: [wall], method: .explicit(SurfaceControlLayout(uDegree: 1, vDegree: 1, uSpans: 1, vSpans: 1)))
        #expect(throws: (any Error).self) { _ = try evaluate(builder) }
    }

    @Test(.timeLimit(.minutes(2)))
    func aWallOfAnOpenBoxWithAnOpenEdgeIsRebuiltInPlace() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: .constant(.length(40, unit: .millimeter)), height: .constant(.length(20, unit: .millimeter))) }
        let box = try builder.extrude(profile, distance: .constant(.length(10, unit: .millimeter)))
        let top = try builder.stableSubshape(generatedBy: box, selector: .generated(role: .endFace))
        let open = try builder.faceDelete(target: box, faces: [top])
        let (wall, _) = try #require(try faces(of: open, in: builder) { surface in
            guard case let .plane(plane) = surface else { return false }
            return abs(plane.normal.z) < 0.1
        }.first)
        let rebuilt = try builder.rebuildFaces(target: open, faces: [wall], method: .explicit(SurfaceControlLayout(uDegree: 2, vDegree: 2, uSpans: 3, vSpans: 1)))
        _ = try evaluate(builder)
        #expect(try faces(of: rebuilt, in: builder) { if case .bSpline = $0 { return true }; return false }.count == 1)
    }
}
