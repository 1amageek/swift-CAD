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
            target: flat, targetEdge: target, reference: arch, referenceEdge: reference, continuity: continuity, blendRows: 0
        )
        let evaluated = try evaluate(builder)
        let result = try surface(of: aligned, in: evaluated)
        let source = try surface(of: arch, in: evaluated)
        // Without a blend the far edge stays where it was.
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

    @Test(.timeLimit(.minutes(2)))
    func aBlendAsLongAsTheSheetMovesItsFarEdgeToo() throws {
        // The flat sheet has two rows: a G0 alignment sets the first, and one blended row is all
        // the rest, so the whole sheet follows the near edge onto the arch (Plasticity's "fully
        // adjusts"), its net keeping its two rows.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (arch, flat, target, reference) = try archAndFlat(&builder)
        let aligned = try builder.alignSurface(
            target: flat, targetEdge: target, reference: arch, referenceEdge: reference, continuity: .positional, blendRows: 1
        )
        let evaluated = try evaluate(builder)
        _ = arch
        guard case let .bSpline(result) = try surface(of: aligned, in: evaluated) else { Issue.record("A B-spline sheet."); return }
        #expect(result.controlPoints.allSatisfy { $0.count == 2 } || result.controlPoints.count == 2)
        let farEnd = try Surface3D.bSpline(result).differentialGeometry(u: 1, v: 0, tolerance: .standard).position
        #expect((farEnd - Point3D(x: 2 * s - 0.005, y: 0, z: 0)).length < 1e-9, "\(farEnd)")
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
    func aPartialAlignmentAttachesTheWholeEdgeToAStretchOfTheReference() throws {
        // Partial 0.3 to 0.7: the flat sheet's whole edge funnels onto the middle of the arch's
        // edge (y from 6 to 14 mm), tangent to the arch there.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (arch, flat, target, reference) = try archAndFlat(&builder)
        let aligned = try builder.alignSurface(
            target: flat, targetEdge: target, reference: arch, referenceEdge: reference, continuity: .tangentPlane,
            partialStart: 0.3, partialEnd: 0.7, layout: SurfaceControlLayout(uDegree: 3, vDegree: 3, uSpans: 4, vSpans: 8)
        )
        let evaluated = try evaluate(builder)
        let result = try surface(of: aligned, in: evaluated)
        guard case let .bSpline(refitted) = result else { Issue.record("An aligned sheet is a B-spline surface."); return }
        #expect(refitted.uDegree == 3 && refitted.vDegree == 3)
        let source = try surface(of: arch, in: evaluated)
        for (v, along) in [(0.0, 0.3), (0.5, 0.5), (1.0, 0.7)] {
            let here = try result.differentialGeometry(u: 0, v: v, tolerance: .standard)
            let there = try source.differentialGeometry(u: 1, v: along, tolerance: .standard)
            #expect((here.position - there.position).length < 1e-9, "\(v)")
            #expect(here.normal.cross(there.normal).length < 1e-9)
        }
        #expect(throws: (any Error).self) {
            var refused = builder
            _ = try refused.alignSurface(target: flat, targetEdge: target, reference: arch, referenceEdge: reference,
                                         partialStart: 0.6, partialEnd: 0.4)
            _ = try evaluate(refused)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func blendedRowsWithoutInputShapeInfluenceRunStraight() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (arch, _, _, reference) = try archAndFlat(&builder)
        // A flat sheet of six rows across, so two blended rows leave the far ones alone.
        let xs = (0...5).map { s + 0.005 + (s - 0.005) * Double($0) / 5 }
        let flat = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 0.2, 0.4, 0.6, 0.8, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, s].map { y in xs.map { Point3D(x: $0, y: y, z: 0) } }
        ))
        let target = try edge(of: flat, atX: s + 0.005, in: builder)
        let aligned = try builder.alignSurface(
            target: flat, targetEdge: target, reference: arch, referenceEdge: reference, continuity: .tangentPlane,
            blendRows: 2, inputShapeInfluence: 0
        )
        let result = try surface(of: aligned, in: try evaluate(builder))
        guard case let .bSpline(surface) = result else { Issue.record("An aligned sheet is a B-spline surface."); return }
        // Rows 2 and 3 lie on the segment from the last row set (1) to the first row left (4),
        // and the net keeps its six rows.
        #expect(surface.controlPoints.allSatisfy { $0.count == 6 })
        for row in surface.controlPoints {
            let chord = row[4] - row[1]
            for k in [2, 3] { #expect((row[k] - row[1]).cross(chord).length < 1e-12) }
        }
    }
}

