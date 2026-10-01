import Foundation
import Testing
@testable import SwiftCAD

@Suite("Thicken builder")
struct ThickenBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndNativePackageShareExactThickenOperation() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(
                width: .constant(.length(40.0, unit: .millimeter)),
                height: .constant(.length(20.0, unit: .millimeter))
            )
        }
        let extrudeID = try builder.extrude(
            profile,
            distance: .constant(.length(10.0, unit: .millimeter))
        )
        var removedFaces = [try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .endFace)
        )]
        for index in 0..<4 {
            removedFaces.append(try builder.stableSubshape(
                generatedBy: extrudeID,
                selector: .generated(role: .sideFace, index: index)
            ))
        }
        let sheetID = try builder.faceDelete(
            target: extrudeID,
            faces: removedFaces
        )
        let thickenID = try builder.thicken(
            target: sheetID,
            front: .constant(.length(2.0, unit: .millimeter)),
            back: .constant(.length(2.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Thicken parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * 0.004) <= 1.0e-12)
        guard case let .thicken(thicken) = loaded.designGraph.nodes[thickenID]?.operation else {
            Issue.record("Native package persistence must preserve the shared thicken operation.")
            return
        }
        #expect(thicken.front == thicken.back)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSheetGrowsByDifferentThicknessesOnItsTwoSides() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(width: .constant(.length(40.0, unit: .millimeter)), height: .constant(.length(20.0, unit: .millimeter)))
        }
        let extrudeID = try builder.extrude(profile, distance: .constant(.length(10.0, unit: .millimeter)))
        var removedFaces = [try builder.stableSubshape(generatedBy: extrudeID, selector: .generated(role: .endFace))]
        for index in 0..<4 {
            removedFaces.append(try builder.stableSubshape(generatedBy: extrudeID, selector: .generated(role: .sideFace, index: index)))
        }
        let sheetID = try builder.faceDelete(target: extrudeID, faces: removedFaces)
        _ = try builder.thicken(
            target: sheetID, front: .constant(.length(3.0, unit: .millimeter)), back: .constant(.length(1.0, unit: .millimeter))
        )
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(try builder.build(name: "Two-sided thicken"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * 0.004) <= 1.0e-12)
        // The bottom sheet faces down, so its front grows down 3 mm and its back up 1 mm.
        let zs = evaluated.brep.vertices.values.map(\.point.z)
        #expect(abs((zs.min() ?? 0) + 0.003) < 1e-12)
        #expect(abs((zs.max() ?? 0) - 0.001) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aSheetOfTangentCurvedFacesThickensIntoOneWall() throws {
        // Half a cylinder's wall (two of its quarter faces, tangent along their seam), radius 10 mm
        // and 10 mm tall, thickened 1 mm to each side: half an annulus 2 mm wide.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { sketch in
            _ = sketch.circle(center: SketchPoint(x: .constant(.length(0, unit: .millimeter)), y: .constant(.length(0, unit: .millimeter))),
                              radius: .constant(.length(10, unit: .millimeter)))
        }
        let cylinder = try builder.extrude(profile, distance: .constant(.length(10, unit: .millimeter)))
        let removed = try [GeneratedSubshapeSelector.generated(role: .startFace), .generated(role: .endFace),
                           .generated(role: .sideFace, index: 2), .generated(role: .sideFace, index: 3)].map {
            try builder.stableSubshape(generatedBy: cylinder, selector: $0)
        }
        let sheet = try builder.faceDelete(target: cylinder, faces: removed)
        _ = try builder.thicken(target: sheet, front: .constant(.length(1, unit: .millimeter)), back: .constant(.length(1, unit: .millimeter)))
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(try builder.build(name: "half wall"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let expected = Double.pi / 2 * (0.011 * 0.011 - 0.009 * 0.009) * 0.010
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) <= 1.0e-12)
    }


    @Test(.timeLimit(.minutes(2)))
    func aDsWallThickensAcrossItsSharpCorners() throws {
        // A D's wall (its flat and its arc of radius 10 mm meeting at right angles), 10 mm tall,
        // thickened 1 mm to each side: the D grown by 1 mm less the D shrunk by 1 mm.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        func mm(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }
        let profile = try builder.sketch(on: .xy) { sketch in
            _ = sketch.arc(center: SketchPoint(x: mm(0), y: mm(0)), radius: mm(10),
                           startAngle: .constant(.angle(0, unit: .degree)), endAngle: .constant(.angle(180, unit: .degree)))
            _ = sketch.line(from: SketchPoint(x: mm(-10), y: mm(0)), to: SketchPoint(x: mm(10), y: mm(0)))
        }
        let d = try builder.extrude(profile, distance: mm(10))
        let caps = try [GeneratedSubshapeSelector.generated(role: .startFace), .generated(role: .endFace)].map {
            try builder.stableSubshape(generatedBy: d, selector: $0)
        }
        let wall = try builder.faceDelete(target: d, faces: caps)
        _ = try builder.thicken(target: wall, front: mm(1), back: mm(1))
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(try builder.build(name: "d wall"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // The disc of radius 11 above y = −1, less the disc of radius 9 above y = 1 (mm).
        let outer = Double.pi * 121 - (121 * acos(1.0 / 11) - 120.0.squareRoot())
        let inner = 81 * acos(1.0 / 9) - 80.0.squareRoot()
        let expected = (outer - inner) * 10 * 1e-9
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) <= 1.0e-12, "\(volume) vs \(expected)")
    }


    @Test(.timeLimit(.minutes(2)))
    func anOpenStripOfAFlatAndAnArcThickensAcrossItsCorner() throws {
        // A quarter disc of radius 10 mm extruded 10 mm, kept as its flat along X and its arc,
        // meeting at a right angle at (10, 0) mm, thickened 1 mm to each side.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        func mm(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }
        let profile = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: SketchPoint(x: mm(0), y: mm(0)), to: SketchPoint(x: mm(10), y: mm(0)))
            _ = sketch.arc(center: SketchPoint(x: mm(0), y: mm(0)), radius: mm(10),
                           startAngle: .constant(.angle(0, unit: .degree)), endAngle: .constant(.angle(90, unit: .degree)))
            _ = sketch.line(from: SketchPoint(x: mm(0), y: mm(10)), to: SketchPoint(x: mm(0), y: mm(0)))
        }
        let sector = try builder.extrude(profile, distance: mm(10))
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(try builder.build(name: "strip"))
        // The face along the Y axis: the plane x = 0.
        let side = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == sector, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .plane(plane)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.x) - 1) < 1e-12
        }?.key)
        let removed = try [GeneratedSubshapeSelector.generated(role: .startFace), .generated(role: .endFace)].map {
            try builder.stableSubshape(generatedBy: sector, selector: $0)
        } + [try builder.stableSubshape(side)]
        let strip = try builder.faceDelete(target: sector, faces: removed)
        _ = try builder.thicken(target: strip, front: mm(1), back: mm(1))
        let thick = try CADPipeline(tolerance: .standard).evaluate(try builder.build(name: "strip"))
        try thick.brep.validate(level: .volumetric, tolerance: .standard)
        // Each side's region right of x = 0 and above its flat's offset, inside its arc's offset.
        func F(_ a: Double, _ u: Double) -> Double { (u * (a * a - u * u).squareRoot() + a * a * asin(u / a)) / 2 }
        func region(_ rho: Double, _ c: Double) -> Double { F(rho, rho) - F(rho, c) }
        let expected = (region(11, -1) - region(9, 1)) * 10 * 1e-9
        let volume = try thick.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) <= 1.0e-12, "\(volume) vs \(expected)")
    }

}
