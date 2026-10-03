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
            // Conic 0.5 is the round of radius d (its arc's weight sin 45°); 0.3 is flatter.
            (.conic, 0.5, [(d, 0), (0, 0), (0, d)], [1, 0.5.squareRoot(), 1]),
            (.conic, 0.3, [(d, 0), (0, 0), (0, d)], [1, 0.5.squareRoot() * 0.3 / 0.7, 1]),
            (.chordal, nil, [(d / 2.0.squareRoot(), 0), (0, 0), (0, d / 2.0.squareRoot())], [1, 0.5.squareRoot(), 1]),
            // Chordal takes a tension too: 0.7 fuller than its arc.
            (.chordal, 0.7, [(d / 2.0.squareRoot(), 0), (0, 0), (0, d / 2.0.squareRoot())], [1, 0.5.squareRoot() * 0.7 / 0.3, 1]),
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
        #expect(throws: KernelError.self) { _ = try fillet(shape: .chordal, tension: 1, distance: 0.004) }
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
    func aFullFilletRoundsTwoFacesAtOnce() throws {
        // Plasticity's shape video: the four long edges of a 20 × 40 × 30 mm rib, the top's two
        // and the bottom's two, round both faces full at once — each pair across its own face.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let rib = try builder.box(width: length(0.02), depth: length(0.04), height: length(0.03))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rib"))
        func longEdges(atZ z: Double) throws -> [StableSubshapeReference] {
            try before.subshapes.entries.compactMap { key, value -> StableSubshapeReference? in
                guard key.featureID == rib, case let .edge(id) = value, let edge = before.brep.edges[id],
                      let start = before.brep.vertices[edge.startVertexID]?.point,
                      let end = before.brep.vertices[edge.endVertexID]?.point,
                      abs(start.z - z) < 1e-12, abs(end.z - z) < 1e-12, abs(start.y - end.y) > 0.03 else { return nil }
                return try builder.stableSubshape(key)
            }
        }
        let top = try longEdges(atZ: 0.03), bottom = try longEdges(atZ: 0)
        #expect(top.count == 2 && bottom.count == 2)
        _ = try builder.fillet(target: rib, edges: top + bottom, radius: length(0.01), shape: .full)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rib"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let r = 0.01
        let expected = 0.02 * 0.04 * 0.03 - 2 * 0.04 * (2 * r * r - Double.pi * r * r / 2)
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
        // An odd count of edges has no pairs.
        #expect(throws: KernelError.self) {
            try FilletFeature(target: FilletTargetReference(featureID: rib), edges: Array((top + bottom).prefix(3)),
                              radius: length(0.01), shape: .full).validate()
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
        // Every sharp edge: the upright corners first, then all four rims, the plate's outline
        // closing on spheres at its corners — the rounded box (its inner box swept by the ball)
        // less the hole and its rims' bands.
        var every = DocumentBuilder(units: .meters, tolerance: .standard)
        let everySketch = try every.sketch(on: .xy) { sketch in
            let corners: [(Double, Double)] = [(-0.02, -0.02), (0.02, -0.02), (0.02, 0.02), (-0.02, 0.02)]
            for (start, end) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
            }
            _ = sketch.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(0.008))
        }.featureID
        let everyPlate = try every.extrude(ProfileReference(featureID: everySketch, profileIndex: 0), distance: length(0.02))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try every.build(name: "h"))
        let sharp = try evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == everyPlate, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                  let end = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
            // The hole's seams, along its wall between its arcs, are smooth.
            let onHole = { (p: Point3D) in abs((p.x * p.x + p.y * p.y).squareRoot() - 0.008) < 1e-9 }
            guard case .line? = evaluated.brep.geometry.curves[edge.curveID], onHole(start), onHole(end) else { return true }
            return false
        }.map { try every.stableSubshape($0.key) }
        _ = try every.fillet(target: everyPlate, edges: sharp, radius: length(r))
        let all = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try every.build(name: "h"))
        try all.brep.validate(level: .volumetric, tolerance: .standard)
        let (a, b, c) = (0.04 - 2 * r, 0.04 - 2 * r, 0.02 - 2 * r)
        let roundedBox = a * b * c + 2 * r * (a * b + a * c + b * c) + Double.pi * r * r * (a + b + c) + 4 * Double.pi * r * r * r / 3
        let allVolume = try all.brep.volume(tolerance: .standard)
        let expected = roundedBox - Double.pi * 0.008 * 0.008 * 0.02 - 2 * section * 2 * Double.pi * (0.008 + inset)
        #expect(abs(allVolume - expected) < 5e-12, "\(allVolume) vs \(expected)")
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

    /// Plasticity's Conic, Chordal and G2 along a rounded outline's tangent chain: Conic and
    /// Chordal at tension 0.5 are the round of the distance (Chordal's chord the distance, so a
    /// round of distance/√2); higher Conic tension keeps more material, and so does G2's quintic.
    @Test(.timeLimit(.minutes(2)))
    func aRoundedBlocksTopOutlineTakesConicChordalAndG2() throws {
        let (w, h, c, height, r) = (0.04, 0.03, 0.005, 0.01, 0.002)
        let solid = (w * h - (4 - Double.pi) * c * c) * height
        let straight = 2 * (w - 2 * c) + 2 * (h - 2 * c)
        func roundVolume(_ radius: Double) -> Double {
            let section = radius * radius * (1 - Double.pi / 4)
            let inset = radius * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
            return solid - section * (straight + 2 * Double.pi * (c - inset))
        }
        func filleted(_ shape: FilletShape, tension: Double?) throws -> Double {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let (block, edge) = try roundedBlock(&builder)
            _ = try builder.fillet(target: block, edges: [edge], radius: length(r), shape: shape, tension: tension)
            let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "r"))
            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            return try evaluated.brep.volume(tolerance: .standard)
        }
        let conic = try filleted(.conic, tension: 0.5)
        #expect(abs(conic - roundVolume(r)) < 1e-11, "\(conic) vs \(roundVolume(r))")
        let chordal = try filleted(.chordal, tension: 0.5)
        #expect(abs(chordal - roundVolume(r / 2.0.squareRoot())) < 1e-11, "\(chordal)")
        let fuller = try filleted(.conic, tension: 0.7)
        #expect(fuller > conic + 1e-12 && fuller < solid)
        let g2 = try filleted(.curvature, tension: nil)
        // G2's quintic hugs the corner more closely than the arc: it keeps more material.
        #expect(g2 > conic && g2 < solid, "\(g2) vs \(conic)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxsTopOutlineRoundsOverItsFilletedUprightEdges() throws {
        // Plasticity's selection video: a box whose four upright edges one fillet rounded, then
        // one top edge with tangent edges rounding the whole top outline over those rounds.
        let (w, h, c, height, r) = (0.04, 0.03, 0.005, 0.01, 0.002)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.rectangle(width: length(w), height: length(h))
        }.featureID
        let box = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(height))
        let plain = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        // The rectangle is centred on the origin.
        let uprights = try [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)].flatMap { corner in
            try edges(of: box, in: plain, builder) { abs($0.x - corner.0) < 1e-12 && abs($0.y - corner.1) < 1e-12 }
        }
        #expect(uprights.count == 4)
        let roundedUprights = try builder.fillet(target: box, edges: uprights, radius: length(c))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let top = try #require(try edges(of: roundedUprights, in: rounded, builder) { abs($0.z - height) < 1e-12 && abs($0.y + h / 2) < 1e-12 }.first)
        _ = try builder.fillet(target: roundedUprights, edges: [top], radius: length(r))
        let result = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try result.brep.validate(level: .volumetric, tolerance: .standard)
        let solid = (w * h - (4 - Double.pi) * c * c) * height
        let straight = 2 * (w - 2 * c) + 2 * (h - 2 * c)
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let volume = try result.brep.volume(tolerance: .standard)
        #expect(abs(volume - (solid - section * (straight + 2 * Double.pi * (c - inset)))) < 5e-12, "\(volume)")
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
    func aDsTopArcRoundsAndChamfersEndingOnItsFlatSide() throws {
        // A D of radius 10 mm extruded 10 mm; its top arc, sharp at the flat side, ends on that
        // side square to it: the band is half a torus (or cone) ending on its sections there.
        let (big, height, r) = (0.01, 0.01, 0.002)
        let solid = Double.pi * big * big / 2 * height
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.arc(center: SketchPoint(x: length(0), y: length(0)), radius: length(big),
                           startAngle: .constant(.angle(0, unit: .degree)), endAngle: .constant(.angle(180, unit: .degree)))
            _ = sketch.line(from: SketchPoint(x: length(-big), y: length(0)), to: SketchPoint(x: length(big), y: length(0)))
        }.featureID
        let d = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(height))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "d"))
        let rim = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == d, case let .edge(id) = value, let edge = before.brep.edges[id],
                  case .circle? = before.brep.geometry.curves[edge.curveID],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return abs(start.z - height) < 1e-12
        }?.key)
        var chamfered = builder
        _ = try builder.fillet(target: d, edges: [try builder.stableSubshape(rim)], radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "d"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // Pappus over half a turn: the corner's section about the axis at its centroid's radius.
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let roundVolume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(roundVolume - (solid - r * r * (1 - Double.pi / 4) * Double.pi * (big - inset))) < 5e-12, "\(roundVolume)")
        _ = try chamfered.chamfer(target: d, edges: [try chamfered.stableSubshape(rim)], distance: length(r))
        let cut = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try chamfered.build(name: "d"))
        try cut.brep.validate(level: .volumetric, tolerance: .standard)
        let chamferVolume = try cut.brep.volume(tolerance: .standard)
        #expect(abs(chamferVolume - (solid - r * r / 2 * Double.pi * (big - r / 3))) < 5e-12, "\(chamferVolume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aUsTangentRunOfLinesAndArcRoundsBetweenItsSharpCorners() throws {
        // A U: 20 mm straight sides joined by a half circle of radius 5 mm, closed by a straight
        // back at x = 0, extruded 10 mm; the top's line–arc–line run ends square on the back.
        let (l, c, height, r) = (0.02, 0.005, 0.01, 0.002)
        func p(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: p(0, 0), to: p(l, 0))
            _ = sketch.arc(center: p(l, c), radius: length(c),
                           startAngle: .constant(.angle(-90, unit: .degree)), endAngle: .constant(.angle(90, unit: .degree)))
            _ = sketch.line(from: p(l, 2 * c), to: p(0, 2 * c))
            _ = sketch.line(from: p(0, 2 * c), to: p(0, 0))
        }.featureID
        let u = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(height))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "u"))
        let side = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == u, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.y) < 1e-12 && abs($0.z - height) < 1e-12 }
        }?.key)
        _ = try builder.fillet(target: u, edges: [try builder.stableSubshape(side)], radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "u"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        let solid = (l * 2 * c + Double.pi * c * c / 2) * height
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - (solid - section * (2 * l + Double.pi * (c - inset)))) < 5e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func anLBlocksInsideCornerRoundsWithTheTopEdgesMeetingIt() throws {
        // An L of 20 mm arms 10 mm wide, extruded 10 mm; its inside upright edge at (10, 10) mm and
        // the two top edges meeting it rounded together: the inside round first, then the top's run
        // around it, a torus about the inside round's axis, ending square on the arms' ends.
        let (h, r) = (0.01, 0.002)
        func p(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let corners = [(0.0, 0.0), (0.02, 0.0), (0.02, 0.01), (0.01, 0.01), (0.01, 0.02), (0.0, 0.02)]
        let sketch = try builder.sketch(on: .xy) { sketch in
            for (start, end) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                _ = sketch.line(from: p(start.0, start.1), to: p(end.0, end.1))
            }
        }.featureID
        let block = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(h))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        let inside = try edges(of: block, in: before, builder) { abs($0.x - 0.01) < 1e-12 && abs($0.y - 0.01) < 1e-12 }
        let alongX = try edges(of: block, in: before, builder) { abs($0.y - 0.01) < 1e-12 && $0.x > 0.01 - 1e-12 && abs($0.z - h) < 1e-12 }
        let alongY = try edges(of: block, in: before, builder) { abs($0.x - 0.01) < 1e-12 && $0.y > 0.01 - 1e-12 && abs($0.z - h) < 1e-12 }
        #expect(inside.count == 1 && alongX.count == 1 && alongY.count == 1)
        // With every top edge, the outer corners meet blended edges at convex corners: refused.
        var everyTop = builder
        let top = try edges(of: block, in: before, everyTop) { abs($0.z - h) < 1e-12 }
        #expect(top.count == 6)
        _ = try everyTop.fillet(target: block, edges: inside + top, radius: length(r))
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try everyTop.build(name: "l"))
        }
        _ = try builder.fillet(target: block, edges: inside + alongX + alongY, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // The inside round adds its corner's section over the height; the top's round removes it
        // along the two shortened arms and, by Pappus, around the quarter turn at its centroid's
        // radius from the inside round's axis (the arc's r plus the centroid's inset).
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let expected = 0.0003 * h + section * h - section * (2 * (0.01 - r) + Double.pi / 2 * (r + inset))
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func withTangentEdgesOffOnlyTheSelectedEdgesBlendClosingAtTheirJoints() throws {
        // The rounded block's top edge along X alone, then one corner's arc alone: each band ends on
        // its section at the tangent joints, closed by a flat face; only its own stretch is cut.
        let (w, h, c, height, r) = (0.04, 0.03, 0.005, 0.01, 0.002)
        let solid = (w * h - (4 - Double.pi) * c * c) * height
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (block, edge) = try roundedBlock(&builder)
        var chamfered = builder
        var arcOnly = builder
        _ = try builder.fillet(target: block, edges: [edge], radius: length(r), tangentEdges: false)
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "r"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        let roundVolume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(roundVolume - (solid - section * (w - 2 * c))) < 5e-12, "\(roundVolume)")
        _ = try chamfered.chamfer(target: block, edges: [edge], distance: length(r), tangentEdges: false)
        let cut = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try chamfered.build(name: "r"))
        try cut.brep.validate(level: .volumetric, tolerance: .standard)
        let chamferVolume = try cut.brep.volume(tolerance: .standard)
        #expect(abs(chamferVolume - (solid - r * r / 2 * (w - 2 * c))) < 5e-12, "\(chamferVolume)")
        // The corner arc at (w − c, c) alone: a quarter turn of the section about its axis.
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try arcOnly.build(name: "r"))
        let arc = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == block, case let .edge(id) = value, let edge = before.brep.edges[id],
                  case let .circle(circle)? = before.brep.geometry.curves[edge.curveID],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return abs(start.z - height) < 1e-12 && abs(circle.center.x - (w - c)) < 1e-12 && abs(circle.center.y - c) < 1e-12
        }?.key)
        _ = try arcOnly.fillet(target: block, edges: [try arcOnly.stableSubshape(arc)], radius: length(r), tangentEdges: false)
        let corner = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try arcOnly.build(name: "r"))
        try corner.brep.validate(level: .volumetric, tolerance: .standard)
        let cornerVolume = try corner.brep.volume(tolerance: .standard)
        #expect(abs(cornerVolume - (solid - section * Double.pi / 2 * (c - inset))) < 5e-12, "\(cornerVolume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aRimRoundAsLargeAsItsCornersClosesOnSpheres() throws {
        // The rounded block's top rim rounded by its 5 mm corner radius: each corner's band is the
        // ball's sphere about the corner's axis.
        let (w, h, c, height) = (0.04, 0.03, 0.005, 0.01)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (block, edge) = try roundedBlock(&builder)
        _ = try builder.fillet(target: block, edges: [edge], radius: length(c))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "r"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        let solid = (w * h - (4 - Double.pi) * c * c) * height
        let section = c * c * (1 - Double.pi / 4)
        let inset = c * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let straight = 2 * (w - 2 * c) + 2 * (h - 2 * c)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - (solid - section * (straight + 2 * Double.pi * (c - inset)))) < 5e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(3)))
    func everyEdgeOfAnLBlockRounds() throws {
        // The L's six upright edges round first (five convex, one concave), then its top and bottom
        // rims all the way round: spheres at the convex corners, a torus at the concave one.
        let (h, r) = (0.01, 0.002)
        func p(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let corners = [(0.0, 0.0), (0.02, 0.0), (0.02, 0.01), (0.01, 0.01), (0.01, 0.02), (0.0, 0.02)]
        let sketch = try builder.sketch(on: .xy) { sketch in
            for (start, end) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                _ = sketch.line(from: p(start.0, start.1), to: p(end.0, end.1))
            }
        }.featureID
        let block = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(h))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        let all = try edges(of: block, in: before, builder) { _ in true }
        #expect(all.count == 18)
        _ = try builder.fillet(target: block, edges: all, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // Upright rounds: five corners cut, one filled. Each rim: the section along its straight
        // runs (the 80 mm outline less r at both ends of each side) and, by Pappus, around each
        // quarter turn at the centroid's radius, r less the inset at a convex corner, r plus it at
        // the concave one.
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let rim = section * ((0.08 - 12 * r) + 5 * Double.pi / 2 * (r - inset) + Double.pi / 2 * (r + inset))
        let expected = 0.0003 * h - 4 * section * h - 2 * rim
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(3)))
    func everyEdgeOfADRounds() throws {
        // A D of radius 10 mm extruded 10 mm, every edge rounded by 2 mm: the upright corners
        // first, each a cylinder tangent to the flat and the arc, then both rims all the way round
        // — a torus along the big arc, spheres at the corners, a cylinder along the flat.
        let (big, height, r) = (0.01, 0.01, 0.002)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.arc(center: SketchPoint(x: length(0), y: length(0)), radius: length(big),
                           startAngle: .constant(.angle(0, unit: .degree)), endAngle: .constant(.angle(180, unit: .degree)))
            _ = sketch.line(from: SketchPoint(x: length(-big), y: length(0)), to: SketchPoint(x: length(big), y: length(0)))
        }.featureID
        let d = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(height))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "d"))
        // Every sharp edge: the arc's two quarter faces meet smoothly along the upright at (0, 10) mm.
        let smooth = try edges(of: d, in: before, builder) { abs($0.x) < 1e-9 && abs($0.y - big) < 1e-9 }
        let all = try edges(of: d, in: before, builder) { _ in true }.filter { smooth.contains($0) == false }
        #expect(all.count == 8)
        _ = try builder.fillet(target: d, edges: all, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "d"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // Each upright round's centre sits r above the flat and r inside the arc, at x = ±cx; it
        // turns θ = π/2 + atan2(r, cx) from the flat's normal to the arc's.
        let cx = ((big - r) * (big - r) - r * r).squareRoot()
        let phi = atan2(r, cx)
        let small = r * r * (-Double.pi / 2 - phi) + r * (-cx - (cx * sin(phi) - r * cos(phi)))
        let removed = big * big * phi / 2 + small / 2
        // Each rim: the section along the flat between the rounds (2·cx) and, by Pappus, about the
        // big arc's axis over its remaining π − 2φ at big − inset, and about each round's axis over
        // its turn π/2 + φ at r − inset.
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let rim = section * (2 * cx + (Double.pi - 2 * phi) * (big - inset) + 2 * (Double.pi / 2 + phi) * (r - inset))
        let expected = (Double.pi * big * big / 2 - 2 * removed) * height - 2 * rim
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aTubesEndRoundsFullIntoAHalfTorus() throws {
        // A tube of 10 mm and 6 mm radii, 10 mm long; its end rounded full between its rims: the
        // half torus of tube radius 2 mm about the circle midway, 8 mm out.
        let (outer, inner, height) = (0.01, 0.006, 0.01)
        let rho = (outer - inner) / 2
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(outer))
            _ = sketch.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(inner))
        }.featureID
        let tube = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(height))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "tube"))
        func rim(_ radius: Double) throws -> StableSubshapeReference {
            let key = try #require(before.subshapes.entries.first { key, value in
                guard key.featureID == tube, case let .edge(id) = value, let edge = before.brep.edges[id],
                      case .circle? = before.brep.geometry.curves[edge.curveID],
                      let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
                return abs(start.z - height) < 1e-12 && abs((start.x * start.x + start.y * start.y).squareRoot() - radius) < 1e-9
            }?.key)
            return try builder.stableSubshape(key)
        }
        _ = try builder.fillet(target: tube, edges: [try rim(outer), try rim(inner)], radius: length(rho), shape: .full)
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "tube"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // The two corners' sections, a 2ρ × ρ rectangle less the half disc, about the axis at the
        // middle radius by symmetry.
        let middle = (outer + inner) / 2
        let removed = 2 * Double.pi * middle * (2 * rho * rho - Double.pi * rho * rho / 2)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - (Double.pi * (outer * outer - inner * inner) * height - removed)) < 5e-12, "\(volume)")
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
    func aConcaveEdgeMeetingAConvexOneRoundsItsTangentRun() throws {
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
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "l"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // The inside round leaves the top edge tangent to the inside arc and the edge along Y: the
        // round takes that whole run, both arms' 30 mm less r and the quarter turn by Pappus.
        let r = 0.002
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let expected = 0.0007 * 0.02 + section * 0.02 - section * (2 * (0.03 - r) + Double.pi / 2 * (r + inset))
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
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
        // The radius follows the natural cubic spline through the three: its second derivative
        // M1 halfway from M0 + 4M1 + M2 = 6(r0 − 2r1 + r2)/h², none at the ends; the round removes
        // (1 − π/4)∫r², exact by four-point Gauss on each half's sextic.
        let h = s / 2
        let m1 = 6 * (r0 - 2 * r1 + r2) / (h * h) / 4
        func radius(_ x: Double) -> Double {
            let (y0, y1, ma, mb, x0) = x <= h ? (r0, r1, 0.0, m1, 0.0) : (r1, r2, m1, 0.0, h)
            let (left, right) = (x0 + h - x, x - x0)
            return ma * left * left * left / (6 * h) + mb * right * right * right / (6 * h)
                + (y0 / h - ma * h / 6) * left + (y1 / h - mb * h / 6) * right
        }
        let nodes = [-0.861136311594053, -0.339981043584856, 0.339981043584856, 0.861136311594053]
        let weights = [0.347854845137454, 0.652145154862546, 0.652145154862546, 0.347854845137454]
        var squared = 0.0
        for x0 in [0.0, h] {
            for (node, weight) in zip(nodes, weights) {
                let r = radius(x0 + h / 2 * (1 + node))
                squared += weight * r * r * h / 2
            }
        }
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - (s * s * s - (1 - Double.pi / 4) * squared)) < 5e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func limitPointsRoundOnlyTheirStretchOfTheEdge() throws {
        let (s, r) = (0.02, 0.003)
        let section = r * r * (1 - Double.pi / 4)
        for (limits, shape) in [(EdgeBlendLimits(start: 0.25, end: 0.75), FilletShape.round),
                                (EdgeBlendLimits(start: 0, end: 0.5), .round),
                                (EdgeBlendLimits(start: 0.5, end: 1), .conic),
                                (EdgeBlendLimits(start: 0.25, end: 0.75, reversed: true), .round),
                                (EdgeBlendLimits(start: 0.4, end: 1, reversed: true), .round)] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let (box, edges) = try boxEdges(&builder, [(0, 0.02)])
            _ = try builder.fillet(target: box, edges: edges, radius: length(r), shape: shape, limits: limits)
            let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
            try rounded.brep.validate(level: .volumetric, tolerance: .standard)
            // The section removed along the limited stretch only, the caps being flat: the round's
            // corner, which a conic of tension 0.5 is exactly.
            let removed = section
            let stretch = limits.stretches.reduce(0.0) { $0 + ($1.end - $1.start) } * s
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