/// Align Surface's boundary flows over a sheared reference, whose own cross direction leans along
/// the edge: Normal meets the edge square, every flow stays tangent (and curvature) continuous.
@Suite("Align Surface flows")
struct SurfaceAlignFlowTests {
    private let s = 0.02

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "flow"))
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
        let face = try #require(evaluated.subshapes.entries.compactMap { key, value -> Face? in
            guard key.featureID == feature, case let .face(id) = value else { return nil }
            return evaluated.brep.faces[id]
        }.first)
        return try #require(evaluated.brep.geometry.surfaces[face.surfaceID])
    }

    @Test(.timeLimit(.minutes(2)), arguments: [SquareFitOptions.BoundaryFlow.normal, .natural, .adjacent, .next])
    func everyFlowStaysCurvatureContinuous(flow: SquareFitOptions.BoundaryFlow) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // An arch across x whose rows shift along y as they rise: its cross direction leans along the edge.
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: s / 2, y: y + s / 4, z: s / 2), Point3D(x: s, y: y + s / 2, z: 0)] }
        let arch = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(s)]
        ))
        let flat = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: s + 0.005, y: s / 2, z: 0), Point3D(x: 2 * s, y: s / 2, z: 0)],
                            [Point3D(x: s + 0.005, y: 1.5 * s, z: 0), Point3D(x: 2 * s, y: 1.5 * s, z: 0)]]
        ))
        let aligned = try builder.alignSurface(
            target: flat, targetEdge: try edge(of: flat, atX: s + 0.005, in: builder), reference: arch,
            referenceEdge: try edge(of: arch, atX: s, in: builder), continuity: .curvature, blendRows: 1, boundaryFlow: flow
        )
        let evaluated = try evaluate(builder)
        let analysis = try SurfaceAlignAnalyzer().analyze(aligned, in: evaluated)
        #expect(analysis.isWithin && analysis.curvature != nil, "\(analysis)")
        let result = try surface(of: aligned, in: evaluated), source = try surface(of: arch, in: evaluated)
        for v in [0.1, 0.5, 0.9] {
            let there = try source.differentialGeometry(u: 1, v: v, tolerance: .standard)
            let projected = try result.parameterProjection(of: there.position, tolerance: .standard)
            let here = try result.differentialGeometry(u: projected.u, v: projected.v, tolerance: .standard)
            #expect(projected.residual < 1e-9)
            #expect(here.normal.cross(there.normal).length < 1e-8)
            // G2: both surfaces bend alike across the edge, along the target's cross direction.
            let across = abs(projected.u) < 1e-9 || abs(projected.u - 1) < 1e-9 ? here.tangentU : here.tangentV
            func curvature(_ jet: Surface3D.DifferentialGeometry, along direction: Vector3D) -> Double {
                let (su, sv) = (jet.tangentU, jet.tangentV)
                let (e, f, g) = (su.dot(su), su.dot(sv), sv.dot(sv))
                let (p, q) = (direction.dot(su), direction.dot(sv))
                let determinant = e * g - f * f
                let (a, b) = ((g * p - f * q) / determinant, (e * q - f * p) / determinant)
                let normal = jet.normal.dot(here.normal) >= 0 ? jet.normal : jet.normal * -1
                return (jet.secondDerivativeUU.dot(normal) * a * a + 2 * jet.secondDerivativeUV.dot(normal) * a * b
                    + jet.secondDerivativeVV.dot(normal) * b * b) / (e * a * a + 2 * f * a * b + g * b * b)
            }
            #expect(abs(curvature(here, along: across) - curvature(there, along: across)) < 1e-4, "\(curvature(here, along: across)) \(curvature(there, along: across))")
            // Normal: the target's cross direction meets the edge square.
            if flow == .normal {
                let across = abs(projected.u) < 1e-9 || abs(projected.u - 1) < 1e-9 ? here.tangentU : here.tangentV
                let along = abs(projected.u) < 1e-9 || abs(projected.u - 1) < 1e-9 ? here.tangentV : here.tangentU
                #expect(abs(across.dot(along)) / (across.length * along.length) < 1e-3)
            }
        }
    }

    /// The analysis's samples along the edge: none with a gap or a normal turn once aligned at G1
    /// or G2; at G2 the sheet bends across the edge as the arch does, at G1 it need not.
    @Test(.timeLimit(.minutes(2)), arguments: [SurfaceContinuityLevel.tangentPlane, .curvature])
    func theSamplesShowTheGapTurnAndBendAlongTheEdge(continuity: SurfaceContinuityLevel) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: s / 2, y: y, z: s / 2), Point3D(x: s, y: y, z: 0)] }
        let arch = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(s)]
        ))
        let flat = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: s + 0.005, y: 0, z: 0), Point3D(x: 2 * s, y: 0, z: 0)],
                            [Point3D(x: s + 0.005, y: s, z: 0), Point3D(x: 2 * s, y: s, z: 0)]]
        ))
        let aligned = try builder.alignSurface(
            target: flat, targetEdge: try edge(of: flat, atX: s + 0.005, in: builder), reference: arch,
            referenceEdge: try edge(of: arch, atX: s, in: builder), continuity: continuity, blendRows: 1
        )
        let samples = try SurfaceAlignAnalyzer().samples(aligned, in: try evaluate(builder))
        #expect(samples.count == 32)
        // The arch z = x(1 − x/s) at x = s: slope −1, z″ = −2/s, so it bends by (2/s)/2^{3/2} across.
        let archCurvature = 2 / s / pow(2, 1.5)
        for sample in samples {
            #expect(abs(sample.edgePoint.x - s) < 1e-12 && abs(sample.edgePoint.z) < 1e-12)
            #expect((sample.sheetPoint - sample.edgePoint).length < 1e-9)
            #expect(sample.angle < 1e-6)
            #expect(abs(abs(sample.referenceCurvature) - archCurvature) < 1e-6, "\(sample.referenceCurvature)")
            if continuity == .curvature {
                #expect(abs(sample.sheetCurvature - sample.referenceCurvature) < 1e-3)
            }
        }
    }
}

