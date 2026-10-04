import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Cylinders crossing at right angles are refused rather than built wrong: a hole drilled across
/// a cylinder, its seam on the axes' plane or turned 45° off it, and a radial hole turned so.
@Suite("Crossed cylinder refusal")
struct CrossedCylinderRefusalTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    @Test(.timeLimit(.minutes(4)), arguments: [(0.03, true), (0.03, false), (0.0, false)])
    func crossedCylindersAreRefusedNotBuiltWrong(reach: Double, seamOnPlane: Bool) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let body = try builder.cylinder(radius: length(0.02), height: length(0.02))
        let seam = seamOnPlane ? Vector3D.unitY : Vector3D(x: 0, y: 0.5.squareRoot(), z: 0.5.squareRoot())
        // From the far side through the whole cylinder, or from its axis out through one side.
        let drill = try builder.cylinder(placement: PrimitivePlacement(origin: Point3D(x: -reach, y: 0, z: 0.01), axis: .unitX,
                                                                       referenceDirection: seam),
                                         radius: length(0.003), height: length(reach + 0.03))
        _ = try builder.boolean(targets: [body], tool: drill, operation: .difference)
        #expect(throws: (any Error).self) {
            let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "drill"))
            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        }
    }
}
