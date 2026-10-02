import Foundation
import Testing
@testable import SwiftCAD

/// Push Face moves faces along their outward side onto their offset surfaces and re-solves the
/// edges and vertices around them from the surfaces: planes shift, cylinders change radius, the
/// faces beside can tilt by an adjacent angle, and a push that would turn an edge around is refused.
@Suite("Push Face")
struct PushFaceTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }
    private func degrees(_ value: Double) -> CADExpression { .constant(.angle(value * .pi / 180, unit: .radian)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: millimeters(x), y: millimeters(y)) }

    /// A 40 × 20 × 10 mm box extruded from a rectangle centered on the origin.
    private func box(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(width: millimeters(40), height: millimeters(20))
        }
        return try builder.extrude(profile, distance: millimeters(10))
    }

    /// A 40 × 20 mm rectangle with 5 mm round corners, extruded 10 mm.
    private func roundedBox(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: point(-15, -10), to: point(15, -10))
            _ = sketch.line(from: point(20, -5), to: point(20, 5))
            _ = sketch.line(from: point(15, 10), to: point(-15, 10))
            _ = sketch.line(from: point(-20, 5), to: point(-20, -5))
            for (cx, cy, start) in [(15.0, -5.0, -90.0), (15.0, 5.0, 0.0), (-15.0, 5.0, 90.0), (-15.0, -5.0, 180.0)] {
                _ = sketch.arc(
                    center: point(cx, cy), radius: millimeters(5),
                    startAngle: .constant(.angle(start * .pi / 180, unit: .radian)),
                    endAngle: .constant(.angle((start + 90) * .pi / 180, unit: .radian))
                )
            }
        }
        return try builder.extrude(profile, distance: millimeters(10))
    }

    /// The stable references of the faces of `featureID` matching `predicate`.
    private func faces(
        in builder: DocumentBuilder,
        of featureID: FeatureID,
        where predicate: (Surface3D) -> Bool
    ) throws -> [StableSubshapeReference] {
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        return try evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == featureID, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return predicate(surface)
        }
        .map(\.key).sorted().map { try builder.stableSubshape($0) }
    }

    private func isPlane(_ surface: Surface3D, normal: Vector3D, at offset: Double) -> Bool {
        guard case let .plane(plane) = surface, abs(abs(plane.normal.dot(normal)) - 1) < 1e-9 else { return false }
        return abs((plane.origin - .origin).dot(normal) - offset) < 1e-9
    }

    private func solid(_ builder: DocumentBuilder) throws -> BRepModel {
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        return model
    }

    @Test(.timeLimit(.minutes(1)))
    func topAndSideOfABoxPushTogether() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let top = try faces(in: builder, of: boxID) { isPlane($0, normal: .unitZ, at: 0.010) }
        let side = try faces(in: builder, of: boxID) { isPlane($0, normal: .unitX, at: 0.020) }
        _ = try builder.offsetFace(target: boxID, faces: top + side, distance: millimeters(2))
        let model = try solid(builder)
        #expect(model.faces.count == 6)
        #expect(abs(try model.volume(tolerance: .standard) - 0.042 * 0.020 * 0.012) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func theWallsOfARoundedBoxPushOutWithTheirRoundCorners() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try roundedBox(&builder)
        let walls = try faces(in: builder, of: boxID) { surface in
            if case .cylinder = surface { return true }
            guard case let .plane(plane) = surface else { return false }
            return abs(plane.normal.z) < 1e-9
        }
        #expect(walls.count == 8)
        _ = try builder.offsetFace(target: boxID, faces: walls, distance: millimeters(2))
        let model = try solid(builder)
        // A 44 × 24 mm rectangle with 7 mm round corners, 10 mm deep.
        let area = 0.044 * 0.024 - (4 - Double.pi) * 0.007 * 0.007
        #expect(abs(try model.volume(tolerance: .standard) - area * 0.010) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCylinderSidePushesToALargerRadius() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let cylinderID = try builder.cylinder(radius: millimeters(10), height: millimeters(20))
        let side = try faces(in: builder, of: cylinderID) { surface in
            if case .cylinder = surface { return true }
            if case .analytic(.cylinder) = surface { return true }
            return false
        }
        #expect(side.isEmpty == false)
        _ = try builder.offsetFace(target: cylinderID, faces: side, distance: millimeters(2))
        let model = try solid(builder)
        #expect(abs(try model.volume(tolerance: .standard) - Double.pi * 0.012 * 0.012 * 0.020) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aHolePushedOutOfTheMaterialNarrows() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let drill = try builder.cylinder(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: -0.005), axis: .unitZ, referenceDirection: .unitX),
            radius: millimeters(5), height: millimeters(20)
        )
        let drilled = try builder.boolean(targets: [boxID], tool: drill, operation: .difference)
        let hole = try faces(in: builder, of: drilled) { surface in
            if case .cylinder = surface { return true }
            if case .analytic(.cylinder) = surface { return true }
            return false
        }
        #expect(hole.isEmpty == false)
        _ = try builder.offsetFace(target: drilled, faces: hole, distance: millimeters(1))
        let model = try solid(builder)
        // The hole's outward side faces its axis, so the push narrows it to a 4 mm radius.
        #expect(abs(try model.volume(tolerance: .standard) - (0.040 * 0.020 - Double.pi * 0.004 * 0.004) * 0.010) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func theFacesBesideAPushedTopTiltByTheAdjacentAngle() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let top = try faces(in: builder, of: boxID) { isPlane($0, normal: .unitZ, at: 0.010) }
        _ = try builder.offsetFace(target: boxID, faces: top, distance: millimeters(5), adjacentAngle: degrees(10))
        let model = try solid(builder)
        // Each wall turns about its top edge, leaning out above it and in below it.
        let slope = tan(10 * Double.pi / 180)
        let steps = 2_000
        let volume = (0..<steps).reduce(0.0) { sum, index in
            let z = (Double(index) + 0.5) * 0.015 / Double(steps)
            let grown = (z - 0.010) * slope
            return sum + (0.040 + 2 * grown) * (0.020 + 2 * grown) * 0.015 / Double(steps)
        }
        #expect(abs(try model.volume(tolerance: .standard) - volume) < 1e-10)
        let highest = model.vertices.values.map(\.point.z).max() ?? 0
        let widest = model.vertices.values.filter { abs($0.point.z - highest) < 1e-9 }.map(\.point.x).max() ?? 0
        #expect(abs(highest - 0.015) < 1e-12)
        #expect(abs(widest - (0.020 + 0.005 * slope)) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aPushThatWouldTurnAnEdgeAroundIsRefused() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let side = try faces(in: builder, of: boxID) { isPlane($0, normal: .unitX, at: 0.020) }
        _ = try builder.offsetFace(target: boxID, faces: side, distance: millimeters(-50))
        #expect(throws: (any Error).self) {
            _ = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        }
    }

    /// An L-shaped prism (a 20 mm square less its 10 mm corner, 20 mm tall) whose inner step
    /// face, at x = 10 mm, is pushed 15 mm out past the outer wall at x = 20 mm.
    private func pushedStep(_ grow: FaceEditGrow) throws -> BRepModel {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let corners = [(0.0, 0.0), (20.0, 0.0), (20.0, 10.0), (10.0, 10.0), (10.0, 20.0), (0.0, 20.0)]
        let profile = try builder.sketch(on: .xy) { sketch in
            for k in corners.indices {
                let (a, b) = (corners[k], corners[(k + 1) % corners.count])
                _ = sketch.line(from: point(a.0, a.1), to: point(b.0, b.1))
            }
        }
        let body = try builder.extrude(profile, distance: millimeters(20))
        let step = try faces(in: builder, of: body) { isPlane($0, normal: .unitX, at: 0.010) }
        #expect(step.count == 1)
        _ = try builder.offsetFace(target: body, faces: step, distance: millimeters(15), grow: grow)
        return try solid(builder)
    }

    /// Grow, as the official video shows: Moving pushes the wall along (the square grows by the
    /// rest, 25 × 20 × 20 mm³), Fixed stops at it (the 20 mm cube), None keeps going alone (a
    /// 15 × 10 mm bar sticking out past the wall, 6000 + 3000 mm³).
    @Test(.timeLimit(.minutes(2)), arguments: [(FaceEditGrow.moving, 10_000.0, 6), (FaceEditGrow.fixed, 8_000.0, 6),
                                                (FaceEditGrow.none, 9_000.0, 8)])
    func aStepPushedPastTheWallGrowsByItsMode(grow: FaceEditGrow, volume: Double, faces count: Int) throws {
        let model = try pushedStep(grow)
        let measured = try model.volume(tolerance: .standard)
        #expect(abs(measured - volume * 1e-9) < 1e-15, "\(grow) \(measured)")
        #expect(model.faces.count == count, "\(grow) \(model.faces.count)")
    }
}

