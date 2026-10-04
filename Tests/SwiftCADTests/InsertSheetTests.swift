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
