import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Two Point guides deform a straight sweep's section by the linear map taking both contacts to
/// their guides' ends: every section of the sweep is that map's interpolation, each contact on its
/// guide.
@Suite("Two Point guides")
struct TwoPointGuideSweepTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// A 40 × 20 mm rectangle about the origin swept 50 mm up Z, its corners (20, 10) and (−20, 10)
    /// mm guided to `ends`.
    private func sweep(ends: (Point3D, Point3D)) throws -> EvaluatedDocument {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.04), height: length(0.02)) }.featureID
        let path = try builder.sketch(on: .zx) { sketch in
            _ = sketch.line(from: SketchPoint(x: length(0), y: length(0)), to: SketchPoint(x: length(0.05), y: length(0)))
        }.featureID
        let guides = try [(Point3D(x: 0.02, y: 0.01, z: 0), ends.0), (Point3D(x: -0.02, y: 0.01, z: 0), ends.1)].map { start, end in
            let guide = FeatureID()
            try builder.append(id: guide, name: "Guide", operation: .spatialPath(SpatialPathFeature(kind: .polyline, knots: [
                SpatialPathKnot(position: start), SpatialPathKnot(position: end),
            ])))
            return guide
        }
        var options = SweepOptions(alignment: .normal)
        options.guideMethod = .point
        _ = try builder.sweep(section: .profile(ProfileReference(featureID: profile)), along: path, guides: guides, options: options)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "guides"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    @Test(.timeLimit(.minutes(2)))
    func twoGuidesShearAndStretchTheSection() throws {
        // M = [[1.25, 0.5], [−0.25, 1.5]] takes (20, 10) to (30, 10) and (−20, 10) to (−20, 20) mm.
        let evaluated = try sweep(ends: (Point3D(x: 0.03, y: 0.01, z: 0.05), Point3D(x: -0.02, y: 0.02, z: 0.05)))
        let ends = evaluated.brep.vertices.values.map(\.point).filter { abs($0.z - 0.05) < 1e-9 }
        #expect(ends.count == 4)
        for (x, y) in [(0.02, 0.01), (-0.02, 0.01), (-0.02, -0.01), (0.02, -0.01)] {
            let expected = Point3D(x: 1.25 * x + 0.5 * y, y: -0.25 * x + 1.5 * y, z: 0.05)
            #expect(ends.contains { ($0 - expected).length < 1e-9 })
        }
        // The area grows as det(I + t(M − I)) = 1 + 0.75 t + 0.25 t².
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - 0.04 * 0.02 * 0.05 * (1 + 0.75 / 2 + 0.25 / 3)) < 1e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(2)))
    func guidesThatFoldTheSectionAreRefused() throws {
        // M swaps the two contacts' sides: the section turns inside out on the way.
        do {
            _ = try sweep(ends: (Point3D(x: -0.02, y: 0.01, z: 0.05), Point3D(x: 0.02, y: 0.01, z: 0.05)))
            Issue.record("Guides that fold the section must be refused.")
        } catch let error as KernelError {
            #expect(error.code == .sweepGuideTransformCollapse || error.code == .sweepGuideConstraintUnavailable)
        }
    }
}
