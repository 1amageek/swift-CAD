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

    /// A 30 × 10 × 10 mm block with a 10 × 5 mm notch along its top edge at x = 0 (open at x = 0
    /// and the top), its notch wall (x = 10, z 5...10, facing -x) drafted 70° about the top face:
    /// the wall's foot swings out past the block's end, so the in-place re-solve cannot close it.
    private func notchWallDrafted70(grow: FaceEditGrow) throws -> BRepModel {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let outline = [(0.0, 0.0), (30.0, 0.0), (30.0, 10.0), (10.0, 10.0), (10.0, 5.0), (0.0, 5.0)]
        // On the ZX plane sketch x is world z and sketch y is world x.
        let profile = try builder.sketch(on: .zx) { sketch in
            for k in outline.indices {
                let (a, b) = (outline[k], outline[(k + 1) % outline.count])
                _ = sketch.line(from: SketchPoint(x: millimeters(a.1), y: millimeters(a.0)), to: SketchPoint(x: millimeters(b.1), y: millimeters(b.0)))
            }
        }
        let block = try builder.extrude(profile, distance: millimeters(10))
        let wall = try faces(in: builder, of: block) { plane($0).map { abs(abs($0.normal.x) - 1) < 1e-9 && abs($0.origin.x - 0.010) < 1e-9 } ?? false }
        let top = try faces(in: builder, of: block) { plane($0).map { abs(abs($0.normal.z) - 1) < 1e-9 && abs($0.origin.z - 0.010) < 1e-9 } ?? false }
        #expect(wall.count == 1)
        #expect(top.count == 1)
        _ = try builder.faceDraft(target: block, faces: wall, neutralFace: try #require(top.first), angle: degrees(70), grow: grow)
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        return model
    }

    @Test(.timeLimit(.minutes(1)))
    func aWallDraftedIntoTheBlocksEndRampsToTheBottomUnderMoving() throws {
        // Moving: the drafted face grows down to the block's bottom, the walls beside it carried
        // along — a ramp from the top edge past the block's end. Section 200 + 50 t mm².
        let model = try notchWallDrafted70(grow: .moving)
        let t = tan(70 * Double.pi / 180)
        let volume = try model.volume(tolerance: .standard)
        #expect(abs(volume - (200 + 50 * t) * 10 * 1e-9) < 1e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(1)))
    func aWallDraftedIntoTheBlocksEndStopsAtItUnderFixed() throws {
        // Fixed: the drafted face stops at the block's end (x = 0) and bottom; the other faces stay.
        // Section 300 − 50 / t mm².
        let model = try notchWallDrafted70(grow: .fixed)
        let t = tan(70 * Double.pi / 180)
        let volume = try model.volume(tolerance: .standard)
        #expect(abs(volume - (300 - 50 / t) * 10 * 1e-9) < 1e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(1)))
    func aWallDraftedIntoTheBlocksEndPokesOutAloneUnderNone() throws {
        // None: the drafted face fills the notch over its own floor (z = 5) and pokes out past
        // the block's end as a slab over that floor's plane. Section 250 + 12.5 t mm².
        let model = try notchWallDrafted70(grow: .none)
        let t = tan(70 * Double.pi / 180)
        let volume = try model.volume(tolerance: .standard)
        #expect(abs(volume - (250 + 12.5 * t) * 10 * 1e-9) < 1e-12, "\(volume)")
    }

    /// A 4 × 10 × 10 mm plate (centred on x and y), its wall at x = −2 drafted 30° into it about
    /// the top face: the wall's foot would move 10 tan 30° mm in, past the far wall.
    private func plateWallDraftedIn(grow: FaceEditGrow) throws -> BRepModel {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(4), height: millimeters(10)) }
        let plate = try builder.extrude(profile, distance: millimeters(10))
        let wall = try faces(in: builder, of: plate) { plane($0).map { abs(abs($0.normal.x) - 1) < 1e-9 && abs($0.origin.x + 0.002) < 1e-9 } ?? false }
        let top = try faces(in: builder, of: plate) { plane($0).map { abs(abs($0.normal.z) - 1) < 1e-9 && abs($0.origin.z - 0.010) < 1e-9 } ?? false }
        #expect(wall.count == 1)
        #expect(top.count == 1)
        _ = try builder.faceDraft(target: plate, faces: wall, neutralFace: try #require(top.first), angle: degrees(-30), grow: grow)
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        return model
    }

    @Test(.timeLimit(.minutes(1)), arguments: [FaceEditGrow.moving, .fixed, .none])
    func aWallDraftedThroughAPlateCutsItAway(grow: FaceEditGrow) throws {
        // The drafted face cuts through the far wall at z = 10 − 4 / tan 30°, taking off all the
        // plate below it: what is left is the triangle above it, 2 · 4² / tan 30° mm² over 10 mm.
        let model = try plateWallDraftedIn(grow: grow)
        let t = tan(30 * Double.pi / 180)
        let volume = try model.volume(tolerance: .standard)
        #expect(abs(volume - 8 / t * 10 * 1e-9) < 1e-12, "\(volume)")
        #expect(model.faces.count == 5)
    }

    /// A 40 × 20 mm block (centred) whose top is a cylinder along x (radius 30 mm, axis at y = 0,
    /// z = -15), its top matched onto a roller of another body; and the block's feature.
    private func cylinderToppedBlock(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        let box = try builder.extrude(profile, distance: millimeters(10))
        // On the YZ plane sketch x is world y and sketch y is world z.
        let circle = try builder.sketch(on: .yz) { _ = $0.circle(center: SketchPoint(x: millimeters(0), y: millimeters(-15)), radius: millimeters(30)) }
        let roller = try builder.extrude(circle, distance: millimeters(40))
        let rollerFace = try #require(try faces(in: builder, of: roller) { surface in
            if case .cylinder = surface { return true }
            if case .analytic(.cylinder) = surface { return true }
            return false
        }.first)
        let top = try #require(try faces(in: builder, of: box) { plane($0).map { $0.normal.z > 0.5 && abs($0.origin.z - 0.010) < 1e-9 } ?? false }.first)
        return try builder.matchFace(target: box, faces: [top], source: roller, referenceFace: rollerFace)
    }

    @Test(.timeLimit(.minutes(1)))
    func aWallTurnsAboutItsStraightEdgeOnACurvedReference() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let block = try cylinderToppedBlock(&builder)
        let isCylinder: (Surface3D) -> Bool = { surface in
            if case .cylinder = surface { return true }
            if case .analytic(.cylinder) = surface { return true }
            return false
        }
        let top = try #require(try faces(in: builder, of: block, where: isCylinder).first)
        let wall = try faces(in: builder, of: block) { plane($0).map { abs($0.normal.y - 1) < 1e-9 } ?? false }
        #expect(wall.count == 1)
        _ = try builder.faceDraft(target: block, faces: wall, neutralFace: top, angle: degrees(30))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        // The wall (y = 10) turns about its top edge (z = h = √800 − 15), pulled along the
        // cylinder's normal there (0, 1/3, √8/3): its rulings run down along −pull + across·tan 30°,
        // moving out by k mm per mm of drop, which adds ½ h² k mm² over the 40 mm.
        let pull = Vector3D(x: 0, y: 1.0 / 3, z: 8.0.squareRoot() / 3)
        let across = Vector3D(x: 0, y: 8.0.squareRoot() / 3, z: -1.0 / 3)
        let running = pull * -1 + across * tan(30 * Double.pi / 180)
        let k = running.y / -running.z
        let h = 800.0.squareRoot() - 15
        let arcArea = 10 * 800.0.squareRoot() + 900 * asin(1.0 / 3)
        let expected = (40 * (arcArea - 300) + 40 * h * h * k / 2) * 1e-9
        // The model also holds the roller, π 30² 40 mm³.
        let volume = try model.volume(tolerance: .standard) - Double.pi * 900 * 40 * 1e-9
        #expect(abs(volume - expected) < 1e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(1)))
    func aWallMeetingACurvedReferenceAlongAnArcTurnsIntoTheConeOfItsRulings() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let block = try cylinderToppedBlock(&builder)
        let top = try #require(try faces(in: builder, of: block) { surface in
            if case .cylinder = surface { return true }
            if case .analytic(.cylinder) = surface { return true }
            return false
        }.first)
        // The end wall (x = 20) meets the cylinder along an arc: at each point of it the wall leans
        // out along x by tan 30° per mm of depth along the cylinder's normal there, so it turns
        // into a ruled surface whose rulings run in toward the cylinder's axis, meeting there.
        let end = try faces(in: builder, of: block) { plane($0).map { $0.normal.x > 0.5 } ?? false }
        _ = try builder.faceDraft(target: block, faces: end, neutralFace: top, angle: degrees(30))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        // Its ruled lines meet on the cylinder's axis: the wall is the cone through the arc from there.
        #expect(model.geometry.surfaces.values.contains { if case .analytic(.cone) = $0 { return true }; return false })
        // A point of the wall's section r mm from the axis (y = 0, z = -15) lies 30 − r below the
        // arc along the normal, so the wall moves out (30 − r) tan 30° there: the added volume is
        // tan 30° ∬ (30 − r) over the section under the arc above z = 0, by Gauss–Legendre.
        let nodes = [-0.9739065285171717, -0.8650633666889845, -0.6794095682990244, -0.4333953941292472, -0.1488743389816312,
                     0.1488743389816312, 0.4333953941292472, 0.6794095682990244, 0.8650633666889845, 0.9739065285171717]
        let weights = [0.0666713443086881, 0.1494513491505806, 0.2190863625159820, 0.2692667193099963, 0.2955242247147529,
                       0.2955242247147529, 0.2692667193099963, 0.2190863625159820, 0.1494513491505806, 0.0666713443086881]
        var added = 0.0
        let pieces = 16
        for i in 0..<pieces {
            let (y0, y1) = (-10 + 20 * Double(i) / Double(pieces), -10 + 20 * Double(i + 1) / Double(pieces))
            for (yNode, yWeight) in zip(nodes, weights) {
                let y = (y0 + y1) / 2 + (y1 - y0) / 2 * yNode
                let top = -15 + (900 - y * y).squareRoot()
                var column = 0.0
                for j in 0..<pieces {
                    let (z0, z1) = (top * Double(j) / Double(pieces), top * Double(j + 1) / Double(pieces))
                    for (zNode, zWeight) in zip(nodes, weights) {
                        let z = (z0 + z1) / 2 + (z1 - z0) / 2 * zNode
                        column += zWeight * (z1 - z0) / 2 * (30 - (y * y + (z + 15) * (z + 15)).squareRoot())
                    }
                }
                added += yWeight * (y1 - y0) / 2 * column
            }
        }
        let arcArea = 10 * 800.0.squareRoot() + 900 * asin(1.0 / 3)
        let expected = (40 * (arcArea - 300) + tan(30 * Double.pi / 180) * added) * 1e-9
        // The model also holds the roller, π 30² 40 mm³.
        let volume = try model.volume(tolerance: .standard) - Double.pi * 900 * 40 * 1e-9
        // The wall's hyperbolic edges on the floor and the sides are integrated numerically, within
        // the certified volume's budget rather than exactly.
        #expect(abs(volume - expected) < 1e-10, "\(volume) vs \(expected)")
    }

}


