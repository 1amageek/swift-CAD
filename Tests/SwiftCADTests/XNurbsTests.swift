import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// XNURBS: an octagon filled flat by one trimmed sheet, a non-planar pentagon spanned smoothly
/// within its tolerances, a plate's square hole filled tangent to the plate, Quad sided as
/// Square's sheet at the Quality's spans, unreachable tolerances refused, and the round trip.
@Suite("XNURBS")
struct XNurbsTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "xnurbs"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func sheet(of feature: FeatureID, in evaluated: EvaluatedDocument) throws -> (face: Face, surface: BSplineSurface3D) {
        let face = try #require(evaluated.subshapes.entries.compactMap { key, value -> Face? in
            guard key.featureID == feature, case let .face(id) = value else { return nil }
            return evaluated.brep.faces[id]
        }.first)
        guard case let .bSpline(surface)? = evaluated.brep.geometry.surfaces[face.surfaceID] else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: nil, message: "An XNURBS sheet is a B-spline.")
        }
        return (face, surface)
    }

    /// Lines through `corners` in order, closing, each a sketch on z = `heights[k]` planes joined by
    /// spatial lines: a polygon whose corners sit at their heights.
    private func polygon(_ builder: inout DocumentBuilder, _ corners: [(Double, Double, Double)]) throws -> [FeatureID] {
        try corners.indices.map { k in
            let (a, b) = (corners[k], corners[(k + 1) % corners.count])
            let start = Point3D(x: a.0, y: a.1, z: a.2), end = Point3D(x: b.0, y: b.1, z: b.2)
            let along = end - start
            // The line's own vertical plane, its sketch x along the line's horizontal run.
            let horizontal = Vector3D(x: along.x, y: along.y, z: 0)
            let normal = try Vector3D(x: -horizontal.y, y: horizontal.x, z: 0).normalized(tolerance: 1e-12)
            let plane = Plane3D(origin: start, normal: normal)
            let frame = try Surface3D.plane(plane).parameterProjection(of: end, tolerance: .standard)
            return try builder.sketch(on: .plane(plane)) { $0.line(from: point(0, 0), to: point(frame.u, frame.v)) }.featureID
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func anOctagonIsFilledFlatByOneTrimmedSheet() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (s, c) = (0.02, 0.006)
        let corners = [(c, 0.0), (s - c, 0.0), (s, c), (s, s - c), (s - c, s), (c, s), (0.0, s - c), (0.0, c)]
        let lines = try corners.indices.map { k in
            let (a, b) = (corners[k], corners[(k + 1) % corners.count])
            return try builder.sketch(on: .xy) { $0.line(from: point(a.0, a.1), to: point(b.0, b.1)) }.featureID
        }
        let fill = try builder.xnurbs(XNurbsFeature(boundaries: lines.map { SquareSide(curve: CurveSectionReference(featureID: $0)) }))
        let evaluated = try evaluate(builder)
        let (face, surface) = try sheet(of: fill, in: evaluated)
        #expect(surface.controlPoints.joined().allSatisfy { abs($0.z) < 1e-12 })
        #expect(face.loops.count == 1 && evaluated.brep.loops[face.loops[0]]?.coedges.count == 8)
    }

    @Test(.timeLimit(.minutes(2)))
    func oneClosedCurveFramesTheSheetOnItsOwn() throws {
        // A circle of 10 mm: one closed boundary, filled flat as its four quarters.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let circle = try builder.sketch(on: .xy) { _ = $0.circle(center: point(0, 0), radius: length(0.01)) }.featureID
        let fill = try builder.xnurbs(XNurbsFeature(boundaries: [SquareSide(curve: CurveSectionReference(featureID: circle))]))
        let evaluated = try evaluate(builder)
        let (face, surface) = try sheet(of: fill, in: evaluated)
        #expect(surface.controlPoints.joined().allSatisfy { abs($0.z) < 1e-12 })
        #expect(face.loops.count == 1 && evaluated.brep.loops[face.loops[0]]?.coedges.count == 4)
        // An open curve alone frames nothing.
        var open = DocumentBuilder(units: .meters, tolerance: .standard)
        let line = try open.sketch(on: .xy) { $0.line(from: point(0, 0), to: point(0.01, 0)) }.featureID
        _ = try open.xnurbs(XNurbsFeature(boundaries: [SquareSide(curve: CurveSectionReference(featureID: line))]))
        #expect(throws: (any Error).self) { _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try open.build(name: "x")) }
    }

    @Test(.timeLimit(.minutes(3)))
    func aNonPlanarPentagonIsSpannedWithinItsTolerances() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let corners: [(Double, Double, Double)] = (0..<5).map { k in
            let angle = 2 * Double.pi * Double(k) / 5
            return (0.01 * cos(angle), 0.01 * sin(angle), k % 2 == 0 ? 0.002 : -0.001)
        }
        let lines = try polygon(&builder, corners)
        let fill = try builder.xnurbs(XNurbsFeature(boundaries: lines.map { SquareSide(curve: CurveSectionReference(featureID: $0)) }))
        let evaluated = try evaluate(builder)
        let (face, surface) = try sheet(of: fill, in: evaluated)
        // Each edge lies on the sheet and within 0.01 mm of its line.
        for coedge in evaluated.brep.loops[face.loops[0]]?.coedges ?? [] {
            let edge = try #require(evaluated.brep.edges[coedge.edgeID])
            let curve = try #require(evaluated.brep.geometry.curves[edge.curveID])
            let trim = try #require(edge.trim)
            let start = try #require(evaluated.brep.vertices[edge.startVertexID]?.point)
            let end = try #require(evaluated.brep.vertices[edge.endVertexID]?.point)
            for k in 0...8 {
                let point = try curve.point(at: trim.startParameter + (trim.endParameter - trim.startParameter) * Double(k) / 8,
                                            tolerance: .standard)
                let along = end - start
                let fraction = max(0, min(1, (point - start).dot(along) / along.dot(along)))
                #expect((point - (start + along * fraction)).length < 1e-5)
            }
        }
        // The interior is one smooth bicubic sheet bending between the corners.
        #expect(surface.uDegree == 3 && surface.controlPoints.joined().contains { abs($0.z) > 1e-4 })
    }

    @Test(.timeLimit(.minutes(3)))
    func aPlatesSquareHoleIsFilledTangentToThePlate() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let plate = try builder.box(width: length(0.03), depth: length(0.03), height: length(0.005))
        let hole = try builder.box(placement: PrimitivePlacement(origin: Point3D(x: 0.01, y: 0.01, z: -0.001), axis: .unitZ, referenceDirection: .unitX),
                                   width: length(0.01), depth: length(0.01), height: length(0.007))
        let cut = try builder.boolean(targets: [plate], tool: hole, operation: .difference)
        let before = try evaluate(builder)
        let edges = try before.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == cut, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let a = before.brep.vertices[edge.startVertexID]?.point, let b = before.brep.vertices[edge.endVertexID]?.point else { return nil }
            let inside = [a, b].allSatisfy { abs($0.z - 0.005) < 1e-12 && $0.x > 0.009 && $0.x < 0.021 && $0.y > 0.009 && $0.y < 0.021 }
            return inside ? key : nil
        }.sorted().map { try builder.stableSubshape($0) }
        #expect(edges.count == 4)
        let curves = try edges.map { try builder.edgeCurves(of: cut, edges: [$0]) }
        let fill = try builder.xnurbs(XNurbsFeature(boundaries: zip(curves, edges).map { curve, edge in
            SquareSide(curve: CurveSectionReference(featureID: curve),
                       continuity: SurfaceEdgeContinuity(source: cut, bodyRole: .body, edge: edge, order: .tangent))
        }))
        let evaluated = try evaluate(builder)
        let (_, surface) = try sheet(of: fill, in: evaluated)
        // Tangent to the plate's top all round, the fill is that plane.
        #expect(surface.controlPoints.joined().allSatisfy { abs($0.z - 0.005) < 1e-9 })
    }

    /// Patch Faces Multiple at G1: a plate's square hole with a guide from one corner to the
    /// opposite one, leaving the plate flat and unbent (as a sheet tangent to the plate along both
    /// edges at a corner must) and rising 1 mm at its middle. One sheet tangent to the plate all
    /// round passes over the guide, divided along it into two faces.
    @Test(.timeLimit(.minutes(4)))
    func aGuideDividesATangentFillOfAPlatesHoleIntoTwoFaces() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let plate = try builder.box(width: length(0.03), depth: length(0.03), height: length(0.005))
        let hole = try builder.box(placement: PrimitivePlacement(origin: Point3D(x: 0.01, y: 0.01, z: -0.001), axis: .unitZ, referenceDirection: .unitX),
                                   width: length(0.01), depth: length(0.01), height: length(0.007))
        let cut = try builder.boolean(targets: [plate], tool: hole, operation: .difference)
        let before = try evaluate(builder)
        let top = 0.005
        let edges = try before.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == cut, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let a = before.brep.vertices[edge.startVertexID]?.point, let b = before.brep.vertices[edge.endVertexID]?.point else { return nil }
            let inside = [a, b].allSatisfy { abs($0.z - top) < 1e-12 && $0.x > 0.009 && $0.x < 0.021 && $0.y > 0.009 && $0.y < 0.021 }
            return inside ? key : nil
        }.sorted().map { try builder.stableSubshape($0) }
        #expect(edges.count == 4)
        let curves = try edges.map { try builder.edgeCurves(of: cut, edges: [$0]) }
        // In the upright plane through the hole's diagonal (sketch x along it, y up): a sextic
        // Bezier flat and straight at both ends, its middle 1 mm up (20/64 of its middle control
        // point's height).
        let diagonal = 0.01 * 2.squareRoot()
        let rise = 0.001
        let guide = try builder.sketch(on: .plane(Plane3D(origin: Point3D(x: 0.01, y: 0.01, z: top),
                                                          normal: Vector3D(x: 1, y: -1, z: 0) * (1 / 2.squareRoot())))) {
            _ = $0.spline(SketchSpline(controlPoints: (0...6).map { k in
                point(Double(k) / 6 * diagonal, k == 3 ? rise * 64 / 20 : 0)
            }, degree: 6))
        }.featureID
        let fill = try builder.xnurbs(XNurbsFeature(boundaries: zip(curves, edges).map { curve, edge in
            SquareSide(curve: CurveSectionReference(featureID: curve),
                       continuity: SurfaceEdgeContinuity(source: cut, bodyRole: .body, edge: edge, order: .tangent))
        }, guides: [CurveSectionReference(featureID: guide)], dividesAlongGuides: true))
        let evaluated = try evaluate(builder)
        let faces = evaluated.subshapes.entries.compactMap { key, value -> Face? in
            guard key.featureID == fill, case let .face(id) = value else { return nil }
            return evaluated.brep.faces[id]
        }
        #expect(faces.count == 2)
        // Both faces lie on the one sheet.
        let surface = try #require(evaluated.brep.geometry.surfaces[faces[0].surfaceID])
        #expect(evaluated.brep.geometry.surfaces[faces[1].surfaceID] == surface)
        // Tangent to the plate along each of the hole's edges, within the angle tolerance.
        var rimSamples = 0
        for face in faces {
            for coedge in face.loops.flatMap({ evaluated.brep.loops[$0]?.coedges ?? [] }) {
                let edge = try #require(evaluated.brep.edges[coedge.edgeID])
                let curve = try #require(evaluated.brep.geometry.curves[edge.curveID])
                let trim = try #require(edge.trim)
                let points = try (0...8).map { k in
                    try curve.point(at: trim.startParameter + (trim.endParameter - trim.startParameter) * Double(k) / 8, tolerance: .standard)
                }
                guard points.allSatisfy({ abs($0.z - top) < 1e-5 }) else { continue }
                for point in points {
                    let uv = try surface.parameterProjection(of: point, tolerance: .standard)
                    let normal = try surface.normal(u: uv.u, v: uv.v, tolerance: .standard)
                    #expect(acos(min(1, abs(normal.z))) <= 0.1 * Double.pi / 180 + 1e-9, "\(normal) at \(point)")
                    rimSamples += 1
                }
            }
        }
        #expect(rimSamples == 4 * 9)
        // The faces share the edge along the guide, passing near its middle.
        let shared = faces.map { face in Set(face.loops.flatMap { evaluated.brep.loops[$0]?.coedges.map(\.edgeID) ?? [] }) }
        let seam = try #require(shared[0].intersection(shared[1]).first)
        let seamEdge = try #require(evaluated.brep.edges[seam])
        let seamCurve = try #require(evaluated.brep.geometry.curves[seamEdge.curveID])
        let apex = Point3D(x: 0.015, y: 0.015, z: top + rise)
        let miss = try (0...200).map { k -> Double in
            let t = seamEdge.trim!.startParameter + (seamEdge.trim!.endParameter - seamEdge.trim!.startParameter) * Double(k) / 200
            return (try seamCurve.point(at: t, tolerance: .standard) - apex).length
        }.min() ?? .infinity
        #expect(miss < 2e-4, "\(miss)")
    }

    @Test(.timeLimit(.minutes(1)))
    func dividingAlongGuidesRoundTripsAndNeedsGuides() throws {
        let sides = [SquareSide(curve: CurveSectionReference(featureID: FeatureID())), SquareSide(curve: CurveSectionReference(featureID: FeatureID()))]
        let divided = XNurbsFeature(boundaries: sides, guides: [CurveSectionReference(featureID: FeatureID())], dividesAlongGuides: true)
        #expect(try JSONDecoder().decode(XNurbsFeature.self, from: try JSONEncoder().encode(divided)) == divided)
        #expect(throws: FeatureEvaluationError.self) { try XNurbsFeature(boundaries: sides, dividesAlongGuides: true).validate() }
    }

    @Test(.timeLimit(.minutes(2)))
    func quadSidedIsSquaresSheetAtItsQualitysSpans() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let corners = [(0.0, 0.0), (0.02, 0.0), (0.02, 0.02), (0.0, 0.02)]
        let lines = try corners.indices.map { k in
            let (a, b) = (corners[k], corners[(k + 1) % corners.count])
            return try builder.sketch(on: .xy) { $0.line(from: point(a.0, a.1), to: point(b.0, b.1)) }.featureID
        }
        let quad = try builder.xnurbs(XNurbsFeature(boundaries: lines.map { SquareSide(curve: CurveSectionReference(featureID: $0)) },
                                                    quadSided: true, quality: .high))
        let evaluated = try evaluate(builder)
        let (face, surface) = try sheet(of: quad, in: evaluated)
        #expect(Set(surface.uKnots.filter { $0 > 0 && $0 < 1 }).count == 5 && Set(surface.vKnots.filter { $0 > 0 && $0 < 1 }).count == 5)
        #expect(evaluated.brep.loops[face.loops[0]]?.coedges.count == 4)
    }

    @Test(.timeLimit(.minutes(3)))
    func unreachableTolerancesAreRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let corners: [(Double, Double, Double)] = (0..<5).map { k in
            let angle = 2 * Double.pi * Double(k) / 5
            return (0.01 * cos(angle), 0.01 * sin(angle), k % 2 == 0 ? 0.004 : -0.003)
        }
        let lines = try polygon(&builder, corners)
        _ = try builder.xnurbs(XNurbsFeature(boundaries: lines.map { SquareSide(curve: CurveSectionReference(featureID: $0)) },
                                             quality: .max, positionTolerance: 1e-14))
        #expect(throws: KernelError.self) { try evaluate(builder) }
    }

    @Test(.timeLimit(.minutes(1)))
    func anXNurbsRoundTrips() throws {
        let feature = XNurbsFeature(boundaries: [SquareSide(curve: CurveSectionReference(featureID: FeatureID())),
                                                 SquareSide(curve: CurveSectionReference(featureID: FeatureID()))],
                                    guides: [CurveSectionReference(featureID: FeatureID())], quadSided: true, flatness: 0.97,
                                    boundaryFlow: .next, quality: .high, satisfiesTolerances: false)
        let decoded = try JSONDecoder().decode(XNurbsFeature.self, from: try JSONEncoder().encode(feature))
        #expect(decoded == feature)
    }
}
