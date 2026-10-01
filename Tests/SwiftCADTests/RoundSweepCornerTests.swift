import Foundation
import Testing
import CADCore
import CADExchange
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A Normal sweep with Round corners keeps the mitre inside each turn and rounds the outside: the
/// section's outer half turns about the corner's axis, so a corner adds a quarter of the section's
/// outer half revolved and loses the inner overlap.
@Suite("Round sweep corners")
struct RoundSweepCornerTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// `section` about the origin swept with Round corners along lines through `points` in the ZX
    /// plane (sketch x is world z), the first leaving the origin along +Z.
    private func evaluate(
        _ points: [(z: Double, x: Double)], section: (inout SketchBuilder) -> Void
    ) throws -> EvaluatedDocument {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { section(&$0) }
        let path = try builder.sketch(on: .zx) { sketch in
            for (start, end) in zip(points, points.dropFirst()) {
                _ = sketch.line(from: SketchPoint(x: length(start.z), y: length(start.x)), to: SketchPoint(x: length(end.z), y: length(end.x)))
            }
        }
        var options = SweepOptions(alignment: .normal)
        options.cornerStyle = .round
        _ = try builder.sweep(profile, along: path.featureID, options: options)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "round"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    private let h = 0.002

    @Test(.timeLimit(.minutes(2)))
    func anLShapedSquareSweepRoundsItsOuterCorner() throws {
        let evaluated = try evaluate([(0, 0), (0.03, 0), (0.03, 0.02)]) { $0.rectangle(width: length(0.004), height: length(0.004)) }
        #expect(evaluated.brep.bodies.count == 1)
        // In the path's plane: the arms' strips, less the inner overlap, plus a quarter disc.
        let area = 2 * h * 0.05 - h * h + Double.pi * h * h / 4
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 2 * h * area) < 1e-12)
        // The outer corner is round: no vertex lies beyond the arm planes on the outside.
        let corner = Point3D(x: 0, y: 0, z: 0.03)
        #expect(evaluated.brep.vertices.values.allSatisfy { point in
            let offset = point.point - corner
            return !(offset.z > 1e-9 && offset.x < -1e-9)
        })
    }

    @Test(.timeLimit(.minutes(2)))
    func aCircleSectionsRoundCornerTurnsOnASphere() throws {
        // A pipe of radius h: each arm's inner half ends on the mitre, losing ∫ d dA = (2/3)h³ over
        // its half disc; the outer half turns a quarter of a ball about the corner's axis.
        let evaluated = try evaluate([(0, 0), (0.03, 0), (0.03, 0.02)]) { sketch in
            _ = sketch.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(h))
        }
        #expect(evaluated.brep.faces.values.contains { face in
            if case .analytic(.sphere)? = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            return false
        })
        let expected = 0.05 * Double.pi * h * h - 4 * h * h * h / 3 + Double.pi * h * h * h / 3
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aDiamondSectionsRoundCornerTurnsOnCones() throws {
        // A square of half diagonal h with corners on the corner's axis: each arm loses ∫ d dA = h³/3
        // over its inner triangle; the outer triangle (area h², centroid h/3 out) turns a quarter turn.
        let evaluated = try evaluate([(0, 0), (0.03, 0), (0.03, 0.02)]) { sketch in
            let corners = [(h, 0.0), (0, h), (-h, 0), (0, -h)]
            for (start, end) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
            }
        }
        #expect(evaluated.brep.faces.values.contains { face in
            if case .analytic(.cone)? = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            return false
        })
        let expected = 2 * h * h * 0.05 - 2 * h * h * h / 3 + Double.pi * h * h * h / 6
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aClosedFrameRoundsEveryCorner() throws {
        let evaluated = try evaluate([(0, 0), (0.04, 0), (0.04, 0.03), (0, 0.03), (0, 0)]) {
            $0.rectangle(width: length(0.004), height: length(0.004))
        }
        #expect(evaluated.brep.bodies.count == 1)
        let area = 2 * h * 0.14 - 4 * h * h + Double.pi * h * h
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 2 * h * area) < 1e-12)
    }
}
