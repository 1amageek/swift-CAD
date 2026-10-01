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

    @Test(.timeLimit(.minutes(2)))
    func aHexagonalPrismsEdgeRoundsAcrossItsHundredTwentyDegrees() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A regular hexagon of 10 mm sides extruded 20 mm; its edges up the sides meet at 120°.
        let corners = (0..<6).map { k in (0.01 * cos(Double(k) * .pi / 3), 0.01 * sin(Double(k) * .pi / 3)) }
        let sketch = try builder.sketch(on: .xy) { sketch in
            for (start, end) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
            }
        }.featureID
        let prism = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "hex"))
        let side = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == prism, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.x - 0.01) < 1e-12 && abs($0.y) < 1e-12 }
        }?.key)
        let r = 0.002
        _ = try builder.fillet(target: prism, edges: [try builder.stableSubshape(side)], radius: length(r))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "hex"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The corner loses the kite of its two r/√3 tangents less the arc's 60° sector.
        let removed = r * r / 3.0.squareRoot() - Double.pi / 6 * r * r
        let expected = 3 * 3.0.squareRoot() / 2 * 0.01 * 0.01 * 0.02 - removed * 0.02
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func anLBlocksInsideCornerFillsWithItsRound() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // An L of 40 mm arms 10 mm thick, extruded 20 mm; its inside corner edge runs up at (10, 10) mm.
        let outline: [(Double, Double)] = [(0, 0), (0.04, 0), (0.04, 0.01), (0.01, 0.01), (0.01, 0.04), (0, 0.04)]
        let sketch = try builder.sketch(on: .xy) { sketch in
            for (start, end) in zip(outline, outline.dropFirst() + outline.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
            }
        }.featureID
        let block = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        let inside = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == block, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.x - 0.01) < 1e-12 && abs($0.y - 0.01) < 1e-12 }
        }?.key)
        let r = 0.004
        _ = try builder.fillet(target: block, edges: [try builder.stableSubshape(inside)], radius: length(r))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The corner gains the r × r square less the quarter disc.
        let expected = (0.04 * 0.01 + 0.03 * 0.01) * 0.02 + (r * r - Double.pi * r * r / 4) * 0.02
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    /// A 20 mm box and the edge of it along X at `y` and `z`.
    private func boxEdges(_ builder: inout DocumentBuilder, _ spots: [(Double, Double)]) throws -> (FeatureID, [StableSubshapeReference]) {
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let edges = try spots.map { y, z in
            let key = try #require(evaluated.subshapes.entries.first { key, value in
                guard key.featureID == box, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                      let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                      let end = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
                return [start, end].allSatisfy { abs($0.y - y) < 1e-12 && abs($0.z - z) < 1e-12 }
            }?.key)
            return try builder.stableSubshape(key)
        }
        return (box, edges)
    }

    @Test(.timeLimit(.minutes(2)))
    func twoEdgesThatDoNotMeetRoundTogether() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // The box's top front and bottom back edges along X share only their end faces.
        let (box, edges) = try boxEdges(&builder, [(0, 0.02), (0.02, 0)])
        let r = 0.003
        _ = try builder.fillet(target: box, edges: edges, radius: length(r))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let expected = 0.02 * 0.02 * 0.02 - 2 * (r * r - Double.pi * r * r / 4) * 0.02
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")

        // Two chamfers likewise, each cutting a right triangle of the distance.
        var chamfers = DocumentBuilder(units: .meters, tolerance: .standard)
        let (other, otherEdges) = try boxEdges(&chamfers, [(0, 0.02), (0.02, 0)])
        _ = try chamfers.chamfer(target: other, edges: otherEdges, distance: length(r))
        let chamfered = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try chamfers.build(name: "box"))
        try chamfered.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try chamfered.brep.volume(tolerance: .standard) - (0.02 * 0.02 * 0.02 - 2 * r * r / 2 * 0.02)) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCylindersRimRoundsIntoATorusBand() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A disc of radius 10 mm extruded 20 mm; one arc of its top rim selects the whole rim.
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(0.01))
        }.featureID
        let cylinder = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "c"))
        let rim = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == cylinder, case let .edge(id) = value, let edge = before.brep.edges[id],
                  case .circle? = before.brep.geometry.curves[edge.curveID],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return abs(start.z - 0.02) < 1e-12
        }?.key)
        let r = 0.002
        _ = try builder.fillet(target: cylinder, edges: [try builder.stableSubshape(rim)], radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "c"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // Pappus: the corner section r²(1 − π/4) swept about the axis at its centroid, r(10 − 3π)/(12 − 3π) in from the wall.
        let (radius, height) = (0.01, 0.02)
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let expected = Double.pi * radius * radius * height - section * 2 * Double.pi * (radius - inset)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aHolesRimRoundsIntoATorusBandAndBothItsRimsTogether() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A 40 mm square with a hole of radius 8 mm, extruded 20 mm.
        let sketch = try builder.sketch(on: .xy) { sketch in
            let corners: [(Double, Double)] = [(-0.02, -0.02), (0.02, -0.02), (0.02, 0.02), (-0.02, 0.02)]
            for (start, end) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
            }
            _ = sketch.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(0.008))
        }.featureID
        let plate = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "h"))
        let rims = try before.subshapes.entries.filter { key, value in
            guard key.featureID == plate, case let .edge(id) = value, let edge = before.brep.edges[id],
                  case .circle? = before.brep.geometry.curves[edge.curveID] else { return false }
            return true
        }
        let top = try #require(rims.first { key, value in
            guard case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return abs(start.z - 0.02) < 1e-12
        }?.key)
        let r = 0.002
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let solid = (0.04 * 0.04 - Double.pi * 0.008 * 0.008) * 0.02
        var single = builder
        _ = try single.fillet(target: plate, edges: [try single.stableSubshape(top)], radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try single.build(name: "h"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // The corner section swept about the axis outside the hole's wall.
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - (solid - section * 2 * Double.pi * (0.008 + inset))) < 5e-12, "\(volume)")
        // A top and a bottom arc select both rims of the hole.
        let bottom = try #require(rims.first { key, value in
            guard case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return abs(start.z) < 1e-12
        }?.key)
        _ = try builder.fillet(target: plate, edges: [try builder.stableSubshape(top), try builder.stableSubshape(bottom)], radius: length(r))
        let both = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "h"))
        try both.brep.validate(level: .volumetric, tolerance: .standard)
        let twice = try both.brep.volume(tolerance: .standard)
        #expect(abs(twice - (solid - 2 * section * 2 * Double.pi * (0.008 + inset))) < 5e-12, "\(twice)")
    }

    @Test(.timeLimit(.minutes(3)))
    func aBossesBaseFillsWithATorusOrConeBand() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A 40 × 20 × 10 mm plate with a boss of radius 3 mm standing 5 mm on its top.
        let plate = try builder.box(width: length(0.04), depth: length(0.02), height: length(0.01))
        let boss = try builder.cylinder(
            placement: PrimitivePlacement(origin: Point3D(x: 0.02, y: 0.01, z: 0.005), axis: .unitZ, referenceDirection: .unitX),
            radius: length(0.003), height: length(0.01))
        let body = try builder.boolean(targets: [plate], tool: boss, operation: .union)
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "b"))
        let base = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == body, case let .edge(id) = value, let edge = before.brep.edges[id],
                  case .circle? = before.brep.geometry.curves[edge.curveID],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return abs(start.z - 0.01) < 1e-12
        }?.key)
        let r = 0.001
        // A chamfer there fills the corner with the triangle r²/2 about the axis at r/3 out.
        var chamfered = builder
        _ = try chamfered.chamfer(target: body, edges: [try chamfered.stableSubshape(base)], distance: length(r))
        let cut = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try chamfered.build(name: "b"))
        try cut.brep.validate(level: .volumetric, tolerance: .standard)
        let solid = 0.04 * 0.02 * 0.01 + Double.pi * 0.003 * 0.003 * 0.005
        let chamferVolume = try cut.brep.volume(tolerance: .standard)
        #expect(abs(chamferVolume - (solid + r * r / 2 * 2 * Double.pi * (0.003 + r / 3))) < 5e-12, "\(chamferVolume)")
        _ = try builder.fillet(target: body, edges: [try builder.stableSubshape(base)], radius: length(r))
        let filled = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "b"))
        try filled.brep.validate(level: .volumetric, tolerance: .standard)
        // Pappus: the corner section gained, about the axis at its centroid outside the boss's wall.
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let expected = 0.04 * 0.02 * 0.01 + Double.pi * 0.003 * 0.003 * 0.005 + r * r * (1 - Double.pi / 4) * 2 * Double.pi * (0.003 + inset)
        let volume = try filled.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    /// A 40 × 30 mm rectangle with 5 mm round corners at the origin, extruded 10 mm, and one of
    /// its top edges along X.
    private func roundedBlock(_ builder: inout DocumentBuilder) throws -> (FeatureID, StableSubshapeReference) {
        let (w, h, c) = (0.04, 0.03, 0.005)
        func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }
        func degrees(_ value: Double) -> CADExpression { .constant(.angle(value, unit: .degree)) }
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: point(c, 0), to: point(w - c, 0))
            _ = sketch.arc(center: point(w - c, c), radius: length(c), startAngle: degrees(-90), endAngle: degrees(0))
            _ = sketch.line(from: point(w, c), to: point(w, h - c))
            _ = sketch.arc(center: point(w - c, h - c), radius: length(c), startAngle: degrees(0), endAngle: degrees(90))
            _ = sketch.line(from: point(w - c, h), to: point(c, h))
            _ = sketch.arc(center: point(c, h - c), radius: length(c), startAngle: degrees(90), endAngle: degrees(180))
            _ = sketch.line(from: point(0, h - c), to: point(0, c))
            _ = sketch.arc(center: point(c, c), radius: length(c), startAngle: degrees(180), endAngle: degrees(270))
        }.featureID
        let block = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.01))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "r"))
        let edge = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == block, case let .edge(id) = value, let edge = before.brep.edges[id],
                  case .line? = before.brep.geometry.curves[edge.curveID],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return abs(start.z - 0.01) < 1e-12 && abs(end.z - 0.01) < 1e-12 && abs(start.y) < 1e-12 && abs(end.y) < 1e-12
        }?.key)
        return (block, try builder.stableSubshape(edge))
    }

    @Test(.timeLimit(.minutes(2)))
    func aRoundedBlocksTopOutlineRoundsAndChamfersAllTheWayRound() throws {
        let (w, h, c, height, r) = (0.04, 0.03, 0.005, 0.01, 0.002)
        let solid = (w * h - (4 - Double.pi) * c * c) * height
        // The straight runs between the corners, and the corners' quarter turns about their axes.
        let straight = 2 * (w - 2 * c) + 2 * (h - 2 * c)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (block, edge) = try roundedBlock(&builder)
        var chamfered = builder
        _ = try builder.fillet(target: block, edges: [edge], radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "r"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let roundVolume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(roundVolume - (solid - section * (straight + 2 * Double.pi * (c - inset)))) < 5e-12, "\(roundVolume)")
        _ = try chamfered.chamfer(target: block, edges: [edge], distance: length(r))
        let cut = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try chamfered.build(name: "r"))
        try cut.brep.validate(level: .volumetric, tolerance: .standard)
        let chamferVolume = try cut.brep.volume(tolerance: .standard)
        #expect(abs(chamferVolume - (solid - r * r / 2 * (straight + 2 * Double.pi * (c - r / 3)))) < 5e-12, "\(chamferVolume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aDsUprightCornerBetweenItsFlatAndItsArcRounds() throws {
        // A D of radius 10 mm extruded 10 mm; its upright edge at (10, 0) mm joins the flat side
        // (y = 0) and the round one at a right angle.
        let (big, height, r) = (0.01, 0.01, 0.002)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.arc(center: SketchPoint(x: length(0), y: length(0)), radius: length(big),
                           startAngle: .constant(.angle(0, unit: .degree)), endAngle: .constant(.angle(180, unit: .degree)))
            _ = sketch.line(from: SketchPoint(x: length(-big), y: length(0)), to: SketchPoint(x: length(big), y: length(0)))
        }.featureID
        let d = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(height))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "d"))
        let corner = try edges(of: d, in: before, builder) { abs($0.x - big) < 1e-12 && abs($0.y) < 1e-12 }
        #expect(corner.count == 1)
        // Both corners together round in turn, each removing as much.
        var both = builder
        let corners = try [big, -big].flatMap { x in try edges(of: d, in: before, both) { abs($0.x - x) < 1e-12 && abs($0.y) < 1e-12 } }
        #expect(corners.count == 2)
        _ = try both.fillet(target: d, edges: corners, radius: length(r))
        let twice = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try both.build(name: "d"))
        try twice.brep.validate(level: .volumetric, tolerance: .standard)
        _ = try builder.fillet(target: d, edges: corner, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "d"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // The round's centre r above the flat and r inside the arc; the corner it cuts off by Green's
        // theorem: the big arc from the corner to the touch, the small arc back down to the flat.
        let cx = ((big - r) * (big - r) - r * r).squareRoot()
        let theta = atan2(r, cx)
        let small = r * r * (-Double.pi / 2 - theta) + r * (-cx - (cx * sin(theta) - r * cos(theta)))
        let removed = big * big * theta / 2 + small / 2
        let expected = (Double.pi * big * big / 2 - removed) * height
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
        let bothVolume = try twice.brep.volume(tolerance: .standard)
        #expect(abs(bothVolume - (Double.pi * big * big / 2 - 2 * removed) * height) < 5e-12, "\(bothVolume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aTabsConcaveRootBetweenItsEdgeAndItsArcFills() throws {
        // A 20 mm square with a half disc of radius 5 mm standing on its top edge, extruded 10 mm;
        // the upright edge at (15, 20) mm joins the top edge and the disc's arc in a concave corner.
        let (a, c, height, r) = (0.02, 0.005, 0.01, 0.002)
        func p(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: p(0, 0), to: p(a, 0))
            _ = sketch.line(from: p(a, 0), to: p(a, a))
            _ = sketch.line(from: p(a, a), to: p(a / 2 + c, a))
            _ = sketch.arc(center: p(a / 2, a), radius: length(c),
                           startAngle: .constant(.angle(0, unit: .degree)), endAngle: .constant(.angle(180, unit: .degree)))
            _ = sketch.line(from: p(a / 2 - c, a), to: p(0, a))
            _ = sketch.line(from: p(0, a), to: p(0, 0))
        }.featureID
        let tab = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(height))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "tab"))
        let root = try edges(of: tab, in: before, builder) { abs($0.x - (a / 2 + c)) < 1e-12 && abs($0.y - a) < 1e-12 }
        #expect(root.count == 1)
        _ = try builder.fillet(target: tab, edges: root, radius: length(r))
        let filled = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "tab"))
        try filled.brep.validate(level: .volumetric, tolerance: .standard)
        // The round's centre r above the edge and r outside the disc; it fills the wedge between them.
        func F(_ radius: Double, _ u: Double) -> Double { (u * (radius * radius - u * u).squareRoot() + radius * radius * asin(u / radius)) / 2 }
        let cx = (c + r) * (c + r) - r * r
        let centre = cx.squareRoot()
        let xb = centre * c / (c + r)
        let added = (F(c, xb) - F(c, c)) + r * (centre - xb) - (F(r, 0) - F(r, xb - centre))
        let expected = (a * a + Double.pi * c * c / 2 + added) * height
        let volume = try filled.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func rimsChamferIntoConeBands() throws {
        let d = 0.002
        // A cylinder's top rim: the corner triangle d²/2 swept about the axis at d/3 in from the wall.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(0.01))
        }.featureID
        let cylinder = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "c"))
        let rim = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == cylinder, case let .edge(id) = value, let edge = before.brep.edges[id],
                  case .circle? = before.brep.geometry.curves[edge.curveID],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return abs(start.z - 0.02) < 1e-12
        }?.key)
        _ = try builder.chamfer(target: cylinder, edges: [try builder.stableSubshape(rim)], distance: length(d))
        let cut = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "c"))
        try cut.brep.validate(level: .volumetric, tolerance: .standard)
        let expected = Double.pi * 0.01 * 0.01 * 0.02 - d * d / 2 * 2 * Double.pi * (0.01 - d / 3)
        let volume = try cut.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func anLBlocksTopEdgesMitreAroundItsInsideCorner() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // An L of 40 mm arms 10 mm thick, extruded 20 mm; its inside corner at (10, 10) mm.
        let outline: [(Double, Double)] = [(0, 0), (0.04, 0), (0.04, 0.01), (0.01, 0.01), (0.01, 0.04), (0, 0.04)]
        let sketch = try builder.sketch(on: .xy) { sketch in
            for (start, end) in zip(outline, outline.dropFirst() + outline.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
            }
        }.featureID
        let block = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        // The two top edges meeting at the inside corner.
        let inner = try before.subshapes.entries.filter { key, value in
            guard key.featureID == block, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.z - 0.02) < 1e-12 }
                && [start, end].contains { abs($0.x - 0.01) < 1e-12 && abs($0.y - 0.01) < 1e-12 }
        }.map { try builder.stableSubshape($0.key) }
        #expect(inner.count == 2)
        let r = 0.004
        _ = try builder.fillet(target: block, edges: inner, radius: length(r))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // Both edges' removed sections, and the blends run on past the corner to their mitre, removing
        // as much more as an outward mitre gives back.
        let expected = (0.04 * 0.01 + 0.03 * 0.01) * 0.02 - r * r * (1 - Double.pi / 4) * 0.06 - r * r * r * (5.0 / 3 - Double.pi / 2)
        // Measured under a tight tolerance: the standard one's enclosure leaves a few 1e-12 m³ here.
        let volume = try evaluated.brep.volume(tolerance: ModelingTolerance(distance: 1e-9, angle: 1e-12, relative: 1e-12))
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aConcaveEdgeMeetingAConvexOneIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let outline: [(Double, Double)] = [(0, 0), (0.04, 0), (0.04, 0.01), (0.01, 0.01), (0.01, 0.04), (0, 0.04)]
        let sketch = try builder.sketch(on: .xy) { sketch in
            for (start, end) in zip(outline, outline.dropFirst() + outline.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
            }
        }.featureID
        let block = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        // The inside corner's upright edge and the top edge along X it meets.
        let edges = try before.subshapes.entries.filter { key, value in
            guard key.featureID == block, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            let upright = [start, end].allSatisfy { abs($0.x - 0.01) < 1e-12 && abs($0.y - 0.01) < 1e-12 }
            let top = [start, end].allSatisfy { abs($0.z - 0.02) < 1e-12 && abs($0.y - 0.01) < 1e-12 }
            return upright || top
        }.map { try builder.stableSubshape($0.key) }
        #expect(edges.count == 2)
        _ = try builder.fillet(target: block, edges: edges, radius: length(0.002))
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func variablePointsSetTheRadiusBetweenTheEnds() throws {
        let (s, r0, r1, r2) = (0.02, 0.002, 0.005, 0.003)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, edges) = try boxEdges(&builder, [(0, 0.02)])
        // 2 mm at the start, 5 mm halfway, 3 mm at the end.
        _ = try builder.fillet(target: box, edges: edges, radius: length(r0), endRadius: length(r2),
                               variablePoints: [FilletVariablePoint(position: 0.5, radius: length(r1))])
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // Each half removes (1 − π/4)(a² + ab + b²)/3 times its length, the radius linear from a to b.
        func half(_ a: Double, _ b: Double) -> Double { (1 - Double.pi / 4) * (a * a + a * b + b * b) / 3 * s / 2 }
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - (s * s * s - half(r0, r1) - half(r1, r2))) < 5e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func limitPointsRoundOnlyTheirStretchOfTheEdge() throws {
        let (s, r) = (0.02, 0.003)
        let section = r * r * (1 - Double.pi / 4)
        for (limits, shape) in [(EdgeBlendLimits(start: 0.25, end: 0.75), FilletShape.round),
                                (EdgeBlendLimits(start: 0, end: 0.5), .round),
                                (EdgeBlendLimits(start: 0.5, end: 1), .conic)] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let (box, edges) = try boxEdges(&builder, [(0, 0.02)])
            _ = try builder.fillet(target: box, edges: edges, radius: length(r), shape: shape, limits: limits)
            let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
            try rounded.brep.validate(level: .volumetric, tolerance: .standard)
            // The section removed along the limited stretch only, the caps being flat: the round's
            // corner, or for a conic of tension 0.5 the parabola's r²/6 (the corner's r²/2 less
            // the parabolic segment's two thirds of it).
            let removed = shape == .round ? section : r * r / 6
            let stretch = (limits.end - limits.start) * s
            let volume = try rounded.brep.volume(tolerance: .standard)
            #expect(abs(volume - (s * s * s - removed * stretch)) < 5e-12, "\(limits): \(volume)")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func twoEdgesMeetingAtACornerJoinAtAMitre() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // The top front edge along X and the top edge along Y it meets at (0, 0, 20) mm.
        let (box, alongX) = try boxEdges(&builder, [(0, 0.02)])
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let alongY = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                  let end = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.x) < 1e-12 && abs($0.z - 0.02) < 1e-12 }
        }?.key)
        let r = 0.003
        _ = try builder.fillet(target: box, edges: alongX + [try builder.stableSubshape(alongY)], radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // Both edges' removed prisms, less their overlap at the corner ∫(r − √(r² − ζ²))² dζ.
        let section = r * r * (1 - Double.pi / 4)
        let expected = 0.02 * 0.02 * 0.02 - section * (0.02 + 0.02) + r * r * r * (5.0 / 3 - Double.pi / 2)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    /// The box's edges whose ends all satisfy `isOn`, as stable references.
    private func edges(of box: FeatureID, in evaluated: EvaluatedDocument, _ builder: DocumentBuilder,
                       where isOn: (Point3D) -> Bool) throws -> [StableSubshapeReference] {
        try evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == box, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                  let end = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
            return isOn(start) && isOn(end)
        }.map { try builder.stableSubshape($0.key) }
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxsFourTopEdgesRoundAroundMitredCorners() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, _) = try boxEdges(&builder, [])
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let top = try edges(of: box, in: evaluated, builder) { abs($0.z - 0.02) < 1e-12 }
        #expect(top.count == 4)
        let r = 0.003
        _ = try builder.fillet(target: box, edges: top, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // Four edges' removed prisms, less their overlaps at the four corners.
        let expected = 0.02 * 0.02 * 0.02 - r * r * (1 - Double.pi / 4) * 0.08 + 4 * r * r * r * (5.0 / 3 - Double.pi / 2)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func threeTopEdgesRoundAroundTwoMitresAndCloseAtTheirEnds() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, _) = try boxEdges(&builder, [])
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        // The top edges at y = 0, x = 0 and y = 20 mm: a chain open at x = 20 mm.
        let three = try ["y0", "x0", "y1"].flatMap { side in
            try edges(of: box, in: evaluated, builder) { point in
                guard abs(point.z - 0.02) < 1e-12 else { return false }
                switch side {
                case "y0": return abs(point.y) < 1e-12
                case "x0": return abs(point.x) < 1e-12
                default: return abs(point.y - 0.02) < 1e-12
                }
            }
        }
        #expect(three.count == 3)
        let r = 0.003
        _ = try builder.fillet(target: box, edges: three, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        let expected = 0.02 * 0.02 * 0.02 - r * r * (1 - Double.pi / 4) * 0.06 + 2 * r * r * r * (5.0 / 3 - Double.pi / 2)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func threeEdgesAtACornerRoundIntoTheBallsOctant() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, _) = try boxEdges(&builder, [])
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let corner = try edges(of: box, in: evaluated, builder) { point in
            [point.x, point.y, point.z].filter { abs($0) < 1e-12 }.count >= 2
        }
        #expect(corner.count == 3)
        let r = 0.003
        _ = try builder.fillet(target: box, edges: corner, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // Each edge's section removed beyond the ball, and the corner cube less the ball's octant.
        let expected = 0.02 * 0.02 * 0.02 - 3 * r * r * (1 - Double.pi / 4) * (0.02 - r) - r * r * r * (1 - Double.pi / 6)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func everyEdgeOfABoxRoundsIntoARoundedBox() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, _) = try boxEdges(&builder, [])
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let all = try edges(of: box, in: evaluated, builder) { _ in true }
        #expect(all.count == 12)
        let r = 0.003
        _ = try builder.fillet(target: box, edges: all, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // The inner box swept by the ball: its volume, faces, edges and corners grown by r.
        let a = 0.02 - 2 * r
        let expected = a * a * a + 6 * a * a * r + 3 * Double.pi * r * r * a + 4 * Double.pi * r * r * r / 3
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
        #expect(rounded.brep.faces.count == 26)
    }

    @Test(.timeLimit(.minutes(3)))
    func everyEdgeOfAHexagonalPrismRoundsAcrossItsAngles() throws {
        // A regular hexagon of 10 mm sides extruded 20 mm: its top and bottom edges meet their
        // faces at 90°, its upright ones at 120°, three meeting at every corner.
        let (a, h, r) = (0.01, 0.02, 0.002)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let corners = (0..<6).map { k in (a * cos(Double(k) * .pi / 3), a * sin(Double(k) * .pi / 3)) }
        let sketch = try builder.sketch(on: .xy) { sketch in
            for (start, end) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
            }
        }.featureID
        let prism = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(h))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "hex"))
        let all = try edges(of: prism, in: evaluated, builder) { _ in true }
        #expect(all.count == 18)
        _ = try builder.fillet(target: prism, edges: all, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "hex"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // Steiner: the prism shrunk by r on every face, grown back by the ball. Its hexagon's inradius
        // is r less; its edges take the ball's (π − α)·r²/2 per length, its corners the whole ball.
        let inner = (a * 3.0.squareRoot() / 2 - r) * 2 / 3.0.squareRoot()
        let height = h - 2 * r
        let base = 3 * 3.0.squareRoot() / 2 * inner * inner
        let volume = base * height + (2 * base + 6 * inner * height) * r
            + r * r / 2 * (12 * inner * Double.pi / 2 + 6 * height * Double.pi / 3) + 4 * Double.pi * r * r * r / 3
        let measured = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(measured - volume) < 5e-12, "\(measured) vs \(volume)")
    }

    @Test(.timeLimit(.minutes(3)))
    func aCornersRoundMeetsAMitreAlongItsEdge() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, _) = try boxEdges(&builder, [])
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        // The three edges at (0, 0, 20) mm, and the top edge at x = 20 mm meeting the first at a mitre.
        let corner = try edges(of: box, in: evaluated, builder) { point in
            [point.x, point.y, abs(point.z - 0.02)].filter { abs($0) < 1e-12 }.count >= 2
        }
        let side = try edges(of: box, in: evaluated, builder) { abs($0.x - 0.02) < 1e-12 && abs($0.z - 0.02) < 1e-12 }
        #expect(corner.count == 3 && side.count == 1)
        let r = 0.003
        _ = try builder.fillet(target: box, edges: corner + side, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let (s, a) = (0.02, r * r * (1 - Double.pi / 4))
        // The ball's corner, three edges beyond it, the fourth edge, less the mitre's overlap.
        let expected = s * s * s - r * r * r * (1 - Double.pi / 6) - 3 * a * (s - r) - a * s + r * r * r * (5.0 / 3 - Double.pi / 2)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    /// The box after chamfering `select`ed edges by `d`, evaluated and validated.
    private func chamferedBox(_ select: (Point3D) -> Bool, count: Int, d: Double) throws -> Double {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, _) = try boxEdges(&builder, [])
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let selected = try edges(of: box, in: evaluated, builder, where: select)
        #expect(selected.count == count)
        _ = try builder.chamfer(target: box, edges: selected, distance: length(d))
        let chamfered = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try chamfered.brep.validate(level: .volumetric, tolerance: .standard)
        return try chamfered.brep.volume(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(2)))
    func chamfersMeetAtTheirPlanesIntersections() throws {
        let (s, d) = (0.02, 0.003)
        // Each edge's triangle along it, less d³/3 where two meet, plus d³/4 where three meet.
        let pair = try chamferedBox({ abs($0.z - s) < 1e-12 && (abs($0.y) < 1e-12 || abs($0.x) < 1e-12) }, count: 2, d: d)
        #expect(abs(pair - (s * s * s - d * d * s + d * d * d / 3)) < 5e-12, "\(pair)")
        let top = try chamferedBox({ abs($0.z - s) < 1e-12 }, count: 4, d: d)
        #expect(abs(top - (s * s * s - 2 * d * d * s + 4 * d * d * d / 3)) < 5e-12, "\(top)")
        let corner = try chamferedBox({ point in [point.x, point.y, point.z].filter { abs($0) < 1e-12 }.count >= 2 }, count: 3, d: d)
        #expect(abs(corner - (s * s * s - 1.5 * d * d * s + 0.75 * d * d * d)) < 5e-12, "\(corner)")
        let all = try chamferedBox({ _ in true }, count: 12, d: d)
        #expect(abs(all - (s * s * s - 6 * d * d * s + 6 * d * d * d)) < 5e-12, "\(all)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aVariableFilletGrowsAlongItsEdgeAndSurvivesARoundTrip() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (box, edges) = try boxEdges(&builder, [(0, 0.02)])
        let (r0, r1) = (0.002, 0.006)
        _ = try builder.fillet(target: box, edges: edges, radius: length(r0), endRadius: length(r1))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The removed cross-section (1 − π/4)·r² with r linear along the 20 mm edge integrates to
        // (1 − π/4)·(r0² + r0·r1 + r1²)/3 · L.
        let removed = (1 - Double.pi / 4) * (r0 * r0 + r0 * r1 + r1 * r1) / 3 * 0.02
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - (0.02 * 0.02 * 0.02 - removed)) < 5e-12, "\(volume)")

        // A shaped fillet and a variable one round-trip through the native package.
        // A limited fillet of a second box's edge, chosen before the stored features are added.
        let (limitedBox, limitedEdges) = try boxEdges(&builder, [(0, 0)])
        _ = try builder.fillet(target: limitedBox, edges: limitedEdges, radius: length(0.002), limits: EdgeBlendLimits(start: 0.2, end: 0.6))
        let (pointedBox, pointedEdges) = try boxEdges(&builder, [(0, 0)])
        _ = try builder.fillet(target: pointedBox, edges: pointedEdges, radius: length(0.002),
                               variablePoints: [FilletVariablePoint(position: 0.3, radius: length(0.004))])
        _ = try builder.fillet(target: box, edges: try boxEdges(&builder, [(0.02, 0)]).1, radius: length(0.003), shape: .conic, tension: 0.4)
        let document = try builder.build(name: "box")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        #expect(try store.loadDocument(from: BorrowedBytes(sink.bytes)).designGraph.nodes == document.designGraph.nodes)
    }
}
