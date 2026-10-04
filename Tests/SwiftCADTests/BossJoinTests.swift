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

    /// A stepped shaft: a 10 mm cylinder standing coaxially on a 20 mm one (or the 20 mm one on
    /// the 10 mm one, either as the tool, above or below), joined into one solid, the larger cap
    /// left as an annulus round the smaller's circle; the step's concave rim then rounds.
    @Test(.timeLimit(.minutes(2)), arguments: [(true, false), (false, false), (true, true), (false, true)])
    func coaxialCylindersStandingOnEachOtherJoin(toolAbove: Bool, toolLarger: Bool) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (large, small, step) = (0.02, 0.01, 0.01)
        let (targetRadius, toolRadius) = toolLarger ? (small, large) : (large, small)
        let target = try builder.cylinder(radius: length(targetRadius), height: length(step))
        let tool = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: toolAbove ? step : -step), axis: .unitZ,
                                                                      referenceDirection: .unitX),
                                        radius: length(toolRadius), height: length(step))
        let joined = try builder.boolean(targets: [target], tool: tool, operation: .union)
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 1)
        let expected = Double.pi * (large * large + small * small) * step
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-12)
        // The step's rim: the smaller cylinder's circle on the shared plane.
        let shared = toolAbove ? step : 0.0
        let rims = evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == joined, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  case let .circle(circle)? = evaluated.brep.geometry.curves[edge.curveID] else { return false }
            return abs(circle.center.z - shared) < 1e-12 && abs(circle.radius - small) < 1e-12
        }.keys.sorted()
        let rim = try #require(rims.first)
        let r = 0.001
        _ = try builder.fillet(target: joined, edges: [try builder.stableSubshape(rim)], radius: length(r))
        let rounded = try evaluate(builder)
        let section = r * r * (1 - Double.pi / 4)
        let outset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let volume = try rounded.brep.volume(tolerance: .standard)
        let filled = expected + section * 2 * Double.pi * (small + outset)
        #expect(abs(volume - filled) < 5e-12, "\(volume) vs \(filled)")
    }

    /// A boss standing on a plate already drilled through beside it: the plate is no longer a
    /// convex block, but its top still bounds it, so the boss joins it the same way.
    @Test(.timeLimit(.minutes(2)))
    func aBossJoinsAPlateWithAHoleBesideIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let plate = try plate(&builder)
        let drill = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: 0.007, y: 0.007, z: -0.001), axis: .unitZ,
                                                                       referenceDirection: .unitX),
                                         radius: length(0.003), height: length(thickness + 0.002))
        let holed = try builder.boolean(targets: [plate], tool: drill, operation: .difference)
        let boss = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: side / 2 + 0.004, y: side / 2 + 0.004, z: thickness),
                                                                      axis: .unitZ, referenceDirection: .unitX),
                                        radius: length(radius), height: length(height))
        _ = try builder.boolean(targets: [holed], tool: boss, operation: .union)
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 1)
        let expected = joinedVolume - Double.pi * 0.003 * 0.003 * thickness
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-12)
    }

    /// Two cylinders of one radius stacked coaxially join into one: both caps between them go, the
    /// walls meeting along their shared circle.
    @Test(.timeLimit(.minutes(2)), arguments: [0.0, Double.pi / 5])
    func equalCylindersStackedJoinIntoOne(turn: Double) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (radius, step) = (0.01, 0.01)
        let lower = try builder.cylinder(radius: length(radius), height: length(step))
        // The upper one turned about the axis, so its rim splits elsewhere than the lower's.
        let upper = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: step), axis: .unitZ,
                                                                       referenceDirection: Vector3D(x: cos(turn), y: sin(turn), z: 0)),
                                         radius: length(radius), height: length(step))
        _ = try builder.boolean(targets: [lower], tool: upper, operation: .union)
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - Double.pi * radius * radius * 2 * step) < 1e-12)
        // No face lies on the plane between them.
        #expect(evaluated.brep.faces.values.contains { face in
            guard case let .plane(plane)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return abs(plane.origin.z - step) < 1e-9
        } == false)
    }
}
