import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Align Surface makes a flat sheet's edge follow a curved sheet's edge across a gap: at G0 the
/// edges coincide, at G1 the sheets share tangent planes along it, at G2 their curvature across it.
@Suite("Align Surface")
struct SurfaceAlignTests {
    private let s = 0.02

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "align"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func edge(of feature: FeatureID, atX x: Double, in builder: DocumentBuilder) throws -> StableSubshapeReference {
        let evaluated = try evaluate(builder)
        let key = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == feature, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  let a = evaluated.brep.vertices[edge.startVertexID]?.point, let b = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
            return abs(a.x - x) < 1e-12 && abs(b.x - x) < 1e-12
        }?.key)
        return try builder.stableSubshape(key)
    }

    private func surface(of feature: FeatureID, in evaluated: EvaluatedDocument) throws -> Surface3D {
        let faceID = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == feature, case .face = value else { return false }
            return true
        }.flatMap { entry -> FaceID? in
            if case let .face(id) = entry.value { return id }
            return nil
        })
        let face = try #require(evaluated.brep.faces[faceID])
        return try #require(evaluated.brep.geometry.surfaces[face.surfaceID])
    }

    @Test(.timeLimit(.minutes(2)), arguments: [SurfaceContinuityLevel.positional, .tangentPlane, .curvature])
    func aFlatSheetFollowsAnArch(continuity: SurfaceContinuityLevel) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A parabolic arch, z = s·u·(1 − u), x = s·u, swept along y.
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: s / 2, y: y, z: s / 2), Point3D(x: s, y: y, z: 0)] }
        let arch = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(s)]
        ))
        // A flat sheet beside it, beyond a gap.
        let gap = 0.005
        let flat = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: s + gap, y: 0, z: 0), Point3D(x: 2 * s, y: 0, z: 0)],
                            [Point3D(x: s + gap, y: s, z: 0), Point3D(x: 2 * s, y: s, z: 0)]]
        ))
        let target = try edge(of: flat, atX: s + gap, in: builder)
        let reference = try edge(of: arch, atX: s, in: builder)
        let aligned = try builder.alignSurface(
            target: flat, targetEdge: target, reference: arch, referenceEdge: reference, continuity: continuity, blendRows: 1
        )
        let evaluated = try evaluate(builder)
        let result = try surface(of: aligned, in: evaluated)
        let source = try surface(of: arch, in: evaluated)
        // The far edge stays where it was.
        let farEnd = try result.differentialGeometry(u: 1, v: 0, tolerance: .standard).position
        #expect((farEnd - Point3D(x: 2 * s, y: 0, z: 0)).length < 1e-9)
        for v in [0.0, 0.3, 0.7, 1.0] {
            let there = try source.differentialGeometry(u: 1, v: v, tolerance: .standard)
            let here = try result.differentialGeometry(u: 0, v: v, tolerance: .standard)
            #expect((here.position - there.position).length < 1e-9)
            if continuity >= .tangentPlane {
                #expect(here.normal.cross(there.normal).length < 1e-9)
            }
            if continuity >= .curvature {
                #expect(abs(here.normalCurvatureU - there.normalCurvatureU) < 1e-6)
            }
        }
    }

    /// The arch and the flat sheet beyond a gap, with the flat sheet's near edge and the arch's far one.
    private func archAndFlat(_ builder: inout DocumentBuilder) throws -> (arch: FeatureID, flat: FeatureID, target: StableSubshapeReference, reference: StableSubshapeReference) {
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: s / 2, y: y, z: s / 2), Point3D(x: s, y: y, z: 0)] }
        let arch = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(s)]
        ))
        let flat = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: s + 0.005, y: 0, z: 0), Point3D(x: 2 * s, y: 0, z: 0)],
                            [Point3D(x: s + 0.005, y: s, z: 0), Point3D(x: 2 * s, y: s, z: 0)]]
        ))
        return (arch, flat, try edge(of: flat, atX: s + 0.005, in: builder), try edge(of: arch, atX: s, in: builder))
    }

    @Test(.timeLimit(.minutes(2)))
    func aPartialAlignmentLeavesTheEdgesEndsAndMeetsInTheMiddle() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (arch, flat, target, reference) = try archAndFlat(&builder)
        let aligned = try builder.alignSurface(
            target: flat, targetEdge: target, reference: arch, referenceEdge: reference, continuity: .tangentPlane,
            partialStart: 0.3, partialEnd: 0.3, layout: SurfaceControlLayout(uDegree: 3, vDegree: 3, uSpans: 4, vSpans: 8)
        )
        let evaluated = try evaluate(builder)
        let result = try surface(of: aligned, in: evaluated)
        guard case let .bSpline(refitted) = result else { Issue.record("An aligned sheet is a B-spline surface."); return }
        #expect(refitted.uDegree == 3 && refitted.vDegree == 3)
        let source = try surface(of: arch, in: evaluated)
        // Both ends stay where the flat sheet's edge was; the middle meets the arch tangentially.
        for v in [0.0, 1.0] {
            let end = try result.differentialGeometry(u: 0, v: v, tolerance: .standard).position
            #expect((end - Point3D(x: s + 0.005, y: v * s, z: 0)).length < 1e-9)
        }
        let here = try result.differentialGeometry(u: 0, v: 0.5, tolerance: .standard)
        let there = try source.differentialGeometry(u: 1, v: 0.5, tolerance: .standard)
        #expect((here.position - there.position).length < 1e-9)
        #expect(here.normal.cross(there.normal).length < 1e-9)
    }

    @Test(.timeLimit(.minutes(2)))
    func blendedRowsWithoutInputShapeInfluenceRunStraight() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (arch, flat, target, reference) = try archAndFlat(&builder)
        let aligned = try builder.alignSurface(
            target: flat, targetEdge: target, reference: arch, referenceEdge: reference, continuity: .tangentPlane,
            blendRows: 2, inputShapeInfluence: 0
        )
        let result = try surface(of: aligned, in: try evaluate(builder))
        guard case let .bSpline(surface) = result else { Issue.record("An aligned sheet is a B-spline surface."); return }
        // Rows 2 and 3 lie on the segment from the last row set (1) to the first row left (4).
        for row in surface.controlPoints {
            let chord = row[4] - row[1]
            for k in [2, 3] { #expect((row[k] - row[1]).cross(chord).length < 1e-12) }
        }
    }
}
