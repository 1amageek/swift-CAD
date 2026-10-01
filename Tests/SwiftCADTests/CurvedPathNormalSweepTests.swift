import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A path-normal sweep along a curved path moves its section with the path's frame within the
/// requested allowance, and refuses a sweep that would overlap itself or has no allowance.
@Suite("Curved path-normal sweep")
struct CurvedPathNormalSweepTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// The planar cubic path in the ZX plane from the origin, leaving along +Z: sketch x is
    /// world z and sketch y is world x.
    private let pathControls: [(z: Double, x: Double)] = [(0, 0), (0.02, 0), (0.04, 0.01), (0.05, 0.03)]

    private func document(radius: Double, allowance: Double?) throws -> CADDocument {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(radius))
        }
        let path = try builder.sketch(on: .zx) { sketch in
            _ = sketch.spline(SketchSpline(controlPoints: pathControls.map {
                SketchPoint(x: length($0.z), y: length($0.x))
            }))
        }
        var options = SweepOptions()
        options.alignment = .normal
        options.approximationTolerance = allowance.map { length($0) }
        _ = try builder.sweep(profile, along: path.featureID, options: options)
        return try builder.build(name: "curved sweep")
    }

    /// The cubic path's length by composite Gauss–Legendre quadrature.
    private func pathLength() -> Double {
        let nodes = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
        let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
        func speed(_ t: Double) -> Double {
            let p = pathControls
            let a = 3 * (1 - t) * (1 - t), b = 6 * (1 - t) * t, c = 3 * t * t
            let dz = a * (p[1].z - p[0].z) + b * (p[2].z - p[1].z) + c * (p[3].z - p[2].z)
            let dx = a * (p[1].x - p[0].x) + b * (p[2].x - p[1].x) + c * (p[3].x - p[2].x)
            return (dz * dz + dx * dx).squareRoot()
        }
        let pieces = 256
        return (0..<pieces).reduce(0.0) { sum, index in
            let lower = Double(index) / Double(pieces), half = 0.5 / Double(pieces)
            return sum + zip(nodes, weights).reduce(0.0) { $0 + $1.1 * speed(lower + half * (1 + $1.0)) } * half
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aCircleSweptAlongAPlanarCurveKeepsItsAreaAlongThePath() throws {
        let radius = 0.003, allowance = 1e-7
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try document(radius: radius, allowance: allowance))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        // Pappus: the section's centroid rides the planar path, so the volume is its area times
        // the path's length, up to the allowance over the side.
        let length = pathLength()
        let exact = Double.pi * radius * radius * length
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - exact) <= 2 * Double.pi * radius * length * allowance + 1e-12)
        // The end cap stands across the path's end tangent.
        let end = Vector3D(x: pathControls[3].x - pathControls[2].x, y: 0, z: pathControls[3].z - pathControls[2].z)
        let endTangent = try end.normalized(tolerance: 1e-12)
        let caps = evaluated.brep.faces.values.compactMap { face -> Plane3D? in
            guard case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return nil }
            return plane
        }
        #expect(caps.count == 2)
        #expect(caps.contains { abs(abs($0.normal.dot(endTangent)) - 1) < 1e-9 })
    }

    /// A 4 mm square about the origin swept along the path, twisted and scaled.
    private func squareDocument(twist: Double, endScale: Double) throws -> CADDocument {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.004), height: length(0.004)) }
        let path = try builder.sketch(on: .zx) { sketch in
            _ = sketch.spline(SketchSpline(controlPoints: pathControls.map { SketchPoint(x: length($0.z), y: length($0.x)) }))
        }
        var options = SweepOptions(
            twistAngle: .constant(.angle(twist, unit: .degree)), endScale: .constant(.scalar(endScale)), alignment: .normal
        )
        options.approximationTolerance = length(1e-7)
        _ = try builder.sweep(profile, along: path.featureID, options: options)
        return try builder.build(name: "twisted sweep")
    }

    @Test(.timeLimit(.minutes(3)))
    func aTwistedOrScaledSweepFollowsItsLawsAlongTheCurve() throws {
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        // A twist turns the square in its plane about the path: the volume stays its area times
        // the path's length.
        let twisted = try evaluator.evaluate(try squareDocument(twist: 90, endScale: 1))
        try twisted.brep.validate(level: .volumetric, tolerance: .standard)
        let pathLength = pathLength()
        #expect(abs(try twisted.brep.volume(tolerance: .standard) - 0.004 * 0.004 * pathLength)
            <= 4 * 0.004 * pathLength * 1e-7 + 1e-12)
        // A 90° twist and a scale of 2 put the end square's corners twice as far from the path's
        // end, turned a quarter.
        let scaled = try evaluator.evaluate(try squareDocument(twist: 90, endScale: 2))
        try scaled.brep.validate(level: .volumetric, tolerance: .standard)
        let end = Point3D(x: pathControls[3].x, y: 0, z: pathControls[3].z)
        // The end cap's four corners: on the plane across the path's end tangent, twice as far
        // from the path's end as the square's.
        let endTangent = try Vector3D(x: pathControls[3].x - pathControls[2].x, y: 0, z: pathControls[3].z - pathControls[2].z)
            .normalized(tolerance: 1e-12)
        let corners = scaled.brep.vertices.values.map(\.point).filter { abs(($0 - end).dot(endTangent)) < 1e-6 }
        #expect(corners.count == 4)
        #expect(corners.allSatisfy { abs(($0 - end).length - 2 * 0.002 * 2.0.squareRoot()) < 1e-6 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aCurvedSweepWithoutAnAllowanceOrPastItsBendIsRefused() throws {
        for (radius, allowance) in [(0.003, nil), (0.05, 1e-6)] as [(Double, Double?)] {
            do {
                _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try document(radius: radius, allowance: allowance))
                Issue.record("A curved sweep with radius \(radius) and allowance \(String(describing: allowance)) must be refused.")
            } catch let error as KernelError {
                #expect(error.code == .sweepPathNormalUnavailable)
            }
        }
    }
}
