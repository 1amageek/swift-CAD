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
/// neighbours and open edges and all; a face sharing edges with planes it crosses refitted coarser
/// than the modeling tolerance, its edges re-solved on them.
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
    func removingTheNominalSurfaceCutsTheSplineToItsEdges() throws {
        // The arch extended a quarter past each end in u, then its nominal surface removed: the
        // surface ends where the face does again, the same parabola on the same parameters.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try arch(&builder)
        let (face, before) = try #require(try faces(of: sheet, in: builder).first)
        let extended = try builder.rebuildFaces(target: sheet, faces: [face], method: .tolerance(.constant(.length(1e-7, unit: .meter))), extendU: 0.25)
        let (wide, _) = try #require(try faces(of: extended, in: builder).first)
        let trimmed = try builder.rebuildFaces(target: extended, faces: [wide], method: .nominal)
        let evaluated = try evaluate(builder)
        let (_, after) = try #require(try faces(of: trimmed, in: builder).first)
        guard case let .bSpline(surface) = after else { Issue.record("The face keeps a spline."); return }
        #expect(abs((surface.uKnots.first ?? 1)) < 1e-12 && abs((surface.uKnots.last ?? 0) - 1) < 1e-12)
        for (u, v) in [(0.0, 0.0), (0.3, 0.7), (1.0, 1.0)] {
            let a = try before.differentialGeometry(u: u, v: v, tolerance: .standard).position
            let b = try after.differentialGeometry(u: u, v: v, tolerance: .standard).position
            #expect((a - b).length < 1e-7)
        }
        #expect(evaluated.brep.faces.count == 1)
        // A plane has no nominal surface beyond its edges.
        var box = DocumentBuilder(units: .meters, tolerance: .standard)
        let side = CADExpression.constant(.length(0.02, unit: .meter))
        let cube = try box.box(width: side, depth: side, height: side)
        let (top, _) = try #require(try faces(of: cube, in: box) { isPlane($0) }.first)
        _ = try box.rebuildFaces(target: cube, faces: [top], method: .nominal)
        #expect(throws: (any Error).self) { _ = try evaluate(box) }
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
    func aCurvedWallRebuiltCoarselyHasItsEdgesResolvedOnItsPlanes() throws {
        // A cubic arch over a 20 mm base, extruded 10 mm; its arched wall rebuilt as a quadratic
        // strays from its edges, which are re-solved where the new wall crosses the base's wall
        // and the two end planes.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        func point(_ x: Double, _ y: Double) -> SketchPoint {
            SketchPoint(x: .constant(.length(x, unit: .meter)), y: .constant(.length(y, unit: .meter)))
        }
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: point(0, 0), to: point(0.02, 0))
            _ = sketch.spline(SketchSpline(controlPoints: [point(0.02, 0), point(0.014, 0.016), point(0.004, 0.008), point(0, 0)]))
        }.featureID
        let height = 0.01
        let tunnel = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: .constant(.length(height, unit: .meter)))
        let (wall, _) = try #require(try faces(of: tunnel, in: builder) { if case .bSpline = $0 { return true }; return false }.first)
        let rebuilt = try builder.rebuildFaces(target: tunnel, faces: [wall],
                                               method: .explicit(SurfaceControlLayout(uDegree: 2, vDegree: 1, uSpans: 1, vSpans: 1)),
                                               extendU: 0.25)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rebuild"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let (_, after) = try #require(try faces(of: rebuilt, in: builder) { if case .bSpline = $0 { return true }; return false }.first)
        guard case let .bSpline(surface) = after, surface.uDegree == 2, let u0 = surface.uKnots.first, let u1 = surface.uKnots.last else {
            Issue.record("The rebuilt wall is a quadratic B-spline.")
            return
        }
        // The wall's section at the base: where it crosses y = 0, by bisection; the area under it
        // by Green's theorem, ∫ x dy along it, exact by five-point Gauss for its cubic integrand.
        func at(_ u: Double) throws -> (point: Point3D, du: Vector3D) {
            let geometry = try after.differentialGeometry(u: u, v: surface.vKnots[0], tolerance: .standard)
            return (geometry.position, geometry.tangentU)
        }
        func crossing(_ a: Double, _ b: Double) throws -> Double {
            var (low, high) = (a, b)
            let lowSign = try at(low).point.y > 0
            for _ in 0..<200 {
                let middle = (low + high) / 2
                if try (at(middle).point.y > 0) == lowSign { low = middle } else { high = middle }
            }
            return (low + high) / 2
        }
        let middle = (u0 + u1) / 2
        let (ua, ub) = (try crossing(u0, middle), try crossing(middle, u1))
        let nodes = [-0.906179845938664, -0.538469310105683, 0.0, 0.538469310105683, 0.906179845938664]
        let weights = [0.236926885056189, 0.478628670499366, 0.568888888888889, 0.478628670499366, 0.236926885056189]
        var area = 0.0
        for (node, weight) in zip(nodes, weights) {
            let u = (ua + ub) / 2 + (ub - ua) / 2 * node
            let (p, du) = try at(u)
            area += weight * p.x * du.y * (ub - ua) / 2
        }
        let volume = try self.volume(of: rebuilt, in: evaluated)
        #expect(abs(volume - abs(area) * height) < 1e-10, "\(volume) vs \(abs(area) * height)")
        // The stray: the quadratic leaves the cubic's corners.
        #expect(abs(abs(area) * height - 0.02 * 0.008 / 2 * height) > 1e-9)
    }

    @Test(.timeLimit(.minutes(2)))
    func aRoundRebuiltFlatBecomesAChamfer() throws {
        // A 20 mm box's top edge rounded by 4 mm, its round rebuilt bilinear: a flat face crossing
        // the top and the side it was tangent to, its edges re-solved where it crosses them.
        let (side, radius) = (0.02, 0.004)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let length = { (value: Double) in CADExpression.constant(.length(value, unit: .meter)) }
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let edge = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.y) < 1e-12 && abs($0.z - side) < 1e-12 }
        }?.key)
        let fillet = try builder.fillet(target: box, edges: [try builder.stableSubshape(edge)], radius: length(radius))
        let (round, _) = try #require(try faces(of: fillet, in: builder) { isCylinder($0) }.first)
        let rebuilt = try builder.rebuildFaces(target: fillet, faces: [round],
                                               method: .explicit(SurfaceControlLayout(uDegree: 1, vDegree: 1, uSpans: 1, vSpans: 1)))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rebuild"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let (_, flat) = try #require(try faces(of: rebuilt, in: builder) { if case .bSpline = $0 { return true }; return false }.first)
        guard case let .bSpline(surface) = flat else { Issue.record("The flat face is a B-spline surface."); return }
        let corner = try flat.differentialGeometry(u: surface.uKnots.first ?? 0, v: surface.vKnots.first ?? 0, tolerance: .standard)
        let normal = try corner.tangentU.cross(corner.tangentV).normalized(tolerance: 1e-12)
        // Where the flat face's line across the edge meets the top (z = side) and the side (y = 0).
        let p = corner.position
        let atTop = p.y - normal.z * (side - p.z) / normal.y
        let atSide = p.z - normal.y * (0 - p.y) / normal.z
        // The bilinear refit keeps the round's corners: the chord through its contact lines.
        #expect(abs(atTop - radius) < 1e-9 && abs(atSide - (side - radius)) < 1e-9, "\(atTop) \(atSide)")
        let volume = try self.volume(of: rebuilt, in: evaluated)
        #expect(abs(volume - (side * side * side - atTop * (side - atSide) / 2 * side)) < 1e-10, "\(volume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aCylindersHalfWallRebuiltFlatCutsItAlongAChord() throws {
        // A bilinear refit of one half of a cylinder's wall is a flat wall: its edges re-solved
        // where it crosses the caps and the other half's cylinder, the section the disc cut by
        // that chord.
        let (r, h) = (0.01, 0.02)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cylinder = try builder.cylinder(radius: .constant(.length(r, unit: .meter)), height: .constant(.length(h, unit: .meter)))
        let (wall, _) = try #require(try faces(of: cylinder, in: builder) { isCylinder($0) }.first)
        let rebuilt = try builder.rebuildFaces(target: cylinder, faces: [wall],
                                               method: .explicit(SurfaceControlLayout(uDegree: 1, vDegree: 1, uSpans: 1, vSpans: 1)))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rebuild"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let (_, flat) = try #require(try faces(of: rebuilt, in: builder) { if case .bSpline = $0 { return true }; return false }.first)
        guard case let .bSpline(surface) = flat else { Issue.record("The flat wall is a B-spline surface."); return }
        // The flat wall's plane: its distance c from the axis, the same at its corners.
        let corners = try [(surface.uKnots.first ?? 0, surface.vKnots.first ?? 0), (surface.uKnots.last ?? 0, surface.vKnots.last ?? 0)].map {
            try flat.differentialGeometry(u: $0.0, v: $0.1, tolerance: .standard)
        }
        let normal = try corners[0].tangentU.cross(corners[0].tangentV).normalized(tolerance: 1e-12)
        let c = abs(normal.dot(corners[0].position - Point3D(x: 0, y: 0, z: corners[0].position.z)))
        #expect(abs(abs(normal.dot(corners[1].position - Point3D(x: 0, y: 0, z: corners[1].position.z))) - c) < 1e-12)
        #expect(c < r)
        // The disc less the segment beyond the chord at distance c.
        let segment = r * r * acos(c / r) - c * (r * r - c * c).squareRoot()
        let volume = try self.volume(of: rebuilt, in: evaluated)
        #expect(abs(volume - (Double.pi * r * r - segment) * h) < 1e-10, "\(volume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aDraftedCylindersQuarterWallRebuiltFlatMeetsTheConeBesideIt() throws {
        // A circle extruded with a 10° draft: its wall a cone in four rational spline quarters.
        // One quarter rebuilt bilinear is flat, its edges with the quarters beside it re-solved
        // on those splines (not planes, cylinders or spheres): every point of them as far from
        // the axis as the cone is there.
        let (r, h) = (0.01, 0.02)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let length = { (value: Double) in CADExpression.constant(.length(value, unit: .meter)) }
        let profile = try builder.sketch(on: .xy) { _ = $0.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(r)) }
        let extrusion = try builder.extrude(profile, distance: length(h), draftAngle: .constant(.angle(10, unit: .degree)))
        let walls = try faces(of: extrusion, in: builder) { !isPlane($0) }
        #expect(walls.count == 4)
        let before = try evaluate(builder)
        let top = try #require(before.brep.vertices.values.map(\.point).first { abs($0.z - h) < 1e-9 })
        let topRadius = hypot(top.x, top.y)
        #expect(abs(abs(topRadius - r) - h * tan(10 * Double.pi / 180)) < 1e-9)
        let rebuilt = try builder.rebuildFaces(target: extrusion, faces: [walls[0].0],
                                               method: .explicit(SurfaceControlLayout(uDegree: 1, vDegree: 1, uSpans: 1, vSpans: 1)))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rebuild"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The flat face: the one whose surface is a bilinear B-spline.
        let flat = try #require(evaluated.brep.faces.values.first { face in
            guard case let .bSpline(surface)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return surface.uDegree == 1 && surface.vDegree == 1
        })
        let flatEdges = Set(flat.loops.flatMap { evaluated.brep.loops[$0]?.coedges.map(\.edgeID) ?? [] })
        var checked = 0
        for edgeID in flatEdges {
            guard let edge = evaluated.brep.edges[edgeID], let curve = evaluated.brep.geometry.curves[edge.curveID], let trim = edge.trim else { continue }
            let points = try (0...16).map { try curve.point(at: trim.startParameter + (trim.endParameter - trim.startParameter) * Double($0) / 16,
                                                             tolerance: .standard) }
            // The edges running up the wall (not along a cap) meet the other half.
            guard let low = points.map(\.z).min(), let high = points.map(\.z).max(), high - low > h / 2 else { continue }
            for point in points {
                let cone = r + (topRadius - r) * point.z / h
                #expect(abs(hypot(point.x, point.y) - cone) < 1e-6, "\(point)")
            }
            checked += 1
        }
        #expect(checked == 2)
    }

    @Test(.timeLimit(.minutes(3)))
    func oppositeQuartersRebuiltFlatShareTheirNeighbours() throws {
        // Two opposite quarters of a drafted cylinder's cone, each rebuilt bilinear: they share
        // the caps and the quarters between them but no corner, so each one's edges are re-solved
        // in turn — the four edges up the wall on the cone, and the caps cut by both chords.
        let (r, h) = (0.01, 0.02)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let length = { (value: Double) in CADExpression.constant(.length(value, unit: .meter)) }
        let profile = try builder.sketch(on: .xy) { _ = $0.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(r)) }
        let extrusion = try builder.extrude(profile, distance: length(h), draftAngle: .constant(.angle(10, unit: .degree)))
        let walls = try faces(of: extrusion, in: builder) { !isPlane($0) }
        let before = try evaluate(builder)
        let top = try #require(before.brep.vertices.values.map(\.point).first { abs($0.z - h) < 1e-9 })
        let topRadius = hypot(top.x, top.y)
        // Opposite quarters: the first and the one whose corners it does not share.
        let first = try #require(walls.first)
        func corners(_ surface: Surface3D) throws -> [Point3D] {
            guard case let .bSpline(spline) = surface else { return [] }
            return [spline.controlPoints[0][0], spline.controlPoints[0][spline.controlPoints[0].count - 1]]
        }
        let opposite = try #require(try walls.first { wall in
            try corners(wall.1).allSatisfy { point in try corners(first.1).allSatisfy { (point - $0).length > 1e-6 } }
        })
        let rebuilt = try builder.rebuildFaces(target: extrusion, faces: [first.0, opposite.0],
                                               method: .explicit(SurfaceControlLayout(uDegree: 1, vDegree: 1, uSpans: 1, vSpans: 1)))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "rebuild"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let flats = evaluated.brep.faces.values.filter { face in
            guard case let .bSpline(surface)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return surface.uDegree == 1 && surface.vDegree == 1
        }
        #expect(flats.count == 2)
        var checked = 0
        for edgeID in Set(flats.flatMap { face in face.loops.flatMap { evaluated.brep.loops[$0]?.coedges.map(\.edgeID) ?? [] } }) {
            guard let edge = evaluated.brep.edges[edgeID], let curve = evaluated.brep.geometry.curves[edge.curveID], let trim = edge.trim else { continue }
            let points = try (0...16).map { try curve.point(at: trim.startParameter + (trim.endParameter - trim.startParameter) * Double($0) / 16,
                                                             tolerance: .standard) }
            guard let low = points.map(\.z).min(), let high = points.map(\.z).max(), high - low > h / 2 else { continue }
            for point in points {
                #expect(abs(hypot(point.x, point.y) - (r + (topRadius - r) * point.z / h)) < 1e-6, "\(point)")
            }
            checked += 1
        }
        #expect(checked == 4)
        _ = rebuilt
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
