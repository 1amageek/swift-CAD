import Foundation
import Testing
@testable import SwiftCAD

/// A revolved tool cut from or joined to a planar block leaves every planar face with its
/// material on the left of its loops about its outward normal: the outline counterclockwise,
/// each hole clockwise — the same turn a profile with a hole extrudes to.
@Suite("Revolved Boolean loop winding")
struct RevolvedBooleanLoopWindingTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }

    /// Each planar face's loops as (role, whether its material lies on the loop's left).
    private func windings(_ model: BRepModel) throws -> [(role: LoopRole, left: Bool)] {
        var result: [(LoopRole, Bool)] = []
        for face in model.faces.values {
            guard let surface = model.geometry.surfaces[face.surfaceID], case let .plane(plane) = surface else { continue }
            let outward = face.orientation == .forward ? plane.normal : plane.normal * -1
            for loopID in face.loops {
                let loop = try #require(model.loops[loopID])
                let points = try model.orderedPoints(for: loopID)
                var normal = Vector3D.zero
                for (a, b) in zip(points, points.dropFirst() + points.prefix(1)) {
                    normal = normal + Vector3D(x: (a.y - b.y) * (a.z + b.z), y: (a.z - b.z) * (a.x + b.x), z: (a.x - b.x) * (a.y + b.y))
                }
                result.append((loop.role, normal.dot(outward) > 0))
            }
        }
        return result
    }

    private func block(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        return try builder.extrude(profile, distance: millimeters(10))
    }

    @Test(.timeLimit(.minutes(1)))
    func aHoleDrilledThroughAWallTurnsClockwiseAboutIt() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let box = try block(&builder)
        let circle = try builder.sketch(on: .zx) { _ = $0.circle(center: SketchPoint(x: millimeters(5), y: millimeters(0)), radius: millimeters(2)) }
        try builder.append(id: FeatureID(), name: "Hole", operation: .extrude(ExtrudeFeature(
            profile: circle, distance: millimeters(30), direction: .symmetric, operation: .difference,
            targets: [BooleanTargetReference(featureID: box)])))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        let loops = try windings(model)
        #expect(loops.filter { $0.role == .inner }.count == 2)
        #expect(loops.allSatisfy { $0.left == ($0.role == .outer) })
        let volume = try model.volume(tolerance: .standard)
        #expect(abs(volume - (8000 - 80 * Double.pi) * 1e-9) < 1e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(1)))
    func aBlindHoleTurnsClockwiseAboutItsMouthAndItsFloorCounterclockwise() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let box = try block(&builder)
        let disk = try builder.sketch(on: .xy) { _ = $0.circle(center: SketchPoint(x: millimeters(0), y: millimeters(0)), radius: millimeters(2)) }
        try builder.append(id: FeatureID(), name: "Blind", operation: .extrude(ExtrudeFeature(
            profile: disk, distance: millimeters(4), direction: .normal, operation: .difference,
            targets: [BooleanTargetReference(featureID: box)])))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        let loops = try windings(model)
        #expect(loops.filter { $0.role == .inner }.count == 1)
        #expect(loops.allSatisfy { $0.left == ($0.role == .outer) })
        let volume = try model.volume(tolerance: .standard)
        #expect(abs(volume - (8000 - 16 * Double.pi) * 1e-9) < 1e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(1)))
    func aBossJoinedThroughATopFaceTurnsClockwiseAboutIt() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let box = try block(&builder)
        let disk = try builder.sketch(on: .xy) { _ = $0.circle(center: SketchPoint(x: millimeters(0), y: millimeters(0)), radius: millimeters(2)) }
        try builder.append(id: FeatureID(), name: "Boss", operation: .extrude(ExtrudeFeature(
            profile: disk, distance: millimeters(15), direction: .normal, operation: .union,
            targets: [BooleanTargetReference(featureID: box)])))
        let model = try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
        let loops = try windings(model)
        #expect(loops.filter { $0.role == .inner }.count == 1)
        #expect(loops.allSatisfy { $0.left == ($0.role == .outer) })
        let volume = try model.volume(tolerance: .standard)
        #expect(abs(volume - (8000 + 20 * Double.pi) * 1e-9) < 1e-12, "\(volume)")
    }
}
