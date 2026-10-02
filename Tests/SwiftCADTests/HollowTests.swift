import Foundation
import Testing
@testable import SwiftCAD

/// Hollow walls a solid by the thickness asked for — inside it when negative, outside it (the solid
/// the cavity) when positive: open through the chosen faces, or closed when none are chosen,
/// whatever faces bound it; an inward thickness the solid cannot take is refused.
@Suite("Hollow")
struct HollowTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: millimeters(x), y: millimeters(y)) }

    private func box(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        return try builder.extrude(profile, distance: millimeters(10))
    }

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

    private func faces(in builder: DocumentBuilder, of featureID: FeatureID, where predicate: (Surface3D) -> Bool) throws -> [StableSubshapeReference] {
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        return try evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == featureID, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return predicate(surface)
        }.map(\.key).sorted().map { try builder.stableSubshape($0) }
    }

    private func isTop(_ surface: Surface3D, at z: Double) -> Bool {
        guard case let .plane(plane) = surface else { return false }
        return abs(abs(plane.normal.z) - 1) < 1e-9 && abs(plane.origin.z - z) < 1e-9
    }

    private func solid(_ builder: DocumentBuilder) throws -> BRepModel {
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        return model
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxOpensThroughItsTop() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let top = try faces(in: builder, of: boxID) { isTop($0, at: 0.010) }
        _ = try builder.shell(target: boxID, removing: top, thickness: millimeters(-2))
        let model = try solid(builder)
        #expect(model.faces.count == 11)
        #expect(abs(try model.volume(tolerance: .standard) - (0.040 * 0.020 * 0.010 - 0.036 * 0.016 * 0.008)) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxWithNoOpeningHasAClosedVoid() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        _ = try builder.shell(target: boxID, removing: [], thickness: millimeters(-2))
        let model = try solid(builder)
        #expect(model.shells.count == 2)
        #expect(abs(try model.volume(tolerance: .standard) - (0.040 * 0.020 * 0.010 - 0.036 * 0.016 * 0.006)) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func twoFacesOpenTogether() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let top = try faces(in: builder, of: boxID) { isTop($0, at: 0.010) }
        let side = try faces(in: builder, of: boxID) { surface in
            guard case let .plane(plane) = surface else { return false }
            return abs(abs(plane.normal.x) - 1) < 1e-9 && plane.origin.x > 0.019
        }
        _ = try builder.shell(target: boxID, removing: top + side, thickness: millimeters(-2))
        let model = try solid(builder)
        #expect(abs(try model.volume(tolerance: .standard) - (0.040 * 0.020 * 0.010 - 0.038 * 0.016 * 0.008)) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCylinderAndARoundedBoxHollowThroughTheirTops() throws {
        var cylinder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let cylinderID = try cylinder.cylinder(radius: millimeters(10), height: millimeters(20))
        let cylinderTop = try faces(in: cylinder, of: cylinderID) { isTop($0, at: 0.020) }
        _ = try cylinder.shell(target: cylinderID, removing: cylinderTop, thickness: millimeters(-1))
        #expect(abs(try solid(cylinder).volume(tolerance: .standard) - Double.pi * (0.010 * 0.010 * 0.020 - 0.009 * 0.009 * 0.019)) < 1e-12)

        var rounded = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let roundedID = try roundedBox(&rounded)
        let roundedTop = try faces(in: rounded, of: roundedID) { isTop($0, at: 0.010) }
        _ = try rounded.shell(target: roundedID, removing: roundedTop, thickness: millimeters(-2))
        let outer = 0.040 * 0.020 - (4 - Double.pi) * 0.005 * 0.005
        let inner = 0.036 * 0.016 - (4 - Double.pi) * 0.003 * 0.003
        #expect(abs(try solid(rounded).volume(tolerance: .standard) - (outer * 0.010 - inner * 0.008)) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aPositiveThicknessWallsTheSolidOutside() throws {
        // Open through the top: the 44 × 24 mm outer walls from z = −2 to the top, less the box with
        // its top run up through them.
        var open = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let openID = try box(&open)
        let top = try faces(in: open, of: openID) { isTop($0, at: 0.010) }
        _ = try open.shell(target: openID, removing: top, thickness: millimeters(2))
        let opened = try solid(open)
        #expect(opened.bodies.count == 1 && opened.faces.count == 11)
        #expect(abs(try opened.volume(tolerance: .standard) - (0.044 * 0.024 * 0.012 - 0.040 * 0.020 * 0.010)) < 1e-12)

        // Closed: the box itself becomes the void inside 44 × 24 × 14 mm.
        var closed = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let closedID = try box(&closed)
        _ = try closed.shell(target: closedID, removing: [], thickness: millimeters(6))
        let walled = try solid(closed)
        #expect(walled.shells.count == 2)
        #expect(abs(try walled.volume(tolerance: .standard) - (0.052 * 0.032 * 0.022 - 0.040 * 0.020 * 0.010)) < 1e-12)

        // A cylinder open at its top: r 11 mm from z = −1 to 20, less the r 10 mm bore.
        var cylinder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let cylinderID = try cylinder.cylinder(radius: millimeters(10), height: millimeters(20))
        let cylinderTop = try faces(in: cylinder, of: cylinderID) { isTop($0, at: 0.020) }
        _ = try cylinder.shell(target: cylinderID, removing: cylinderTop, thickness: millimeters(1))
        #expect(abs(try solid(cylinder).volume(tolerance: .standard) - Double.pi * (0.011 * 0.011 * 0.021 - 0.010 * 0.010 * 0.020)) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aThicknessTheSolidCannotTakeIsRefused() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        _ = try builder.shell(target: boxID, removing: [], thickness: millimeters(-6))
        #expect(throws: (any Error).self) {
            _ = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        }
    }
}
