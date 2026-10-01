import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Fillet Shell's shapes round a box's edge with a conic, a chordal arc or a curvature-continuous
/// quintic: the volume removed is the cross-section's area beyond the curve times the edge's length.
@Suite("Fillet shapes")
struct FilletShapeTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// A 20 mm box with its first generated edge filleted; the edge's length and the evaluated body.
    private func fillet(shape: FilletShape, tension: Double?, distance: Double) throws -> (EvaluatedDocument, Double) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let edge = try builder.stableSubshape(generatedBy: box, selector: .generated(role: .edge, index: 0))
        _ = try builder.fillet(target: box, edges: [edge], radius: length(distance), shape: shape, tension: tension)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "fillet"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return (evaluated, 0.02)
    }

    /// The area between a corner's two sides and the curve through `points` with `weights`,
    /// by Green's theorem over the rational Bézier and its two straight sides.
    private func removedArea(_ points: [(Double, Double)], weights: [Double]) -> Double {
        let n = points.count - 1
        func binomial(_ k: Int) -> Double { (0..<k).reduce(1.0) { $0 * Double(n - $1) / Double($1 + 1) } }
        func point(_ t: Double) -> (Double, Double) {
            var x = 0.0, y = 0.0, w = 0.0
            for (k, p) in points.enumerated() {
                let b = binomial(k) * pow(t, Double(k)) * pow(1 - t, Double(n - k)) * weights[k]
                x += b * p.0; y += b * p.1; w += b
            }
            return (x / w, y / w)
        }
        // Signed area of the closed loop corner → first contact → curve → second contact → corner.
        var area = 0.0
        let steps = 20_000
        var previous = point(0)
        for step in 1...steps {
            let next = point(Double(step) / Double(steps))
            area += previous.0 * next.1 - next.0 * previous.1
            previous = next
        }
        return abs(0.5 * area)
    }

    @Test(.timeLimit(.minutes(2)))
    func conicChordalAndCurvatureShapesRemoveTheirCrossSections() throws {
        let d = 0.004, box = 0.02 * 0.02 * 0.02
        // Corner at the origin, the first face along +x, the second along +y.
        let cases: [(FilletShape, Double?, [(Double, Double)], [Double])] = [
            (.conic, 0.5, [(d, 0), (0, 0), (0, d)], [1, 1, 1]),
            (.conic, 0.3, [(d, 0), (0, 0), (0, d)], [1, 0.3 / 0.7, 1]),
            (.chordal, nil, [(d / 2.0.squareRoot(), 0), (0, 0), (0, d / 2.0.squareRoot())], [1, 0.5.squareRoot(), 1]),
            (.curvature, 1, [(d, 0), (2 * d / 3, 0), (d / 3, 0), (0, d / 3), (0, 2 * d / 3), (0, d)], Array(repeating: 1, count: 6)),
        ]
        for (shape, tension, points, weights) in cases {
            let (evaluated, edgeLength) = try fillet(shape: shape, tension: tension, distance: d)
            // The removed region: the corner between the sides and the curve.
            let expected = box - removedArea(points, weights: weights) * edgeLength
            let volume = try evaluated.brep.volume(tolerance: .standard)
            #expect(abs(volume - expected) < 5e-12, "\(shape) \(String(describing: tension)): \(volume) vs \(expected)")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func shapesTakeOneEdgeAndTheirOwnTension() throws {
        #expect(throws: KernelError.self) {
            try FilletFeature(target: FilletTargetReference(featureID: FeatureID()), edges: [], radius: length(0.004),
                              allEdges: true, shape: .conic).validate()
        }
        #expect(throws: KernelError.self) { _ = try fillet(shape: .chordal, tension: 0.4, distance: 0.004) }
        #expect(throws: KernelError.self) { _ = try fillet(shape: .conic, tension: 1, distance: 0.004) }
    }

    @Test(.timeLimit(.minutes(2)))
    func aFullFilletRoundsARibsTopAcrossItsWidth() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A rib 20 mm wide, 40 mm long and 30 mm tall; its top's two long edges bound the round.
        let rib = try builder.box(width: length(0.02), depth: length(0.04), height: length(0.03))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rib"))
        let topEdges = try before.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == rib, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point,
                  abs(start.z - end.z) < 1e-12, abs(start.x - end.x) < 1e-12, abs(start.y - end.y) > 0.03 else { return nil }
            return (try before.brep.vertices[edge.startVertexID].map { abs($0.point.z - start.z) } ?? 1) < 1e-12 ? key : nil
        }
        let top = topEdges.filter { key in
            guard case let .edge(id) = before.subshapes.entries[key], let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return start.z > 0.02
        }
        #expect(top.count == 2)
        let edges = try top.map { try builder.stableSubshape($0) }
        // A radius other than the half width the faces fix is refused.
        var stated = builder
        _ = try stated.fillet(target: rib, edges: edges, radius: length(0.009), shape: .full)
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try stated.build(name: "rib"))
        }
        _ = try builder.fillet(target: rib, edges: edges, radius: length(0.01), shape: .full)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rib"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The top 10 mm of the cross-section becomes a half disc of radius 10 mm.
        let r = 0.01
        let expected = 0.02 * 0.04 * 0.03 - 0.04 * (2 * r * r - Double.pi * r * r / 2)
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
        // The highest point is the top's middle line, still at 30 mm.
        let highest = evaluated.brep.vertices.values.map(\.point.z).max() ?? 0
        #expect(highest < 0.03 - 1e-6)

        // Two edges that do not bound one face are refused.
        var wrong = DocumentBuilder(units: .meters, tolerance: .standard)
        let other = try wrong.box(width: length(0.02), depth: length(0.04), height: length(0.03))
        let twoEdges = try [0, 1].map { try wrong.stableSubshape(generatedBy: other, selector: .generated(role: .edge, index: $0)) }
        _ = try wrong.fillet(target: other, edges: twoEdges, radius: length(0.01), shape: .full)
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try wrong.build(name: "rib"))
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aFullFilletRoundsADraftedRibsTopTangentToItsSlopingSides() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A rib 30 mm wide at its foot and 20 mm at its 30 mm top, 40 mm long along Y (on the plane
        // across Y sketch x is -x and sketch y is z).
        let outline: [(Double, Double)] = [(-0.015, 0), (0.015, 0), (0.01, 0.03), (-0.01, 0.03)]
        let sketch = try builder.sketch(on: .plane(Plane3D(origin: .origin, normal: .unitY))) { sketch in
            for (start, end) in zip(outline, outline.dropFirst() + outline.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(-start.0), y: length(start.1)), to: SketchPoint(x: length(-end.0), y: length(end.1)))
            }
        }.featureID
        let rib = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.04))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rib"))
        let top = try before.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == rib, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point,
                  abs(start.z - 0.03) < 1e-12, abs(end.z - 0.03) < 1e-12, abs(start.y - end.y) > 0.03 else { return nil }
            return key
        }
        #expect(top.count == 2)
        let edges = try top.map { try builder.stableSubshape($0) }
        // The corners' interior angle α: cos α = -5/√925; the round's radius 10 / cot(α/2) mm.
        let alpha = acos(-5 / 925.0.squareRoot())
        let r = 0.01 / (1 / tan(alpha / 2))
        #expect(abs(try FullFilletRadius().radius(target: rib, edges: (edges[0], edges[1]), in: before) - r) < 1e-12)
        _ = try builder.fillet(target: rib, edges: edges, radius: length(r), shape: .full)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rib"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // Each corner loses the kite of its two 10 mm tangents less the arc's sector.
        let removed = 2 * (0.01 * r - (Double.pi - alpha) * r * r / 2)
        let expected = (0.03 + 0.02) / 2 * 0.03 * 0.04 - removed * 0.04
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aSheetsBendRoundsIntoAQuarterCylinder() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // An L of a 40 mm floor (z = 0, y from 0 to 40 mm) and wall (y = 0, z from 0 to 40 mm) joined
        // along x; on the ZX plane sketch x is z and sketch y is x.
        func square(on plane: SketchPlane, _ corners: [(Double, Double)]) throws -> FeatureID {
            let lines = try corners.indices.map { index in
                try builder.sketch(on: plane) { sketch in
                    let (start, end) = (corners[index], corners[(index + 1) % corners.count])
                    _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
                }.featureID
            }
            return try builder.patch(curves: lines.map { CurveSectionReference(featureID: $0) })
        }
        let floor = try square(on: .xy, [(0, 0), (0.04, 0), (0.04, 0.04), (0, 0.04)])
        let wall = try square(on: .zx, [(0, 0), (0, 0.04), (0.04, 0.04), (0.04, 0)])
        let sheet = try builder.joinBodies([floor, wall], mode: .sewnSheet)
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "bend"))
        let bend = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == sheet, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.y) < 1e-12 && abs($0.z) < 1e-12 }
        }?.key)
        let r = 0.005
        var g2Builder = builder
        var chamferBuilder = builder
        let fillet = try builder.fillet(target: sheet, edges: [try builder.stableSubshape(bend)], radius: length(r))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "bend"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let body = try #require(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == fillet, case let .body(id) = value else { return nil }
            return id
        }.first)
        #expect(evaluated.brep.bodies[body]?.kind == .sheet)
        let faces = try BodyTopologyScope(bodyID: body, model: evaluated.brep).references.compactMap { reference -> FaceID? in
            if case let .face(id) = reference { return id }
            return nil
        }
        #expect(faces.count == 3)
        // The round meets the floor at y = r and the wall at z = r, passing (·, r − r/√2, r − r/√2).
        let round = try #require(faces.compactMap { id -> Surface3D? in
            guard let face = evaluated.brep.faces[id], let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
                  case .bSpline = surface else { return nil }
            return surface
        }.first)
        let middle = r - r / 2.0.squareRoot()
        #expect(try round.parameterProjection(of: Point3D(x: 0.02, y: middle, z: middle), tolerance: .standard).residual < 1e-9)
        let points = evaluated.brep.vertices.values.map(\.point)
        #expect(points.contains { abs($0.y - r) < 1e-12 && abs($0.z) < 1e-12 })
        #expect(points.contains { abs($0.z - r) < 1e-12 && abs($0.y) < 1e-12 })
        #expect(points.allSatisfy { !(abs($0.y) < 1e-9 && abs($0.z) < 1e-9) })

        // A G2 blend of the same bend is a sheet too, flat across both contacts.
        let blend = try g2Builder.g2Blend(target: sheet, edges: [try g2Builder.stableSubshape(bend)], distance: length(r))
        let blended = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try g2Builder.build(name: "bend"))
        try blended.brep.validate(level: .exact, tolerance: .standard)
        let blendBody = try #require(blended.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == blend, case let .body(id) = value else { return nil }
            return id
        }.first)
        #expect(blended.brep.bodies[blendBody]?.kind == .sheet)

        // A chamfer of the bend: a flat strip from y = r on the floor to z = r on the wall.
        let chamfer = try chamferBuilder.chamfer(target: sheet, edges: [try chamferBuilder.stableSubshape(bend)], distance: length(r))
        let chamfered = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try chamferBuilder.build(name: "bend"))
        try chamfered.brep.validate(level: .exact, tolerance: .standard)
        let chamferBody = try #require(chamfered.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == chamfer, case let .body(id) = value else { return nil }
            return id
        }.first)
        #expect(chamfered.brep.bodies[chamferBody]?.kind == .sheet)
        let chamferFaces = try BodyTopologyScope(bodyID: chamferBody, model: chamfered.brep).references.compactMap { reference -> FaceID? in
            if case let .face(id) = reference { return id }
            return nil
        }
        #expect(chamferFaces.count == 3)
        // The strip's control points all on the plane y + z = r.
        let splines = chamferFaces.compactMap { id -> BSplineSurface3D? in
            guard let face = chamfered.brep.faces[id], case let .bSpline(spline)? = chamfered.brep.geometry.surfaces[face.surfaceID] else { return nil }
            return spline
        }
        let strip = try #require(splines.first)
        #expect(strip.controlPoints.joined().allSatisfy { abs($0.y + $0.z - r) < 1e-12 })
    }
}
