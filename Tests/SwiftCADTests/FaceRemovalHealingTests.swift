import Foundation
import Testing
@testable import SwiftCAD

/// Delete Face heals a solid over the faces taken out, and Remove Fillets takes out its fillets:
/// a hole's face goes with the hole, a fillet or chamfer collapses onto the meeting of the faces
/// it joined, and a face the faces around cannot close over is refused.
@Suite("Face removal healing")
struct FaceRemovalHealingTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: millimeters(x), y: millimeters(y)) }

    private func box(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
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

    private func subshapes(
        in builder: DocumentBuilder,
        of featureID: FeatureID,
        where predicate: (TopologyReference, BRepModel) -> Bool
    ) throws -> [StableSubshapeReference] {
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        return try evaluated.subshapes.entries.filter { key, value in key.featureID == featureID && predicate(value, evaluated.brep) }
            .map(\.key).sorted().map { try builder.stableSubshape($0) }
    }

    private func isCylindrical(_ value: TopologyReference, _ model: BRepModel) -> Bool {
        guard case let .face(id) = value, let face = model.faces[id] else { return false }
        switch model.geometry.surfaces[face.surfaceID] {
        case .cylinder, .analytic(.cylinder): return true
        default: return false
        }
    }

    private func solid(_ builder: DocumentBuilder) throws -> BRepModel {
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        return model
    }

    @Test(.timeLimit(.minutes(2)))
    func deletingAHolesFaceFillsTheHole() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let drill = try builder.cylinder(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: -0.005), axis: .unitZ, referenceDirection: .unitX),
            radius: millimeters(5), height: millimeters(20)
        )
        let drilled = try builder.boolean(targets: [boxID], tool: drill, operation: .difference)
        let hole = try subshapes(in: builder, of: drilled, where: isCylindrical)
        #expect(hole.isEmpty == false)
        _ = try builder.faceDelete(target: drilled, faces: hole, heals: true)
        let model = try solid(builder)
        #expect(model.faces.count == 6)
        #expect(abs(try model.volume(tolerance: .standard) - 0.040 * 0.020 * 0.010) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func removingFilletsSharpensARoundedBox() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try roundedBox(&builder)
        _ = try builder.removeFillets(target: boxID, maximumRadius: millimeters(6), convexity: .convex)
        let model = try solid(builder)
        #expect(model.faces.count == 6)
        #expect(model.vertices.count == 8)
        #expect(abs(try model.volume(tolerance: .standard) - 0.040 * 0.020 * 0.010) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func filletsOutsideTheRadiusOrConvexityAreKept() throws {
        for (radius, convexity) in [(4.0, FilletConvexity.any), (6.0, FilletConvexity.concave)] {
            var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
            let boxID = try roundedBox(&builder)
            _ = try builder.removeFillets(target: boxID, maximumRadius: millimeters(radius), convexity: convexity)
            #expect(throws: (any Error).self) {
                _ = try CADPipeline(tolerance: .standard).evaluate(builder.build())
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func deletingOneRoundCornerSharpensIt() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try roundedBox(&builder)
        let corners = try subshapes(in: builder, of: boxID, where: isCylindrical)
        #expect(corners.count == 4)
        _ = try builder.faceDelete(target: boxID, faces: [corners[0]], heals: true)
        let model = try solid(builder)
        #expect(model.faces.count == 9)
        let area = 0.040 * 0.020 - 3 * 0.005 * 0.005 * (1 - Double.pi / 4)
        #expect(abs(try model.volume(tolerance: .standard) - area * 0.010) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func deletingAChamferRestoresTheEdge() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let edge = try #require(try subshapes(in: builder, of: boxID) { value, model in
            guard case let .edge(id) = value, let edge = model.edges[id],
                  let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else { return false }
            return abs(a.z - 0.010) < 1e-9 && abs(b.z - 0.010) < 1e-9 && abs(a.x - 0.020) < 1e-9 && abs(b.x - 0.020) < 1e-9
        }.first)
        let chamfered = try builder.chamfer(target: boxID, edges: [edge], distance: millimeters(2))
        let chamferFace = try #require(try subshapes(in: builder, of: chamfered) { value, model in
            guard case let .face(id) = value, let face = model.faces[id], case let .plane(plane)? = model.geometry.surfaces[face.surfaceID] else { return false }
            return abs(plane.normal.x) > 0.1 && abs(plane.normal.z) > 0.1
        }.first)
        _ = try builder.faceDelete(target: chamfered, faces: [chamferFace], heals: true)
        let model = try solid(builder)
        #expect(model.faces.count == 6)
        #expect(abs(try model.volume(tolerance: .standard) - 0.040 * 0.020 * 0.010) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func deletingTwoChamfersThatMeetRestoresTheCorner() throws {
        // Two top edges meeting at a corner chamfered together: the chamfers meet along a mitre,
        // so they touch; deleted together they heal one after the other into the sharp box.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let edges = try subshapes(in: builder, of: boxID) { value, model in
            guard case let .edge(id) = value, let edge = model.edges[id],
                  let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else { return false }
            let top = abs(a.z - 0.010) < 1e-9 && abs(b.z - 0.010) < 1e-9
            let right = abs(a.x - 0.020) < 1e-9 && abs(b.x - 0.020) < 1e-9
            let front = abs(a.y + 0.010) < 1e-9 && abs(b.y + 0.010) < 1e-9
            return top && (right || front)
        }
        #expect(edges.count == 2)
        let chamfered = try builder.chamfer(target: boxID, edges: edges, distance: millimeters(2))
        let chamfers = try subshapes(in: builder, of: chamfered) { value, model in
            guard case let .face(id) = value, let face = model.faces[id], case let .plane(plane)? = model.geometry.surfaces[face.surfaceID] else { return false }
            return abs(plane.normal.z) > 0.1 && (abs(plane.normal.x) > 0.1 || abs(plane.normal.y) > 0.1)
        }
        #expect(chamfers.count == 2)
        _ = try builder.faceDelete(target: chamfered, faces: chamfers, heals: true)
        let model = try solid(builder)
        #expect(model.faces.count == 6)
        #expect(abs(try model.volume(tolerance: .standard) - 0.040 * 0.020 * 0.010) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aFaceTheFacesAroundCannotCloseOverIsRefused() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let top = try #require(try subshapes(in: builder, of: boxID) { value, model in
            guard case let .face(id) = value, let face = model.faces[id], case let .plane(plane)? = model.geometry.surfaces[face.surfaceID] else { return false }
            return abs(plane.normal.z) > 0.5 && plane.origin.z > 0.005
        }.first)
        _ = try builder.faceDelete(target: boxID, faces: [top], heals: true)
        #expect(throws: (any Error).self) {
            _ = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        }
    }

    /// Remove Fillets' video: an L slab whose small top and bottom rounds wrap a large vertical
    /// round and small convex and concave ones; every round up to 3 mm goes, the large one stays.
    @Test(.timeLimit(.minutes(2)))
    func smallRoundsWrappingALargeOneGoAndLeaveItWithSharpEdges() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        func deg(_ d: Double) -> CADExpression { .constant(.angle(d * .pi / 180, unit: .radian)) }
        let profile = try builder.sketch(on: .xy) { sketch in
            // An L (x 0...40, y 0...40, notch x 20...40, y 20...40) with every vertical corner
            // round: the front-left one 8 mm, the others 2 mm, the notch's inside corner concave.
            _ = sketch.line(from: point(8, 0), to: point(38, 0))
            _ = sketch.arc(center: point(38, 2), radius: millimeters(2), startAngle: deg(270), endAngle: deg(360))
            _ = sketch.line(from: point(40, 2), to: point(40, 18))
            _ = sketch.arc(center: point(38, 18), radius: millimeters(2), startAngle: deg(0), endAngle: deg(90))
            _ = sketch.line(from: point(38, 20), to: point(22, 20))
            _ = sketch.arc(center: point(22, 22), radius: millimeters(2), startAngle: deg(180), endAngle: deg(270))
            _ = sketch.line(from: point(20, 22), to: point(20, 38))
            _ = sketch.arc(center: point(18, 38), radius: millimeters(2), startAngle: deg(0), endAngle: deg(90))
            _ = sketch.line(from: point(18, 40), to: point(2, 40))
            _ = sketch.arc(center: point(2, 38), radius: millimeters(2), startAngle: deg(90), endAngle: deg(180))
            _ = sketch.line(from: point(0, 38), to: point(0, 8))
            _ = sketch.arc(center: point(8, 8), radius: millimeters(8), startAngle: deg(180), endAngle: deg(270))
        }
        let slab = try builder.extrude(profile, distance: millimeters(10))
        let outline = try subshapes(in: builder, of: slab) { value, model in
            guard case let .edge(id) = value, let edge = model.edges[id],
                  let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else { return false }
            return (abs(a.z - 0.010) < 1e-9 && abs(b.z - 0.010) < 1e-9) || (abs(a.z) < 1e-9 && abs(b.z) < 1e-9)
        }
        #expect(outline.count == 24)
        let rounded = try builder.fillet(target: slab, edges: outline, radius: millimeters(0.5))
        #expect(try solid(builder).faces.count == 38)
        _ = try builder.removeFillets(target: rounded, maximumRadius: millimeters(3), convexity: .any)
        let removed = try solid(builder)
        // Six side planes and the 8 mm round between the top and the bottom, the round's top and
        // bottom edges now sharp arcs: the L's 1200 mm² less the 8 mm corner's (1 − π/4) 64 mm².
        #expect(removed.faces.count == 9)
        let volume = try removed.volume(tolerance: .standard)
        #expect(abs(volume - (1200 - 64 * (1 - Double.pi / 4)) * 10 * 1e-9) < 1e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func theFilletsToRemoveAreNamedBeforeRemoving() throws {
        // Remove Fillets' red preview: a rounded box's four upright rounds, all convex.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try roundedBox(&builder)
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let all = try RemovableFillets().faces(target: boxID, maximumRadius: nil, convexity: .any, in: evaluated)
        #expect(all.count == 4)
        #expect(all.allSatisfy { key in
            guard case let .face(id) = evaluated.subshapes.entries[key], let face = evaluated.brep.faces[id] else { return false }
            if case .cylinder = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            if case .analytic(.cylinder) = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            return false
        })
        #expect(try RemovableFillets().faces(target: boxID, maximumRadius: 0.004, convexity: .any, in: evaluated).isEmpty)
        #expect(try RemovableFillets().faces(target: boxID, maximumRadius: nil, convexity: .concave, in: evaluated).isEmpty)
    }
}
