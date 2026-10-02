import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A Curve guide (Plasticity's Curve method) turns the section, unscaled, about a straight path
/// that touches it, so it keeps touching the guide wherever on the section that is.
@Suite("Curve guide sweep")
struct CurveGuideSweepTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    @Test(.timeLimit(.minutes(3)))
    func theSectionTurnsToKeepTouchingTheGuide() throws {
        let allowance = 1e-6
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A 4 × 2 mm rectangle whose left side runs through the path at the origin.
        let corners = [(0.0, -0.001), (0.004, -0.001), (0.004, 0.001), (0.0, 0.001)]
        let profile = try builder.sketch(on: .xy) { sketch in
            for k in corners.indices {
                let (a, b) = (corners[k], corners[(k + 1) % 4])
                _ = sketch.line(from: point(a.0, a.1), to: point(b.0, b.1))
            }
        }.featureID
        let path = try builder.sketch(on: .zx) { $0.line(from: point(0, 0), to: point(0.05, 0)) }.featureID
        // The guide leaves the right side's middle and winds a quarter round (a cubic close to a
        // circular quarter, its handles 0.552 of the radius), ending a little farther out.
        let guideEnd = Point3D(x: 0, y: 0.0041, z: 0.05)
        let guide = FeatureID()
        try builder.append(id: guide, name: "Guide", operation: .spatialPath(SpatialPathFeature(kind: .bezier, knots: [
            SpatialPathKnot(position: Point3D(x: 0.004, y: 0, z: 0), outgoing: Vector3D(x: 0, y: 0.0022, z: 0.05 / 3)),
            SpatialPathKnot(position: guideEnd, incoming: Vector3D(x: 0.0022, y: 0, z: -0.05 / 3)),
        ])))
        var options = SweepOptions(alignment: .normal)
        options.guideMethod = .curve
        options.approximationTolerance = length(allowance)
        _ = try builder.sweep(section: .profile(ProfileReference(featureID: profile)), along: path, guides: [guide], options: options)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "curve"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // Turned, not scaled: the volume is the rectangle's area along the path.
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.004 * 0.002 * 0.05) <= 2 * (0.004 + 0.002) * 0.05 * allowance)
        // The end cap still has the path on its side and the guide's end on its boundary.
        let cap = evaluated.brep.vertices.values.map(\.point).filter { abs($0.z - 0.05) < 1e-9 }
        #expect(cap.count == 4)
        func distance(_ p: Point3D, toSegment a: Point3D, _ b: Point3D) -> Double {
            let d = b - a
            let t = max(0, min(1, (p - a).dot(d) / d.dot(d)))
            return (p - (a + d * t)).length
        }
        // The cap's corners in order around it: by angle about their centre.
        let centre = Point3D.origin + cap.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * 0.25
        let ordered = cap.sorted { atan2($0.y - centre.y, $0.x - centre.x) < atan2($1.y - centre.y, $1.x - centre.x) }
        let sides = (0..<4).map { (ordered[$0], ordered[($0 + 1) % 4]) }
        #expect(sides.map { distance(guideEnd, toSegment: $0.0, $0.1) }.min() ?? 1 <= 2 * allowance)
        #expect(sides.map { distance(Point3D(x: 0, y: 0, z: 0.05), toSegment: $0.0, $0.1) }.min() ?? 1 <= 2 * allowance)
    }

    /// A straight guide across the quarter comes nearer the path than the side it starts on, so
    /// its contact would jump across the section: refused, never swept with a jump.
    @Test(.timeLimit(.minutes(3)))
    func aGuideNearerThanItsSideIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let corners = [(0.0, -0.001), (0.004, -0.001), (0.004, 0.001), (0.0, 0.001)]
        let profile = try builder.sketch(on: .xy) { sketch in
            for k in corners.indices {
                let (a, b) = (corners[k], corners[(k + 1) % 4])
                _ = sketch.line(from: point(a.0, a.1), to: point(b.0, b.1))
            }
        }.featureID
        let path = try builder.sketch(on: .zx) { $0.line(from: point(0, 0), to: point(0.05, 0)) }.featureID
        let guide = FeatureID()
        try builder.append(id: guide, name: "Guide", operation: .spatialPath(SpatialPathFeature(kind: .polyline, knots: [
            SpatialPathKnot(position: Point3D(x: 0.004, y: 0, z: 0)), SpatialPathKnot(position: Point3D(x: 0, y: 0.0041, z: 0.05)),
        ])))
        var options = SweepOptions(alignment: .normal)
        options.guideMethod = .curve
        options.approximationTolerance = length(1e-6)
        _ = try builder.sweep(section: .profile(ProfileReference(featureID: profile)), along: path, guides: [guide], options: options)
        let document = try builder.build(name: "jump")
        #expect {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        } throws: { error in
            (error as? KernelError)?.code == .sweepGuideContactUnavailable
        }
    }
}
