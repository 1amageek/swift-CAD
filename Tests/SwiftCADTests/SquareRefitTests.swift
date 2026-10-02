import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Square's Refit: a face replaced by an untrimmed four-sided sheet on its own edges — a box's
/// top, a pentagonal prism's top split at its four sharpest corners, and a sheet's face tangent
/// to the curved face beside it — the body keeping its edges, validity and volume.
@Suite("Square refit")
struct SquareRefitTests {
    private let s = 0.02
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "refit"))
    }

    private func face(of feature: FeatureID, in builder: DocumentBuilder, where predicate: (Surface3D) -> Bool) throws -> StableSubshapeReference {
        let evaluated = try evaluate(builder)
        let key = try #require(evaluated.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == feature, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID], predicate(surface) else { return nil }
            return key
        }.sorted().first)
        return try builder.stableSubshape(key)
    }

    private func refitted(_ feature: FeatureID, in evaluated: EvaluatedDocument) throws -> [BSplineSurface3D] {
        evaluated.subshapes.entries.compactMap { key, value -> BSplineSurface3D? in
            guard key.featureID == feature, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .bSpline(spline)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return nil }
            return spline
        }
    }

    private func volume(_ feature: FeatureID, in evaluated: EvaluatedDocument) throws -> Double {
        let bodyID = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == feature, case let .body(id) = value else { return nil }
            return id
        }.first)
        return try evaluated.brep.volume(of: bodyID, tolerance: .standard)
    }

    private func isTop(_ surface: Surface3D) -> Bool {
        guard case let .plane(plane) = surface else { return false }
        return plane.normal.z > 0.99
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxsTopIsRefitFlatOnItsEdges() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(s), depth: length(s), height: length(s))
        let top = try face(of: box, in: builder, where: isTop)
        let refit = try builder.rebuildFaces(target: box, faces: [top], method: .square(SquareRefit(
            options: SquareFitOptions(uDegree: 4, vDegree: 3, uSpans: 2, vSpans: 1)
        )))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let sheets = try refitted(refit, in: evaluated)
        #expect(sheets.count == 1)
        #expect(sheets.allSatisfy { Set([$0.uDegree, $0.vDegree]) == [3, 4] && $0.controlPoints.joined().allSatisfy { abs($0.z - s) < 1e-12 } })
        #expect(abs(try volume(refit, in: evaluated) - s * s * s) < s * s * s * 1e-9)
    }

    @Test(.timeLimit(.minutes(2)))
    func aPentagonsTopIsSplitAtItsFourSharpestCorners() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A square with one corner cut at a shallow angle: its sharpest corners are the other three
        // and the cut's sharper end.
        let corners = [(0.0, 0.0), (s, 0.0), (s, 0.6 * s), (0.8 * s, s), (0.0, s)]
        let profile = try builder.sketch(on: .xy) { sketch in
            for k in corners.indices {
                let (a, b) = (corners[k], corners[(k + 1) % corners.count])
                _ = sketch.line(from: SketchPoint(x: length(a.0), y: length(a.1)), to: SketchPoint(x: length(b.0), y: length(b.1)))
            }
        }
        let prism = try builder.extrude(ProfileReference(featureID: profile.featureID, profileIndex: 0), distance: length(s))
        let top = try face(of: prism, in: builder, where: isTop)
        let before = try volume(prism, in: try evaluate(builder))
        let refit = try builder.rebuildFaces(target: prism, faces: [top], method: .square(SquareRefit()))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let sheets = try refitted(refit, in: evaluated)
        #expect(sheets.count == 1 && sheets.allSatisfy { $0.controlPoints.joined().allSatisfy { abs($0.z - s) < 1e-12 } })
        #expect(abs(try volume(refit, in: evaluated) - before) < before * 1e-9)
    }

    @Test(.timeLimit(.minutes(2)))
    func aSheetsFaceIsRefitTangentToTheCurvedFaceBesideIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A flat floor and, beyond its edge y = 0, a ramp leaving it level and curving up.
        let floor = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: s, y: 0, z: 0)], [Point3D(x: 0, y: s, z: 0), Point3D(x: s, y: s, z: 0)]]
        ))
        let row = { (y: Double, z: Double) in [Point3D(x: 0, y: y, z: z), Point3D(x: s, y: y, z: z)] }
        let ramp = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 2, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: [row(0, 0), row(-s / 2, 0), row(-s, s / 2)]
        ))
        let sheet = try builder.joinBodies([floor, ramp], mode: .sewnSheet)
        let flat = try face(of: sheet, in: builder) { surface in
            guard case let .bSpline(spline) = surface else { return false }
            return spline.controlPoints.joined().allSatisfy { $0.z == 0 }
        }
        let refit = try builder.rebuildFaces(target: sheet, faces: [flat], method: .square(SquareRefit(
            order: .tangent, angularAllowance: 1e-3
        )))
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let sheets = try refitted(refit, in: evaluated)
        // Level where the ramp leaves it, the floor stays flat.
        let floorSheet = try #require(sheets.first { $0.controlPoints.joined().allSatisfy { $0.y >= -1e-12 } })
        #expect(floorSheet.controlPoints.joined().allSatisfy { abs($0.z) < 1e-9 })
    }
}
