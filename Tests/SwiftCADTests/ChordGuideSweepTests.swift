import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A Chord guide turns the section about a straight path to keep pointing at the guide, without
/// scaling it, within the sweep's positional allowance.
@Suite("Chord guide sweep")
struct ChordGuideSweepTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// A 4 × 2 mm rectangle about the origin swept 50 mm up the Z axis, guided by a line from its
    /// corner (2, 1, 0) mm to `guideEnd`.
    private func evaluate(guideEnd: Point3D, method: SweepGuideMethod, allowance: Double?) throws -> EvaluatedDocument {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.004), height: length(0.002)) }.featureID
        let path = try builder.sketch(on: .zx) { sketch in
            _ = sketch.line(from: SketchPoint(x: length(0), y: length(0)), to: SketchPoint(x: length(0.05), y: length(0)))
        }.featureID
        let guide = FeatureID()
        try builder.append(id: guide, name: "Guide", operation: .spatialPath(SpatialPathFeature(kind: .polyline, knots: [
            SpatialPathKnot(position: Point3D(x: 0.002, y: 0.001, z: 0)), SpatialPathKnot(position: guideEnd),
        ])))
        var options = SweepOptions(alignment: .normal)
        options.guideMethod = method
        options.approximationTolerance = allowance.map { length($0) }
        _ = try builder.sweep(section: .profile(ProfileReference(featureID: profile)), along: path, guides: [guide], options: options)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "chord"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    @Test(.timeLimit(.minutes(3)))
    func aChordGuideTurnsTheSectionAQuarterWithoutScalingIt() throws {
        let allowance = 1e-6
        // The guide ends a quarter turn round and twice as far out: Chord keeps only the turn.
        let evaluated = try evaluate(guideEnd: Point3D(x: -0.002, y: 0.004, z: 0.05), method: .chord, allowance: allowance)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.004 * 0.002 * 0.05) <= 2 * (0.004 + 0.002) * 0.05 * allowance)
        // The end cap is the rectangle turned a quarter about the path.
        let endCorners = evaluated.brep.vertices.values.map(\.point).filter { abs($0.z - 0.05) < 1e-9 }
        #expect(endCorners.count == 4)
        for expected in [Point3D(x: -0.001, y: 0.002, z: 0.05), Point3D(x: -0.001, y: -0.002, z: 0.05),
                         Point3D(x: 0.001, y: -0.002, z: 0.05), Point3D(x: 0.001, y: 0.002, z: 0.05)] {
            #expect(endCorners.contains { ($0 - expected).length <= allowance })
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aChordGuideWithoutAnAllowanceIsRefused() throws {
        do {
            _ = try evaluate(guideEnd: Point3D(x: -0.002, y: 0.004, z: 0.05), method: .chord, allowance: nil)
            Issue.record("A Chord guide needs an allowance.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func aChordGuideTurnsALineSectionIntoATwistedSheet() throws {
        let allowance = 1e-6
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A 4 mm line at y = 1 mm swept 50 mm up the Z axis, its end (2, 1) mm guided a quarter round.
        let line = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: SketchPoint(x: length(0.002), y: length(0.001)), to: SketchPoint(x: length(-0.002), y: length(0.001)))
        }.featureID
        let path = try builder.sketch(on: .zx) { sketch in
            _ = sketch.line(from: SketchPoint(x: length(0), y: length(0)), to: SketchPoint(x: length(0.05), y: length(0)))
        }.featureID
        let guide = FeatureID()
        try builder.append(id: guide, name: "Guide", operation: .spatialPath(SpatialPathFeature(kind: .polyline, knots: [
            SpatialPathKnot(position: Point3D(x: 0.002, y: 0.001, z: 0)), SpatialPathKnot(position: Point3D(x: -0.002, y: 0.004, z: 0.05)),
        ])))
        var options = SweepOptions(alignment: .normal)
        options.guideMethod = .chord
        options.resultKind = .sheet
        options.approximationTolerance = length(allowance)
        let sweep = try builder.sweep(section: .curve(CurveSectionReference(featureID: line)), along: path, guides: [guide], options: options)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "chord"))
        try evaluated.brep.validate(tolerance: .standard)
        let bodies = Set(evaluated.subshapes.entries.compactMap { key, value -> BodyID? in
            guard key.featureID == sweep, case let .body(id) = value else { return nil }
            return id
        })
        #expect(bodies.count == 1)
        #expect(bodies.allSatisfy { evaluated.brep.bodies[$0]?.kind == .sheet })
        // The end edge is the line turned a quarter about the path.
        let ends = evaluated.brep.vertices.values.map(\.point).filter { abs($0.z - 0.05) < 1e-9 }
        #expect(ends.count == 2)
        for expected in [Point3D(x: -0.001, y: 0.002, z: 0.05), Point3D(x: -0.001, y: -0.002, z: 0.05)] {
            #expect(ends.contains { ($0 - expected).length <= allowance })
        }
    }
}
