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
}
