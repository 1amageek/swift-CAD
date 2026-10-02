import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// One guide steers a section along a curved path, read in the path's moving frame: a guide that
/// drifts away from the path across its plane scales the section (Point), leaves it as it is
/// (Chord, the direction kept), or turns it so its side keeps touching the guide (Curve).
@Suite("Curved path guided sweep")
struct CurvedPathGuidedSweepTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// The planar cubic path in the ZX plane from the origin (sketch x is world z, y is world x).
    private let pathControls: [(z: Double, x: Double)] = [(0, 0), (0.02, 0), (0.04, 0.01), (0.05, 0.03)]
    private func pathPoint(_ index: Int) -> Point3D { Point3D(x: pathControls[index].x, y: 0, z: pathControls[index].z) }

    /// ∫₀¹ f(t)·|P′(t)| dt along the path by composite Gauss–Legendre quadrature.
    private func integral(_ f: (Double) -> Double) -> Double {
        let nodes = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
        let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
        func speed(_ t: Double) -> Double {
            let p = pathControls
            let a = 3 * (1 - t) * (1 - t), b = 6 * (1 - t) * t, c = 3 * t * t
            let dz = a * (p[1].z - p[0].z) + b * (p[2].z - p[1].z) + c * (p[3].z - p[2].z)
            let dx = a * (p[1].x - p[0].x) + b * (p[2].x - p[1].x) + c * (p[3].x - p[2].x)
            return (dz * dz + dx * dx).squareRoot()
        }
        return (0..<256).reduce(0.0) { sum, index in
            let lower = Double(index) / 256, half = 0.5 / 256
            return sum + zip(nodes, weights).reduce(0.0) { $0 + $1.1 * f(lower + half * (1 + $1.0)) * speed(lower + half * (1 + $1.0)) } * half
        }
    }

    /// A 4 mm square about the path swept with a guide running above it, `rise(t)` off the path
    /// along y at the path's parameter t: the path's cubic plus a linear y, so it crosses each
    /// station's plane at the same t.
    private func evaluate(_ method: SweepGuideMethod, rise: (Double, Double), turned: Double = 0) throws -> EvaluatedDocument {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // The square turned by `turned` about the path.
        let corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].map { c in
            (0.002 * (c.0 * cos(turned) - c.1 * sin(turned)), 0.002 * (c.0 * sin(turned) + c.1 * cos(turned)))
        }
        let profile = try builder.sketch(on: .xy) { sketch in
            for k in 0..<4 {
                let (a, b) = (corners[k], corners[(k + 1) % 4])
                _ = sketch.line(from: SketchPoint(x: length(a.0), y: length(a.1)), to: SketchPoint(x: length(b.0), y: length(b.1)))
            }
        }
        let path = try builder.sketch(on: .zx) { sketch in
            _ = sketch.spline(SketchSpline(controlPoints: pathControls.map { SketchPoint(x: length($0.z), y: length($0.x)) }))
        }
        let controls = (0..<4).map { i in
            pathPoint(i) + Vector3D(x: 0, y: rise.0 + (rise.1 - rise.0) * Double(i) / 3, z: 0)
        }
        let guide = FeatureID()
        try builder.append(id: guide, name: "Guide", operation: .spatialPath(SpatialPathFeature(kind: .bezier, knots: [
            SpatialPathKnot(position: controls[0], outgoing: controls[1] - controls[0]),
            SpatialPathKnot(position: controls[3], incoming: controls[2] - controls[3]),
        ])))
        var options = SweepOptions(alignment: .normal)
        options.guideMethod = method
        options.approximationTolerance = length(1e-7)
        _ = try builder.sweep(section: .profile(ProfileReference(featureID: profile.featureID)), along: path.featureID,
                              guides: [guide], options: options)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "guided"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    @Test(.timeLimit(.minutes(3)))
    func aPointGuideDriftingAwayScalesTheSection() throws {
        // The guide from the top edge's middle (2 mm up) to 4 mm: the section scales by 1 + t.
        let evaluated = try evaluate(.point, rise: (0.002, 0.004))
        let expected = integral { t in 0.004 * 0.004 * (1 + t) * (1 + t) }
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 1e-10, "\(volume) \(expected)")
    }

    @Test(.timeLimit(.minutes(3)))
    func aChordGuideKeepsTheSectionAsItIs() throws {
        // A guide drifting straight away keeps its direction: no turn, no scale.
        let evaluated = try evaluate(.chord, rise: (0.002, 0.004))
        let expected = integral { _ in 0.004 * 0.004 }
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-10)
    }

    @Test(.timeLimit(.minutes(3)))
    func aCurveGuideStartingSquareToTheSideIsRefused() throws {
        // From the middle of the square's side, square to it, the contact slides as the square
        // root of the run: the section turns infinitely fast at the start.
        #expect {
            _ = try evaluate(.curve, rise: (0.002, 0.0023))
        } throws: { error in
            (error as? KernelError)?.code == .sweepGuideContactUnavailable
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func aCurveGuideTurnsTheSectionToKeepTouchingIt() throws {
        // The square turned 30° about the path: the guide from its side straight above the path
        // (off the side's middle) to 0.3 mm further. The side reaches it only turned, unscaled;
        // its end lies on the end cap's outline.
        let turned = Double.pi / 6
        let start = 0.002 / cos(turned)
        let evaluated = try evaluate(.curve, rise: (start, start + 0.0003), turned: turned)
        let expected = integral { _ in 0.004 * 0.004 }
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-10)
        let end = pathPoint(3), guideEnd = pathPoint(3) + Vector3D(x: 0, y: start + 0.0003, z: 0)
        let tangent = try Vector3D(x: pathControls[3].x - pathControls[2].x, y: 0, z: pathControls[3].z - pathControls[2].z)
            .normalized(tolerance: 1e-12)
        let cap = evaluated.brep.vertices.values.map(\.point).filter { abs(($0 - end).dot(tangent)) < 1e-9 }
        #expect(cap.count == 4)
        // The guide's end lies on one of the cap's sides (between two of its corners).
        let onSide = cap.contains { a in cap.contains { b in
            a != b && abs((guideEnd - a).length + (b - guideEnd).length - (b - a).length) < 1e-6
        } }
        #expect(onSide)
    }
}
