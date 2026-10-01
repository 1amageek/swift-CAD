import Foundation
import Testing
import CADCore
import CADExchange
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A Normal sweep along straight arms with corners mitres each corner: the arms meet on the plane
/// halving the turn, so a square centred on the path sweeps its area times the path's length, open
/// or around a closed frame.
@Suite("Mitred sweep")
struct MitredSweepTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// A 4 mm square about the origin swept along lines through `points` in the ZX plane (sketch x
    /// is world z), the first leaving the origin along +Z.
    private func evaluate(_ points: [(z: Double, x: Double)]) throws -> EvaluatedDocument {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.004), height: length(0.004)) }
        let path = try builder.sketch(on: .zx) { sketch in
            for (start, end) in zip(points, points.dropFirst()) {
                _ = sketch.line(from: SketchPoint(x: length(start.z), y: length(start.x)), to: SketchPoint(x: length(end.z), y: length(end.x)))
            }
        }
        _ = try builder.sweep(profile, along: path.featureID, options: SweepOptions(alignment: .normal))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "mitred"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    @Test(.timeLimit(.minutes(2)))
    func anLShapedPathMitresItsCorner() throws {
        let evaluated = try evaluate([(0, 0), (0.03, 0), (0.03, 0.02)])
        #expect(evaluated.brep.bodies.count == 1)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.004 * 0.004 * 0.05) < 1e-12)
        // The two arms meet on the 45° plane through the corner: its four vertices lie on it.
        let corner = Point3D(x: 0, y: 0, z: 0.03)
        let mitre = try Vector3D(x: 1, y: 0, z: 1).normalized(tolerance: 1e-12)
        let onMitre = evaluated.brep.vertices.values.map(\.point).filter { abs(($0 - corner).dot(mitre)) < 1e-9 }
        #expect(onMitre.count == 4)
    }

    @Test(.timeLimit(.minutes(2)))
    func aClosedFrameMitresEveryCornerWithoutCaps() throws {
        let evaluated = try evaluate([(0, 0), (0.04, 0), (0.04, 0.03), (0, 0.03), (0, 0)])
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.faces.count == 16)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.004 * 0.004 * 0.14) < 1e-12)
    }
}
