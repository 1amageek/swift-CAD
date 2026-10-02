import Foundation
import Testing
@testable import SwiftCAD

/// Draft Face turns faces about their crossing with the neutral plane so each makes the draft
/// angle with the pull direction: a box's walls taper into a frustum of a pyramid, a cylinder into
/// a frustum of a cone, and a face crossing the neutral plane turns as one plane about that
/// crossing — out on the far side from the pull, in beyond the plane.
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
    func aWallCrossingAnOffsetNeutralPlaneTurnsAboutItsCrossing() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        let boxID = try builder.extrude(profile, distance: millimeters(10))
        let wall = try faces(in: builder, of: boxID) { plane($0).map { abs($0.normal.x) > 0.5 && $0.origin.x > 0 } ?? false }
        let bottom = try #require(try faces(in: builder, of: boxID, where: isBottom).first)
        // The bottom faces down, so moving the neutral plane -5 mm along it lifts it to mid-height:
        // the wall turns as one plane about its crossing there, out above it (away from the bottom)
        // and in below, the wedge added above taken off below.
        _ = try builder.faceDraft(target: boxID, faces: wall, neutralFace: bottom, angle: degrees(5), neutralOffset: millimeters(-5))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try model.volume(tolerance: .standard) - 0.040 * 0.020 * 0.010) < 1e-12)
        #expect(model.faces.count == 6)
        // The wall leans: one plane, neither upright nor parallel to the bottom.
        let wallPlanes = model.faces.values.compactMap { model.geometry.surfaces[$0.surfaceID].flatMap(plane) }
            .filter { abs($0.normal.x) > 0.5 && abs($0.normal.z) > 1e-6 }
        #expect(wallPlanes.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func everyWallAboutAMidHeightNeutralPlaneTapersThroughIt() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        let boxID = try builder.extrude(profile, distance: millimeters(10))
        let walls = try faces(in: builder, of: boxID) { plane($0).map { abs($0.normal.z) < 1e-9 } ?? false }
        let bottom = try #require(try faces(in: builder, of: boxID, where: isBottom).first)
        _ = try builder.faceDraft(target: boxID, faces: walls, neutralFace: bottom, angle: degrees(5), neutralOffset: millimeters(-5))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        // One frustum through the 40 × 20 mm section at mid-height, each wall out by d = (z − 5) t
        // mm: the section (40 + 2d)(20 + 2d) over z in 0...10 gives 8000 + 1000 t² / 3 mm³.
        let t = tan(5 * Double.pi / 180)
        #expect(abs(try model.volume(tolerance: .standard) - (8000 + 1000 * t * t / 3) * 1e-9) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCylinderAboutAMidHeightNeutralPlaneTapersThroughIt() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let cylinderID = try builder.cylinder(radius: millimeters(10), height: millimeters(20))
        let side = try faces(in: builder, of: cylinderID) { surface in
            if case .cylinder = surface { return true }
            if case .analytic(.cylinder) = surface { return true }
            return false
        }
        let bottom = try #require(try faces(in: builder, of: cylinderID, where: isBottom).first)
        _ = try builder.faceDraft(target: cylinderID, faces: side, neutralFace: bottom, angle: degrees(5), neutralOffset: millimeters(-10))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        // One cone through the 10 mm circle at mid-height: wider by tan 5° per unit above it,
        // narrower below.
        let t = tan(5 * Double.pi / 180)
        let (bottomRadius, topRadius) = (0.010 + 0.010 * t, 0.010 - 0.010 * t)
        let expected = Double.pi * 0.020 / 3 * (bottomRadius * bottomRadius + bottomRadius * topRadius + topRadius * topRadius)
        #expect(abs(try model.volume(tolerance: .standard) - expected) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aUShapedWallCrossedFourTimesTurnsAsOnePlane() throws {
        // A U-shaped block (40 wide, a 20 × 6 mm notch from the top), 10 mm deep along y, its
        // front wall drafted about a plane 3 mm below its top, which crosses the wall four times:
        // the wall still turns as one plane about that crossing.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let outline = [(0.0, 0.0), (40.0, 0.0), (40.0, 12.0), (30.0, 12.0), (30.0, 6.0), (10.0, 6.0), (10.0, 12.0), (0.0, 12.0)]
        // On the ZX plane sketch x is world z and sketch y is world x.
        let profile = try builder.sketch(on: .zx) { sketch in
            for k in outline.indices {
                let (a, b) = (outline[k], outline[(k + 1) % outline.count])
                _ = sketch.line(from: SketchPoint(x: millimeters(a.1), y: millimeters(a.0)), to: SketchPoint(x: millimeters(b.1), y: millimeters(b.0)))
            }
        }
        let block = try builder.extrude(profile, distance: millimeters(10))
        let front = try faces(in: builder, of: block) { plane($0).map { abs(abs($0.normal.y) - 1) < 1e-9 } ?? false }
        #expect(front.count == 2)
        let bottom = try #require(try faces(in: builder, of: block) { plane($0).map { $0.normal.z < -0.5 } ?? false }.first)
        // The bottom faces down: -9 mm along it puts the plane 9 mm up, crossing the U's arms
        // (6..12 mm) and above the notch's floor (6 mm).
        _ = try builder.faceDraft(target: block, faces: [front[0]], neutralFace: bottom, angle: degrees(5), neutralOffset: millimeters(-9))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        // The face moves out by (z − 9) t mm (out above the plane, away from the bottom; in below):
        // over the full 40 mm for z in 0...6 that takes 1440 t; over the arms' 20 mm for z in 6...12
        // it adds as much as it takes; on the 360 mm² × 10 mm block.
        let t = tan(5 * Double.pi / 180)
        let volume = try model.volume(tolerance: .standard)
        #expect(abs(volume - (3600 - 1440 * t) * 1e-9) < 1e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(1)))
    func aDrilledWallTurnsAboutAMidHeightNeutralPlaneThroughItsHole() throws {
        // A 40 × 20 × 10 mm box with a 2 mm hole along y through its middle; its front wall
        // drafted about the mid-height plane, which runs through the hole.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        let box = try builder.extrude(profile, distance: millimeters(10))
        // On the ZX plane sketch x is world z and sketch y is world x.
        let circle = try builder.sketch(on: .zx) { _ = $0.circle(center: SketchPoint(x: millimeters(5), y: millimeters(0)), radius: millimeters(2)) }
        let drilled = FeatureID()
        try builder.append(id: drilled, name: "Hole", operation: .extrude(ExtrudeFeature(
            profile: circle, distance: millimeters(30), direction: .symmetric, operation: .difference,
            targets: [BooleanTargetReference(featureID: box)])))
        let front = try faces(in: builder, of: drilled) { plane($0).map { $0.normal.y * $0.origin.y > 0.009 * abs($0.normal.y) && abs(abs($0.normal.y) - 1) < 1e-9 } ?? false }
        let bottom = try #require(try faces(in: builder, of: drilled, where: isBottom).first)
        _ = try builder.faceDraft(target: drilled, faces: [try #require(front.first)], neutralFace: bottom, angle: degrees(5), neutralOffset: millimeters(-5))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        // The wall moves out by (z − 5) t mm, antisymmetric about z = 5 over both the face and the
        // hole's disc, so the volume stays; the hole's wall now meets the wall along an ellipse.
        let volume = try model.volume(tolerance: .standard)
        #expect(abs(volume - (8000 - 80 * Double.pi) * 1e-9) < 1e-12, "\(volume)")
        let ellipses = model.edges.values.filter { edge in
            if case .analytic(.ellipse)? = model.geometry.curves[edge.curveID] { return true }
            return false
        }
        #expect(ellipses.isEmpty == false)
    }
}

