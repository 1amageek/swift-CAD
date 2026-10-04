import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A boss joined to a plate it stands on: a cylinder whose base lies on the plate's top, inside
/// it, joins it (Boolean union, or a circle drawn on the top extruded with Join), the plate's top
/// taking the base's circle as a hole the boss rises from; its base rim then rounds as a concave
/// rim.
@Suite("Boss join")
struct BossJoinTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private let side = 0.03
    private let thickness = 0.01
    private let radius = 0.005
    private let height = 0.01

    private func plate(_ builder: inout DocumentBuilder) throws -> FeatureID {
        try builder.box(width: length(side), depth: length(side), height: length(thickness))
    }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "boss"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    private var joinedVolume: Double { side * side * thickness + Double.pi * radius * radius * height }

    @Test(.timeLimit(.minutes(2)), arguments: [true, false])
    func aCylinderStandingOnThePlateJoinsIt(extrudes: Bool) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let plate = try plate(&builder)
        let joined: FeatureID
        if extrudes {
            let circle = try builder.sketch(on: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: thickness), normal: .unitZ))) {
                _ = $0.circle(center: SketchPoint(x: length(side / 2), y: length(side / 2)), radius: length(radius))
            }.featureID
            joined = FeatureID()
            try builder.append(id: joined, name: nil, operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: circle, profileIndex: 0), distance: length(height), direction: .normal,
                operation: .union, targets: [BooleanTargetReference(featureID: plate)])))
        } else {
            let boss = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: side / 2, y: side / 2, z: thickness), axis: .unitZ,
                                                                          referenceDirection: .unitX),
                                            radius: length(radius), height: length(height))
            joined = try builder.boolean(targets: [plate], tool: boss, operation: .union)
        }
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - joinedVolume) < 1e-12)
        // The boss's base rim, now a concave edge, rounds: the corner section r²(1 − π/4) added
        // about the axis at its centroid, r(10 − 3π)/(12 − 3π) out from the boss's wall.
        let rims = evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == joined, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  case .circle? = evaluated.brep.geometry.curves[edge.curveID],
                  let start = evaluated.brep.vertices[edge.startVertexID]?.point else { return false }
            return abs(start.z - thickness) < 1e-12
        }.keys.sorted()
        let rim = try #require(rims.first)
        let r = 0.001
        _ = try builder.fillet(target: joined, edges: [try builder.stableSubshape(rim)], radius: length(r))
        let rounded = try evaluate(builder)
        let section = r * r * (1 - Double.pi / 4)
        let outset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let expected = joinedVolume + section * 2 * Double.pi * (radius + outset)
        let volume = try rounded.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aCylinderReachingPastThePlatesTopIsStillRefused() throws {
        // Standing on the top's corner, its base disc runs off the face: no exact join is built.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let plate = try plate(&builder)
        let boss = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: thickness), axis: .unitZ,
                                                                      referenceDirection: .unitX),
                                        radius: length(radius), height: length(height))
        _ = try builder.boolean(targets: [plate], tool: boss, operation: .union)
        #expect(throws: KernelError.self) { try evaluate(builder) }
    }
}
