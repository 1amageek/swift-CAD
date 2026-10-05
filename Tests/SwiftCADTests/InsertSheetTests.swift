import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Plasticity's Insert Sheet (Patch with a hole's edges and a sheet, Trim to hole): the sheet is
/// trimmed to the hole and sewn in, closing the body.
@Suite("Insert sheet")
struct InsertSheetTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    @Test(.timeLimit(.minutes(2)))
    func aSheetTrimmedToABoxsOpenTopClosesIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let before = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let topKey = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .face(id) = value, let face = before.brep.faces[id],
                  case let .plane(plane) = before.brep.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.z) - 1) < 1e-9 && plane.origin.z > 0.01
        }?.key)
        let topZ = try #require(before.brep.vertices.values.map(\.point.z).max())
        let opened = try builder.faceDelete(target: box, faces: [try builder.stableSubshape(topKey)])
        // A flat sheet at the top's height, reaching past the box on every side.
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: -0.03, y: -0.03, z: topZ), Point3D(x: 0.03, y: -0.03, z: topZ)],
                            [Point3D(x: -0.03, y: 0.03, z: topZ), Point3D(x: 0.03, y: 0.03, z: topZ)]]
        ))
        let open = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let openBody = try #require(open.subshapes.entries.compactMap { key, value -> Body? in
            guard key.featureID == opened, case let .body(id) = value else { return nil }
            return open.brep.bodies[id]
        }.first)
        let hole = try #require(OpenBoundaryLoopResolver().loops(in: openBody, model: open.brep).first)
        let seedKey = try #require(open.subshapes.entries.first { key, value in
            key.featureID == opened && value == .edge(hole.traversals[0].edgeID)
        }?.key)
        let fill = try builder.surfaceFill(target: opened, boundarySeed: try builder.stableSubshape(seedKey), insertedSheet: sheet)
        let joined = try builder.joinBodies([opened, fill], mode: .sewnSolid)
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let solid = try #require(evaluated.subshapes.entries.compactMap { key, value -> Body? in
            guard key.featureID == joined, case let .body(id) = value else { return nil }
            return evaluated.brep.bodies[id]
        }.first)
        #expect(solid.kind == .solid)
        let side = 0.02
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
    }

    /// Insert Sheet's Trim to sheet (inferred with the user 2026-10-05): a cap whose rim stands on
    /// the plate around a hole keeps its whole self, and the plate is cut back to the rim, the two
    /// sewn into one sheet.
    @Test(.timeLimit(.minutes(4)))
    func trimToSheetCutsThePlateBackToTheInsertedSheetsRim() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A 40 mm block 10 mm thick with a 10 mm square hole through its middle, the hole's walls
        // taken away: a sheet with a hole in its top and in its bottom.
        let block = try builder.box(width: length(0.04), depth: length(0.04), height: length(0.01))
        let drill = try builder.box(placement: PrimitivePlacement(origin: Point3D(x: 0.015, y: 0.015, z: -0.001), axis: .unitZ,
                                                                  referenceDirection: .unitX),
                                    width: length(0.01), depth: length(0.01), height: length(0.012))
        let holed = try builder.boolean(targets: [block], tool: drill, operation: .difference)
        let drilled = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let walls = try drilled.subshapes.entries.compactMap { key, value -> StableSubshapeReference? in
            guard key.featureID == holed, case let .face(id) = value, let face = drilled.brep.faces[id],
                  case let .plane(plane)? = drilled.brep.geometry.surfaces[face.surfaceID], abs(plane.normal.z) < 1e-9,
                  [0.015, 0.025].contains(where: { abs(plane.origin.x - $0) < 1e-9 && abs(plane.normal.x) > 0.5 })
                    || [0.015, 0.025].contains(where: { abs(plane.origin.y - $0) < 1e-9 && abs(plane.normal.y) > 0.5 }) else { return nil }
            return try builder.stableSubshape(key)
        }
        #expect(walls.count == 4)
        let plate = try builder.faceDelete(target: holed, faces: walls)
        // A cap: a 20 mm square box 5 mm high standing on the plate around the hole, its bottom taken away.
        let box = try builder.box(placement: PrimitivePlacement(origin: Point3D(x: 0.01, y: 0.01, z: 0.01), axis: .unitZ, referenceDirection: .unitX),
                                  width: length(0.02), depth: length(0.02), height: length(0.005))
        let boxed = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let bottom = try #require(boxed.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .face(id) = value, let face = boxed.brep.faces[id],
                  case let .plane(plane)? = boxed.brep.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.z) - 1) < 1e-9 && abs(plane.origin.z - 0.01) < 1e-9
        }?.key)
        let cap = try builder.faceDelete(target: box, faces: [try builder.stableSubshape(bottom)])
        let open = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let plateBody = try #require(open.subshapes.entries.compactMap { key, value -> Body? in
            guard key.featureID == plate, case let .body(id) = value else { return nil }
            return open.brep.bodies[id]
        }.first)
        // The hole in the plate's top.
        let top = try #require(OpenBoundaryLoopResolver().loops(in: plateBody, model: open.brep).first { loop in
            loop.traversals.allSatisfy { traversal in
                guard let edge = open.brep.edges[traversal.edgeID], let point = open.brep.vertices[edge.startVertexID]?.point else { return false }
                return abs(point.z - 0.01) < 1e-9
            }
        })
        let seed = try #require(open.subshapes.entries.first { key, value in key.featureID == plate && value == .edge(top.traversals[0].edgeID) }?.key)
        let fill = try builder.surfaceFill(target: plate, boundarySeed: try builder.stableSubshape(seed), insertedSheet: cap, trimsToSheet: true)
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let sheet = try #require(evaluated.subshapes.entries.compactMap { key, value -> Body? in
            guard key.featureID == fill, case let .body(id) = value else { return nil }
            return evaluated.brep.bodies[id]
        }.first)
        #expect(sheet.kind == .sheet)
        #expect(evaluated.brep.bodies[plateBody.id] == nil)
        #expect(evaluated.subshapes.entries.values.contains(.body(plateBody.id)) == false)
        // The plate's top less the cap's 20 mm square, its bottom less the hole, its four sides, and
        // the cap's top and four sides: 1200 + 1500 + 1600 + 400 + 400 mm².
        let faces = sheet.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }
        let area = try faces.reduce(0.0) { $0 + (try evaluated.brep.faceAreaMeasurement(of: $1, tolerance: .standard)).area }
        #expect(abs(area - 5.1e-3) < 1e-12, "\(area)")
        // Only the bottom's hole stays open.
        #expect(OpenBoundaryLoopResolver().loops(in: sheet, model: evaluated.brep).count == 1)
        // The option persists; documents without it trim the inserted sheet to the hole.
        guard case let .surfaceFill(stored)? = try builder.build().designGraph.nodes[fill]?.operation else {
            Issue.record("The fill is a surface fill."); return
        }
        #expect(try JSONDecoder().decode(SurfaceFillFeature.self, from: try JSONEncoder().encode(stored)).trimsToSheet)
    }

    /// Patch Faces Multiple through a guide (Plasticity's patch video): an arc over a box's open
    /// top from one corner to the opposite one divides the opening; each half is a face of its
    /// own, the two meeting along the arc, and the sheet closes the box.
    @Test(.timeLimit(.minutes(4)))
    func aGuideAcrossAnOpeningDividesItsPatchIntoFacesMeetingAlongIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let before = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let topKey = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .face(id) = value, let face = before.brep.faces[id],
                  case let .plane(plane) = before.brep.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.z) - 1) < 1e-9 && plane.origin.z > 0.01
        }?.key)
        let points = before.brep.vertices.values.map(\.point)
        let top = try #require(points.map(\.z).max())
        let (low, high) = (try #require(points.map(\.x).min()), try #require(points.map(\.x).max()))
        let (near, far) = (try #require(points.map(\.y).min()), try #require(points.map(\.y).max()))
        let opened = try builder.faceDelete(target: box, faces: [try builder.stableSubshape(topKey)])
        // The arc in the upright plane through the top's diagonal (its sketch x along the
        // diagonal, y up), rising 10 mm at the middle.
        let corner = Point3D(x: low, y: near, z: top)
        let diagonal = hypot(high - low, far - near)
        let rise = 0.01
        let radius = (diagonal * diagonal / 4 + rise * rise) / (2 * rise)
        let center = SketchPoint(x: length(diagonal / 2), y: length(rise - radius))
        let normal = Vector3D(x: far - near, y: -(high - low), z: 0) * (1 / diagonal)
        let guide = try builder.sketch(on: .plane(Plane3D(origin: corner, normal: normal))) { sketch in
            _ = sketch.arc(center: center, radius: length(radius),
                           startAngle: .constant(.angle(atan2(radius - rise, diagonal / 2), unit: .radian)),
                           endAngle: .constant(.angle(atan2(radius - rise, -diagonal / 2), unit: .radian)))
        }.featureID
        let open = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let openBody = try #require(open.subshapes.entries.compactMap { key, value -> Body? in
            guard key.featureID == opened, case let .body(id) = value else { return nil }
            return open.brep.bodies[id]
        }.first)
        let hole = try #require(OpenBoundaryLoopResolver().loops(in: openBody, model: open.brep).first)
        let seedKey = try #require(open.subshapes.entries.first { key, value in
            key.featureID == opened && value == .edge(hole.traversals[0].edgeID)
        }?.key)
        let fill = try builder.surfaceFill(target: opened, boundarySeed: try builder.stableSubshape(seedKey),
                                           guides: [CurveSectionReference(featureID: guide)])
        let patched = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        try patched.brep.validate(level: .exact, tolerance: .standard)
        let faces = patched.subshapes.entries.compactMap { key, value -> FaceID? in
            guard key.featureID == fill, case let .face(id) = value else { return nil }
            return id
        }
        #expect(faces.count == 2)
        // The arc's top, over the top's middle, is a point of the edge the faces share.
        let apex = Point3D(x: (low + high) / 2, y: (near + far) / 2, z: top + rise)
        let shared = faces.map { faceID in
            Set((patched.brep.faces[faceID]?.loops ?? []).flatMap { patched.brep.loops[$0]?.coedges.map(\.edgeID) ?? [] })
        }
        let seam = try #require(shared[0].intersection(shared[1]).first)
        let edge = try #require(patched.brep.edges[seam])
        let curve = try #require(patched.brep.geometry.curves[edge.curveID])
        #expect(try curve.parameterProjection(of: apex, tolerance: .standard).residual < 1e-9)
        // Sewn to the box, the sheet closes it.
        let joined = try builder.joinBodies([opened, fill], mode: .sewnSolid)
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let solid = try #require(evaluated.subshapes.entries.compactMap { key, value -> Body? in
            guard key.featureID == joined, case let .body(id) = value else { return nil }
            return evaluated.brep.bodies[id]
        }.first)
        #expect(solid.kind == .solid)
        #expect(try evaluated.brep.volume(of: solid.id, tolerance: .standard) > 0.02 * 0.02 * 0.02)
    }
}
