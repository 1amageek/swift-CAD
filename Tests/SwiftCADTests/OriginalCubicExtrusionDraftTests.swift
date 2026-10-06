import Foundation
import Testing
@testable import SwiftCAD

@Suite("Original cubic extrusion public draft adjacency")
struct OriginalCubicExtrusionPublicDraftTests {
    @Test(.timeLimit(.minutes(15)))
    func originalHingeAndEveryPlanarNeighborRetainWholePcurves() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        func mm(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }
        func point(_ y: Double, _ z: Double) -> SketchPoint { SketchPoint(x: mm(y), y: mm(z)) }
        let profile = try builder.sketch(on: .yz) { sketch in
            _ = sketch.spline(SketchSpline(controlPoints: [point(-10, 10), point(-3, 12), point(3, 8), point(10, 10)]))
            _ = sketch.line(from: point(10, 10), to: point(10, 0))
            _ = sketch.line(from: point(10, 0), to: point(-10, 0))
            _ = sketch.line(from: point(-10, 0), to: point(-10, 10))
        }
        let block = try builder.extrude(profile, distance: mm(30))
        let before = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let entries = before.subshapes.entries.filter { $0.key.featureID == block }
        let topEntry = try #require(entries.first { _, value in
            guard case let .face(id) = value, let face = before.brep.faces[id],
                  case .bSpline? = before.brep.geometry.surfaces[face.surfaceID] else { return false }
            return true
        })
        let endEntry = try #require(entries.first { _, value in
            guard case let .face(id) = value, let face = before.brep.faces[id],
                  case let .plane(plane)? = before.brep.geometry.surfaces[face.surfaceID] else { return false }
            return plane.normal.x * (face.orientation == .forward ? 1.0 : -1.0) > 0.5
        })
        let top = try builder.stableSubshape(topEntry.key)
        let end = try builder.stableSubshape(endEntry.key)
        _ = try builder.faceDraft(target: block, faces: [end], neutralFace: top,
            angle: .constant(.angle(.pi / 6, unit: .radian)))
        let after = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        #expect(after.faces.count == before.brep.faces.count)
        #expect(after.edges.count == before.brep.edges.count)
        #expect(after.vertices.count == before.brep.vertices.count)
        try after.validatePcurves(tolerance: .standard)
        let originalHinges = before.brep.edges.values.filter { edge in
            guard let curve = before.brep.geometry.curves[edge.curveID], case let .bSpline(spline) = curve else { return false }
            return spline.controlPoints.allSatisfy { $0.x == 0.03 }
        }
        #expect(originalHinges.count == 1)
        for original in originalHinges {
            let retained = try #require(after.edges[original.id])
            #expect(after.geometry.curves[retained.curveID] == before.brep.geometry.curves[original.curveID])
            #expect(retained.trim == original.trim)
            let owners = after.faces.values.filter { face in
                face.loops.contains { loopID in after.loops[loopID]?.coedges.contains { $0.edgeID == retained.id } ?? false }
            }
            #expect(owners.count == 2)
        }
        for face in after.faces.values {
            for loopID in face.loops {
                let loop = try #require(after.loops[loopID])
                #expect(loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil })
            }
        }
    }
}
