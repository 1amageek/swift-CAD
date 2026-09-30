import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A planar face of a body sweeps like a profile: along a straight path into a block, along a
/// curved path within the allowance, and united with the body it lies on.
@Suite("Sweep face")
struct SweepFaceTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "sweep face"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    /// The 20 mm box's top face, at z = 20 mm.
    private func top(of box: FeatureID, in builder: DocumentBuilder) throws -> SectionReference {
        let evaluated = try evaluate(builder)
        let key = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return (face.orientation == .forward ? plane.normal : plane.normal * -1).z > 0.99
        }?.key)
        return .face(FaceSectionReference(featureID: box, face: try builder.stableSubshape(key), bodyRole: .body))
    }

    /// A path in the ZX plane (sketch x is world z) from the top face's middle, leaving along +Z.
    private func path(_ controls: [(z: Double, x: Double)], in builder: inout DocumentBuilder) throws -> FeatureID {
        try builder.sketch(on: .zx) { sketch in
            if controls.count == 2 {
                _ = sketch.line(from: SketchPoint(x: length(controls[0].z), y: length(controls[0].x)),
                                to: SketchPoint(x: length(controls[1].z), y: length(controls[1].x)))
            } else {
                _ = sketch.spline(SketchSpline(controlPoints: controls.map { SketchPoint(x: length($0.z), y: length($0.x)) }))
            }
        }.featureID
    }

    @Test(.timeLimit(.minutes(2)))
    func aTopFaceSweepsIntoABlockOrGrowsItsBox() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let face = try top(of: box, in: builder)
        let straight = try path([(0.02, 0.01), (0.05, 0.01)], in: &builder)
        var apart = builder
        _ = try apart.sweep(section: face, along: straight)
        let separate = try evaluate(apart)
        #expect(separate.brep.bodies.count == 2)
        #expect(abs(try separate.brep.volume(tolerance: .standard) - (0.02 * 0.02 * 0.02 + 0.02 * 0.02 * 0.03)) < 1e-12)

        var options = SweepOptions()
        options.booleanOperation = .union
        _ = try builder.sweep(section: face, along: straight, targets: [box], options: options)
        let grown = try evaluate(builder)
        #expect(grown.brep.bodies.count == 1)
        #expect(abs(try grown.brep.volume(tolerance: .standard) - 0.02 * 0.02 * 0.05) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aTopFaceFollowsACurvedPath() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let face = try top(of: box, in: builder)
        let controls: [(z: Double, x: Double)] = [(0.02, 0.01), (0.05, 0.01), (0.08, 0.02), (0.1, 0.05)]
        let curved = try path(controls, in: &builder)
        var options = SweepOptions()
        options.approximationTolerance = length(1e-7)
        _ = try builder.sweep(section: face, along: curved, options: options)
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 2)
        // The face's centroid sits on the path's plane-normal side only across it (in Y), so the
        // swept volume is its area times the path's length, within the allowance over the side.
        let nodes = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
        let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
        func speed(_ t: Double) -> Double {
            let a = 3 * (1 - t) * (1 - t), b = 6 * (1 - t) * t, c = 3 * t * t
            let dz = a * (controls[1].z - controls[0].z) + b * (controls[2].z - controls[1].z) + c * (controls[3].z - controls[2].z)
            let dx = a * (controls[1].x - controls[0].x) + b * (controls[2].x - controls[1].x) + c * (controls[3].x - controls[2].x)
            return (dz * dz + dx * dx).squareRoot()
        }
        let pathLength = (0..<256).reduce(0.0) { sum, index in
            let lower = Double(index) / 256, half = 0.5 / 256
            return sum + zip(nodes, weights).reduce(0.0) { $0 + $1.1 * speed(lower + half * (1 + $1.0)) } * half
        }
        let swept = try evaluated.brep.volume(tolerance: .standard) - 0.02 * 0.02 * 0.02
        #expect(abs(swept - 0.02 * 0.02 * pathLength) <= 4 * 0.02 * pathLength * 1e-7 + 1e-12)
    }
}
