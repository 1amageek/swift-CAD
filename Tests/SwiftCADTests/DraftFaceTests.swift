import Foundation
import Testing
@testable import SwiftCAD

/// Draft Face turns faces about their crossing with the neutral plane so each makes the draft
/// angle with the pull direction: a box's walls taper into a frustum of a pyramid, a cylinder into
/// a frustum of a cone, and a face crossing the neutral plane is refused.
@Suite("Draft Face")
struct DraftFaceTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }
    private func degrees(_ value: Double) -> CADExpression { .constant(.angle(value * .pi / 180, unit: .radian)) }

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

    private func plane(_ surface: Surface3D) -> Plane3D? {
        if case let .plane(plane) = surface { return plane }
        return nil
    }

    private func isBottom(_ surface: Surface3D) -> Bool {
        guard let plane = plane(surface) else { return false }
        return abs(abs(plane.normal.z) - 1) < 1e-9 && abs(plane.origin.z) < 1e-9
    }

    @Test(.timeLimit(.minutes(1)))
    func theWallsOfABoxTaperIntoAFrustum() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        let boxID = try builder.extrude(profile, distance: millimeters(10))
        let walls = try faces(in: builder, of: boxID) { plane($0).map { abs($0.normal.z) < 1e-9 } ?? false }
        let bottom = try #require(try faces(in: builder, of: boxID, where: isBottom).first)
        #expect(walls.count == 4)
        _ = try builder.faceDraft(target: boxID, faces: walls, neutralFace: bottom, angle: degrees(5))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        // Each wall leans out by tan 5° per unit of height above the bottom.
        let t = tan(5 * Double.pi / 180)
        let h = 0.010
        let expected = 0.040 * 0.020 * h + (0.040 + 0.020) * t * h * h + 4 * t * t * h * h * h / 3
        #expect(abs(try model.volume(tolerance: .standard) - expected) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCylinderTapersIntoAFrustumOfACone() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let cylinderID = try builder.cylinder(radius: millimeters(10), height: millimeters(20))
        let side = try faces(in: builder, of: cylinderID) { surface in
            if case .cylinder = surface { return true }
            if case .analytic(.cylinder) = surface { return true }
            return false
        }
        let bottom = try #require(try faces(in: builder, of: cylinderID, where: isBottom).first)
        _ = try builder.faceDraft(target: cylinderID, faces: side, neutralFace: bottom, angle: degrees(-5))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        // A negative angle leans the side in: the radius shrinks by tan 5° per unit of height.
        let r = 0.010
        let top = r - 0.020 * tan(5 * Double.pi / 180)
        let expected = Double.pi * 0.020 / 3 * (r * r + r * top + top * top)
        #expect(abs(try model.volume(tolerance: .standard) - expected) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aFaceCrossingAnOffsetNeutralPlaneIsRefused() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        let boxID = try builder.extrude(profile, distance: millimeters(10))
        let wall = try faces(in: builder, of: boxID) { plane($0).map { abs($0.normal.x) > 0.5 && $0.origin.x > 0 } ?? false }
        let bottom = try #require(try faces(in: builder, of: boxID, where: isBottom).first)
        // The bottom faces down, so moving the neutral plane -5 mm along it lifts it to mid-height.
        _ = try builder.faceDraft(target: boxID, faces: wall, neutralFace: bottom, angle: degrees(5), neutralOffset: millimeters(-5))
        #expect(throws: (any Error).self) {
            _ = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        }
    }
}
