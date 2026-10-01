import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Simplify makes a sweep's flat faces trimmed planes and leaves its curved faces, its volume and
/// its topology as they were.
@Suite("Sweep simplify")
struct SweepSimplifyTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// A section about the origin swept along lines through `points` in the ZX plane.
    private func evaluate(
        simplify: Bool, _ points: [(z: Double, x: Double)], section: (inout SketchBuilder) -> Void
    ) throws -> EvaluatedDocument {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { section(&$0) }
        let path = try builder.sketch(on: .zx) { sketch in
            for (start, end) in zip(points, points.dropFirst()) {
                _ = sketch.line(from: SketchPoint(x: length(start.z), y: length(start.x)), to: SketchPoint(x: length(end.z), y: length(end.x)))
            }
        }
        var options = SweepOptions(alignment: .normal)
        options.simplify = simplify
        _ = try builder.sweep(profile, along: path.featureID, options: options)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "simplify"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    private func planarFaceCount(_ evaluated: EvaluatedDocument) -> Int {
        evaluated.brep.faces.values.filter { face in
            if case .plane = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            return false
        }.count
    }

    @Test(.timeLimit(.minutes(2)))
    func aSquareSweptAroundACornerHasOnlyPlanes() throws {
        let points: [(z: Double, x: Double)] = [(0, 0), (0.03, 0), (0.03, 0.02)]
        let square: (inout SketchBuilder) -> Void = { $0.rectangle(width: length(0.004), height: length(0.004)) }
        let plain = try evaluate(simplify: false, points, section: square)
        let simplified = try evaluate(simplify: true, points, section: square)
        #expect(simplified.brep.faces.count == plain.brep.faces.count)
        #expect(simplified.brep.edges.count == plain.brep.edges.count)
        #expect(planarFaceCount(plain) < plain.brep.faces.count)
        #expect(planarFaceCount(simplified) == simplified.brep.faces.count)
        #expect(abs(try simplified.brep.volume(tolerance: .standard) - 0.004 * 0.004 * 0.05) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCircleKeepsItsCurvedSide() throws {
        let circle: (inout SketchBuilder) -> Void = { _ = $0.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(0.002)) }
        let simplified = try evaluate(simplify: true, [(0, 0), (0.03, 0)], section: circle)
        #expect(planarFaceCount(simplified) == 2)
        #expect(simplified.brep.faces.count > 2)
        #expect(abs(try simplified.brep.volume(tolerance: .standard) - Double.pi * 0.002 * 0.002 * 0.03) < 1e-12)
    }
}
