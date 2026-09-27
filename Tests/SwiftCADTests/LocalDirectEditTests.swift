import Foundation
import Testing
@testable import SwiftCAD

/// Direct edits re-solve only the faces around the moved vertices, so they reach bodies with
/// curved faces elsewhere, sheets and non-convex solids, and a warped four-sided face becomes the
/// bilinear patch of its corners.
@Suite("Local direct edits")
struct LocalDirectEditTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: millimeters(x), y: millimeters(y))
    }

    /// A 40 × 20 × 10 mm box extruded from a rectangle centered on the origin.
    private func box(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(width: millimeters(40), height: millimeters(20))
        }
        return try builder.extrude(profile, distance: millimeters(10))
    }

    /// The stable reference of the first subshape of `featureID` matching `predicate`.
    private func reference(
        in builder: DocumentBuilder,
        of featureID: FeatureID,
        where predicate: (TopologyReference, BRepModel) -> Bool
    ) throws -> StableSubshapeReference {
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let subshapeID = try #require(evaluated.subshapes.entries.first { key, value in
            key.featureID == featureID && predicate(value, evaluated.brep)
        }?.key)
        return try builder.stableSubshape(subshapeID)
    }

    private func edgeMidpoint(_ reference: TopologyReference, _ model: BRepModel) -> Point3D? {
        guard case let .edge(id) = reference, let edge = model.edges[id],
              let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else { return nil }
        return Point3D(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, z: (a.z + b.z) / 2)
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test(.timeLimit(.minutes(1)))
    func anEdgeOfABoxWithAHoleMovesAndTheHoleStays() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: -0.005), axis: .unitZ, referenceDirection: .unitX),
            radius: millimeters(3), height: millimeters(20)
        )
        let holedID = try builder.boolean(targets: [boxID], tool: cylinderID, operation: .difference)
        // The bottom edge on the +X side runs along Y at x = 20 mm, z = 0.
        let edge = try reference(in: builder, of: holedID) { value, model in
            guard let mid = edgeMidpoint(value, model) else { return false }
            return near(mid.x, 0.020) && near(mid.z, 0) && near(mid.y, 0)
        }
        _ = try builder.moveEdge(target: holedID, edge: edge, direction: .unitX, distance: millimeters(5))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep

        try model.validate(level: .volumetric, tolerance: .standard)
        // The +X side leans out 5 mm at its foot: the section gains a 5 × 10 mm triangle.
        let hole = Double.pi * 0.003 * 0.003 * 0.010
        let expected = 0.040 * 0.020 * 0.010 + 0.5 * 0.005 * 0.010 * 0.020 - hole
        #expect(abs(try model.volume(tolerance: .standard) - expected) < 1e-12)
        #expect(model.geometry.surfaces.values.contains { if case .cylinder = $0 { return true }; return false })
    }

    @Test(.timeLimit(.minutes(1)))
    func aTopFaceOfAnLShapedSolidMovesUp() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let corners = [(0.0, 0.0), (30.0, 0.0), (30.0, 10.0), (10.0, 10.0), (10.0, 30.0), (0.0, 30.0)]
        let profile = try builder.sketch(on: .xy) { sketch in
            for index in corners.indices {
                let next = corners[(index + 1) % corners.count]
                _ = sketch.line(from: point(corners[index].0, corners[index].1), to: point(next.0, next.1))
            }
        }
        let extrudeID = try builder.extrude(profile, distance: millimeters(5))
        let top = try reference(in: builder, of: extrudeID) { value, model in
            guard case let .face(id) = value, let face = model.faces[id],
                  let points = try? model.orderedPoints(for: face.loops[0]) else { return false }
            return points.allSatisfy { near($0.z, 0.005) }
        }
        _ = try builder.moveFace(target: extrudeID, face: top, direction: .unitZ, distance: millimeters(3))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try model.volume(tolerance: .standard) - 0.0005 * 0.008) < 1e-13)
    }

    @Test(.timeLimit(.minutes(1)))
    func aVertexOfAnOpenBoxSheetWarpsItsQuadsIntoBilinearPatches() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let top = try reference(in: builder, of: boxID) { value, model in
            guard case let .face(id) = value, let face = model.faces[id],
                  let points = try? model.orderedPoints(for: face.loops[0]) else { return false }
            return points.allSatisfy { near($0.z, 0.010) }
        }
        let openID = try builder.faceDelete(target: boxID, faces: [top])
        // A rim corner of the open box.
        let corner = try reference(in: builder, of: openID) { value, model in
            guard case let .vertex(id) = value, let p = model.vertices[id]?.point else { return false }
            return near(p.x, 0.020) && near(p.y, 0.010) && near(p.z, 0.010)
        }
        // Pushed out diagonally, the corner leaves the planes of both walls it joins.
        _ = try builder.moveVertex(target: openID, vertex: corner, direction: Vector3D(x: 1, y: 1, z: 0), distance: millimeters(4))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep

        try model.validate(level: .exact, tolerance: .standard)
        #expect(model.bodies.values.first?.kind == .sheet)
        #expect(model.faces.count == 5)
        let bilinear = model.faces.values.filter { face in
            if case .bSpline = model.geometry.surfaces[face.surfaceID] { return true }
            return false
        }
        // The two walls meeting at the corner warp; the floor does not reach it.
        #expect(bilinear.count == 2)
        let offset = 0.004 / 2.0.squareRoot()
        #expect(model.vertices.values.contains { near($0.point.x, 0.020 + offset) && near($0.point.y, 0.010 + offset) && near($0.point.z, 0.010) })
        // Each warped wall still contains its straight edges: its corners lie on the patch.
        for face in bilinear {
            guard case let .bSpline(patch) = model.geometry.surfaces[face.surfaceID] else { continue }
            let corners = try model.orderedPoints(for: face.loops[0])
            for (u, v) in [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)] {
                let p = try Surface3D.bSpline(patch).point(u: u, v: v, tolerance: .standard)
                #expect(corners.contains { ($0 - p).length < 1e-12 })
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func anEdgeOfAnOpenBoxSheetMoves() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let top = try reference(in: builder, of: boxID) { value, model in
            guard case let .face(id) = value, let face = model.faces[id],
                  let points = try? model.orderedPoints(for: face.loops[0]) else { return false }
            return points.allSatisfy { near($0.z, 0.010) }
        }
        let openID = try builder.faceDelete(target: boxID, faces: [top])
        // The rim edge on the +X wall.
        let rim = try reference(in: builder, of: openID) { value, model in
            guard let mid = edgeMidpoint(value, model) else { return false }
            return near(mid.x, 0.020) && near(mid.z, 0.010) && near(mid.y, 0)
        }
        _ = try builder.moveEdge(target: openID, edge: rim, direction: .unitX, distance: millimeters(6))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep

        try model.validate(level: .exact, tolerance: .standard)
        #expect(model.bodies.values.first?.kind == .sheet)
        #expect(model.vertices.values.filter { near($0.point.x, 0.026) && near($0.point.z, 0.010) }.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func aVertexOfASolidWithACrossHoleWarpsTwoFacesAndKeepsItsVolumeExact() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        // A hole along Y through the ±Y walls, clear of the top face and the +X wall.
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: -0.015, z: 0.005), axis: .unitY, referenceDirection: .unitX),
            radius: millimeters(3), height: millimeters(30)
        )
        let holedID = try builder.boolean(targets: [boxID], tool: cylinderID, operation: .difference)
        let corner = try reference(in: builder, of: holedID) { value, model in
            guard case let .vertex(id) = value, let p = model.vertices[id]?.point else { return false }
            return near(p.x, 0.020) && near(p.y, 0.010) && near(p.z, 0.010)
        }
        _ = try builder.moveVertex(target: holedID, vertex: corner, direction: .unitX, distance: millimeters(3))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep

        try model.validate(level: .volumetric, tolerance: .standard)
        let warped = model.faces.values.filter { face in
            if case .bSpline = model.geometry.surfaces[face.surfaceID] { return true }
            return false
        }
        // Only the +X wall warps: the corner stays in the top plane and in the +Y wall's plane,
        // which keeps its hole.
        #expect(warped.count == 1)
        // Displacing one corner of a box by d along x adds d · Ly · Lz / 4 exactly.
        let expected = 0.040 * 0.020 * 0.010 + 0.003 * 0.020 * 0.010 / 4 - Double.pi * 0.003 * 0.003 * 0.020
        #expect(abs(try model.volume(tolerance: .standard) - expected) < 1e-12)
    }

    /// A 40 × 20 mm rectangle with 5 mm round corners, extruded 10 mm.
    private func roundedBox(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            let r = 5.0
            _ = sketch.line(from: point(-15, -10), to: point(15, -10))
            _ = sketch.line(from: point(20, -5), to: point(20, 5))
            _ = sketch.line(from: point(15, 10), to: point(-15, 10))
            _ = sketch.line(from: point(-20, 5), to: point(-20, -5))
            for (cx, cy, start) in [(15.0, -5.0, -90.0), (15.0, 5.0, 0.0), (-15.0, 5.0, 90.0), (-15.0, -5.0, 180.0)] {
                _ = sketch.arc(
                    center: point(cx, cy), radius: millimeters(r),
                    startAngle: .constant(.angle(start * .pi / 180, unit: .radian)),
                    endAngle: .constant(.angle((start + 90) * .pi / 180, unit: .radian))
                )
            }
        }
        return try builder.extrude(profile, distance: millimeters(10))
    }

    private func topFace(of featureID: FeatureID, in builder: DocumentBuilder, z: Double) throws -> StableSubshapeReference {
        try reference(in: builder, of: featureID) { value, model in
            guard case let .face(id) = value, let face = model.faces[id],
                  case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.z) - 1) < 1e-9 && near(plane.origin.z, z)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func theTopOfARoundedBoxPullsUpWithItsRoundCornersAndCannotSlideSideways() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let extrudeID = try roundedBox(&builder)
        let top = try topFace(of: extrudeID, in: builder, z: 0.010)
        var sideways = builder
        _ = try builder.moveFace(target: extrudeID, face: top, direction: .unitZ, distance: millimeters(5))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep

        try model.validate(level: .volumetric, tolerance: .standard)
        let area = 0.040 * 0.020 - (4 - Double.pi) * 0.005 * 0.005
        #expect(abs(try model.volume(tolerance: .standard) - area * 0.015) < 1e-12)
        #expect(model.geometry.curves.values.filter { if case .circle = $0 { return true }; return false }.count == 8)

        // Sliding the top sideways would slant the round corners' cylinders.
        _ = try sideways.moveFace(target: extrudeID, face: top, direction: .unitX, distance: millimeters(5))
        #expect(throws: (any Error).self) {
            _ = try CADPipeline(tolerance: .standard).evaluate(sideways.build())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aRoundedBoxTopOffsetsAlongItsNormalAndAnOpenBoxWallOffsets() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let extrudeID = try roundedBox(&builder)
        let top = try topFace(of: extrudeID, in: builder, z: 0.010)
        _ = try builder.offsetFace(target: extrudeID, face: top, distance: millimeters(4))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        let area = 0.040 * 0.020 - (4 - Double.pi) * 0.005 * 0.005
        #expect(abs(try model.volume(tolerance: .standard) - area * 0.014) < 1e-12)

        var sheet = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&sheet)
        let lid = try topFace(of: boxID, in: sheet, z: 0.010)
        let openID = try sheet.faceDelete(target: boxID, faces: [lid])
        let wall = try reference(in: sheet, of: openID) { value, model in
            guard case let .face(id) = value, let face = model.faces[id],
                  case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.x) - 1) < 1e-9 && near(plane.origin.x, 0.020)
        }
        _ = try sheet.offsetFace(target: openID, face: wall, distance: millimeters(3))
        let open = try CADPipeline(tolerance: .standard).evaluate(sheet.build()).brep
        try open.validate(level: .exact, tolerance: .standard)
        #expect(open.bodies.values.first?.kind == .sheet)
        // The wall's front faces out of the box, so it moves outward.
        let xs = open.vertices.values.map(\.point.x)
        #expect(abs((xs.max() ?? 0) - 0.023) < 1e-9)
        #expect(abs((xs.min() ?? 0) + 0.020) < 1e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCylinderCapMovesAsAFace() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let cylinderID = try builder.cylinder(radius: millimeters(10), height: millimeters(20))
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        let topZ = evaluated.vertices.values.map(\.point.z).max() ?? 0
        let top = try topFace(of: cylinderID, in: builder, z: topZ)
        _ = try builder.moveFace(target: cylinderID, face: top, direction: .unitZ, distance: millimeters(-5))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try model.volume(tolerance: .standard) - Double.pi * 0.010 * 0.010 * 0.015) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aVertexOnAHoledFaceIsRefused() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: -0.005), axis: .unitZ, referenceDirection: .unitX),
            radius: millimeters(3), height: millimeters(20)
        )
        let holedID = try builder.boolean(targets: [boxID], tool: cylinderID, operation: .difference)
        let corner = try reference(in: builder, of: holedID) { value, model in
            guard case let .vertex(id) = value, let p = model.vertices[id]?.point else { return false }
            return near(p.x, 0.020) && near(p.y, 0.010) && near(p.z, 0.010)
        }
        // Lifting the corner warps the top face, whose hole keeps it from being a bilinear patch.
        _ = try builder.moveVertex(target: holedID, vertex: corner, direction: .unitZ, distance: millimeters(4))
        #expect(throws: (any Error).self) {
            _ = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        }
    }
}
