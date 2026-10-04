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
        // Drawn from another corner the other way round, the frame starts where the section is.
        let redrawn = try evaluate([(0.04, 0.03), (0, 0.03), (0, 0), (0.04, 0), (0.04, 0.03)])
        #expect(abs(try redrawn.brep.volume(tolerance: .standard) - 0.004 * 0.004 * 0.14) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)), arguments: [SweepCornerStyle.mitre, .round])
    func aLineInThePathsPlaneSweepsAFlatRibbon(corners: SweepCornerStyle) throws {
        // A 4 mm line across the start of an L in the XY plane, both drawn on XY: a flat ribbon.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let section = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: SketchPoint(x: length(0), y: length(-0.002)), to: SketchPoint(x: length(0), y: length(0.002)))
        }
        let path = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: SketchPoint(x: length(0), y: length(0)), to: SketchPoint(x: length(0.03), y: length(0)))
            _ = sketch.line(from: SketchPoint(x: length(0.03), y: length(0)), to: SketchPoint(x: length(0.03), y: length(0.02)))
        }
        _ = try builder.sweep(section: .curve(CurveSectionReference(featureID: section.featureID)), along: path.featureID,
                              options: SweepOptions(alignment: .normal, cornerStyle: corners, resultKind: .sheet))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "ribbon"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let points = evaluated.brep.vertices.values.map(\.point)
        // Flat in z = 0, from the start across to the end of the second arm.
        #expect(points.allSatisfy { abs($0.z) < 1e-12 })
        #expect(points.contains { ($0 - Point3D(x: 0, y: -0.002, z: 0)).length < 1e-12 })
        #expect(points.contains { ($0 - Point3D(x: 0.032, y: 0.02, z: 0)).length < 1e-12 })
        #expect(points.contains { ($0 - Point3D(x: 0.028, y: 0.02, z: 0)).length < 1e-12 })
    }

    /// A path in the ZX plane (sketch x is world z): along +Z, a right-angled corner, on along +X,
    /// a 10 mm quarter arc running on smoothly into a last line back along −Z, and optionally a
    /// corner where the arc meets that line instead.
    private func pathWithAnArc(_ builder: inout DocumentBuilder, cornerAfterArc: Bool) throws -> FeatureID {
        func point(_ z: Double, _ x: Double) -> SketchPoint { SketchPoint(x: length(z), y: length(x)) }
        return try builder.sketch(on: .zx) { sketch in
            _ = sketch.line(from: point(0, 0), to: point(0.03, 0))
            _ = sketch.line(from: point(0.03, 0), to: point(0.03, 0.02))
            _ = sketch.arc(center: point(0.02, 0.02), radius: length(0.01),
                           startAngle: .constant(.angle(0, unit: .degree)), endAngle: .constant(.angle(90, unit: .degree)))
            _ = sketch.line(from: point(0.02, 0.03), to: cornerAfterArc ? point(0.02, 0.05) : point(0, 0.03))
        }.featureID
    }

    @Test(.timeLimit(.minutes(4)), arguments: [SweepCornerStyle.mitre, .round])
    func aPathWithACornerAndASmoothArcSweepsBoth(corners: SweepCornerStyle) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.004), height: length(0.004)) }
        let path = try pathWithAnArc(&builder, cornerAfterArc: false)
        _ = try builder.sweep(profile, along: path, options: SweepOptions(alignment: .normal, cornerStyle: corners,
                                                                          approximationTolerance: length(1e-7)))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "arc"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        let volume = try evaluated.brep.volume(tolerance: .standard)
        // Mitred, the square sweeps its area times the path's length (Pappus along the arc).
        let mitred = 0.004 * 0.004 * (0.03 + 0.02 + 0.005 * Double.pi + 0.02)
        if corners == .mitre {
            #expect(abs(volume - mitred) < 1e-10, "\(volume) vs \(mitred)")
        } else {
            // Rounded, the corner's outside turns about its axis instead of meeting on the mitre.
            #expect(volume > mitred * 0.9 && volume < mitred * 1.1 && abs(volume - mitred) > 1e-12, "\(volume)")
        }
        // The section ends square across the last line, at z = 0 about x = 30 mm (the start's cap
        // lies at z = 0 about the origin).
        let points = evaluated.brep.vertices.values.map(\.point)
        for (x, y) in [(0.028, -0.002), (0.028, 0.002), (0.032, -0.002), (0.032, 0.002)] {
            #expect(points.contains { ($0 - Point3D(x: x, y: y, z: 0)).length < 1e-9 }, "\(x) \(y)")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aCornerBesideAnArcIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.004), height: length(0.004)) }
        let path = try pathWithAnArc(&builder, cornerAfterArc: true)
        _ = try builder.sweep(profile, along: path, options: SweepOptions(alignment: .normal, approximationTolerance: length(1e-7)))
        #expect(throws: KernelError.self) {
            try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "arc"))
        }
    }
}
