import Foundation
import Testing
@testable import SwiftCAD

/// Topology Transform moves faces, edges and vertices of one body together, each shared vertex
/// once, by a translation, a rotation or a scale.
@Suite("Topology transform")
struct TopologyTransformTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }

    private func box(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(width: millimeters(40), height: millimeters(20))
        }
        return try builder.extrude(profile, distance: millimeters(10))
    }

    private func references(
        in builder: DocumentBuilder,
        of featureID: FeatureID,
        where predicate: (TopologyReference, BRepModel) -> Bool
    ) throws -> [StableSubshapeReference] {
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        return try evaluated.subshapes.entries
            .filter { key, value in key.featureID == featureID && predicate(value, evaluated.brep) }
            .map { try builder.stableSubshape($0.key) }
    }

    private func edgeMidpoint(_ reference: TopologyReference, _ model: BRepModel) -> Point3D? {
        guard case let .edge(id) = reference, let edge = model.edges[id],
              let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else { return nil }
        return Point3D(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, z: (a.z + b.z) / 2)
    }

    private func isTopFace(_ reference: TopologyReference, _ model: BRepModel) -> Bool {
        guard case let .face(id) = reference, let face = model.faces[id],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else { return false }
        return abs(abs(plane.normal.z) - 1) < 1e-9 && abs(plane.origin.z - 0.010) < 1e-9
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test(.timeLimit(.minutes(1)))
    func twoEdgesSharingACornerLiftItOnce() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let edges = try references(in: builder, of: boxID) { value, model in
            guard let mid = edgeMidpoint(value, model), near(mid.z, 0.010) else { return false }
            return (near(mid.x, 0.020) && near(mid.y, 0)) || (near(mid.y, 0.010) && near(mid.x, 0))
        }
        #expect(edges.count == 2)
        _ = try builder.transformTopology(
            target: boxID, subshapes: edges,
            motion: .translation(DirectMoveVector(direction: .unitZ, distance: millimeters(5)))
        )
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        let lifted = model.vertices.values.filter { near($0.point.z, 0.015) }
        #expect(lifted.count == 3)
        #expect(!model.vertices.values.contains { $0.point.z > 0.0151 })
    }

    @Test(.timeLimit(.minutes(1)))
    func aTopFaceTiltsAboutItsMiddle() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let top = try references(in: builder, of: boxID, where: isTopFace)
        let angle = 10.0 * .pi / 180
        _ = try builder.transformTopology(
            target: boxID, subshapes: top,
            motion: .rotation(DirectRotation(
                origin: Point3D(x: 0, y: 0, z: 0.010), axis: .unitY, angle: .constant(.angle(angle, unit: .radian))
            ))
        )
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        // The section in x–z is the quadrilateral under the tilted top; the depth is 20 mm.
        let c = cos(angle), s = sin(angle)
        let section: [(Double, Double)] = [(-0.020, 0), (0.020, 0), (0.020 * c, 0.010 - 0.020 * s), (-0.020 * c, 0.010 + 0.020 * s)]
        var twiceArea = 0.0
        for index in section.indices {
            let (x0, z0) = section[index], (x1, z1) = section[(index + 1) % section.count]
            twiceArea += x0 * z1 - x1 * z0
        }
        #expect(abs(try model.volume(tolerance: .standard) - abs(twiceArea) / 2 * 0.020) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aTopFaceScaledByHalfMakesAFrustum() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let top = try references(in: builder, of: boxID, where: isTopFace)
        _ = try builder.transformTopology(
            target: boxID, subshapes: top,
            motion: .scale(DirectScale(
                origin: Point3D(x: 0, y: 0, z: 0.010), xAxis: .unitX, yAxis: .unitY,
                factors: Array(repeating: .constant(.scalar(0.5)), count: 3)
            ))
        )
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        try model.validate(level: .volumetric, tolerance: .standard)
        let bottom = 0.040 * 0.020, top2 = 0.020 * 0.010
        let frustum = 0.010 / 3 * (bottom + top2 + (bottom * top2).squareRoot())
        #expect(abs(try model.volume(tolerance: .standard) - frustum) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aRotationOfACurvedEdgeIsRefusedAndNothingIsNotAMotion() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let cylinderID = try builder.cylinder(radius: millimeters(10), height: millimeters(20))
        let circles = try references(in: builder, of: cylinderID) { value, model in
            guard case let .edge(id) = value, let edge = model.edges[id],
                  case .circle = model.geometry.curves[edge.curveID] else { return false }
            return true
        }
        var rotated = builder
        _ = try rotated.transformTopology(
            target: cylinderID, subshapes: [try #require(circles.first)],
            motion: .rotation(DirectRotation(origin: .origin, axis: .unitX, angle: .constant(.angle(0.1, unit: .radian))))
        )
        #expect(throws: (any Error).self) { _ = try CADPipeline(tolerance: .standard).evaluate(rotated.build()) }

        #expect(throws: (any Error).self) {
            try TopologyTransformFeature(
                target: TopologyTransformTargetReference(featureID: cylinderID), subshapes: [],
                motion: .translation(DirectMoveVector(direction: .unitZ, distance: millimeters(1)))
            ).validate(tolerance: .standard)
        }
    }

    @Test func aTransformRoundTripsThroughItsCodableForm() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let boxID = try box(&builder)
        let feature = TopologyTransformFeature(
            target: TopologyTransformTargetReference(featureID: boxID),
            subshapes: try references(in: builder, of: boxID, where: isTopFace),
            motion: .scale(DirectScale(origin: .origin, xAxis: .unitX, yAxis: .unitY,
                                       factors: Array(repeating: .constant(.scalar(2)), count: 3)))
        )
        let data = try JSONEncoder().encode(FeatureOperation.topologyTransform(feature))
        #expect(try JSONDecoder().decode(FeatureOperation.self, from: data) == .topologyTransform(feature))
    }
}
