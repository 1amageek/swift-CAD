import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Cylinders crossing at right angles: a hole drilled across a cylinder, a radial hole from its
/// axis out through its side, and a tee of two. Their intersection curves run round the smaller
/// cylinder and turn at the larger's angular extremes, where both cylinders' seams may split them.
/// The smaller cylinder's seam is turned 0, 45 and 90 degrees about its axis, so the curves cross
/// it at different places; the solids validate and their volumes match the overlap's integral
/// within the certified volume's enclosure of the curved walls.
@Suite("Crossed cylinders")
struct CrossedCylindersTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// ∫ 2√(r² − y²) g(y) dy over the smaller cylinder's section, by y = r sin t (no endpoint
    /// singularity) and the composite midpoint rule.
    private func chordIntegral(_ r: Double, _ g: (Double) -> Double) -> Double {
        let count = 20_000
        let step = Double.pi / Double(count)
        return (0..<count).reduce(0.0) { sum, index in
            let t = -Double.pi / 2 + (Double(index) + 0.5) * step
            return sum + 2 * r * r * cos(t) * cos(t) * g(r * sin(t)) * step
        }
    }

    @Test(.timeLimit(.minutes(4)), arguments: ["through", "radial", "tee"], [0.0, 45.0, 90.0])
    func crossedCylindersMeetExactly(_ kind: String, seamDegrees: Double) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let angle = seamDegrees * Double.pi / 180
        let seam = Vector3D(x: 0, y: cos(angle), z: sin(angle))
        let expected: Double
        switch kind {
        case "through":
            // A 3 mm hole drilled across a 20 mm cylinder.
            let (big, small, height) = (0.02, 0.003, 0.02)
            let body = try builder.cylinder(radius: length(big), height: length(height))
            let drill = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: -0.03, y: 0, z: height / 2), axis: .unitX,
                                                                           referenceDirection: seam),
                                             radius: length(small), height: length(0.06))
            _ = try builder.boolean(targets: [body], tool: drill, operation: .difference)
            expected = Double.pi * big * big * height - chordIntegral(small) { 2 * (big * big - $0 * $0).squareRoot() }
        case "radial":
            // A 3 mm hole from the axis of a 20 mm cylinder out through its side.
            let (big, small, height) = (0.02, 0.003, 0.02)
            let body = try builder.cylinder(radius: length(big), height: length(height))
            let drill = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: height / 2), axis: .unitX,
                                                                           referenceDirection: seam),
                                             radius: length(small), height: length(0.03))
            _ = try builder.boolean(targets: [body], tool: drill, operation: .difference)
            expected = Double.pi * big * big * height - chordIntegral(small) { (big * big - $0 * $0).squareRoot() }
        default:
            // A 10 mm arm through a 20 mm upright.
            let (big, small, span) = (0.01, 0.005, 0.04)
            let body = try builder.cylinder(radius: length(big), height: length(span))
            let arm = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: -span / 2, y: 0, z: span / 2), axis: .unitX,
                                                                         referenceDirection: seam),
                                           radius: length(small), height: length(span))
            _ = try builder.boolean(targets: [body], tool: arm, operation: .union)
            expected = Double.pi * (big * big + small * small) * span - chordIntegral(small) { 2 * (big * big - $0 * $0).squareRoot() }
        }
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: kind))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 2e-9, "\(volume) vs \(expected)")
    }
}
