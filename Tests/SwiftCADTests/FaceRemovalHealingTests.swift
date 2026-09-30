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
}
