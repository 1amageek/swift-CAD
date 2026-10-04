import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A slot cut across a cylinder's top, flush with it: its walls meet the top's circle in arcs
/// whose trimming curves and edges are found apart, a hair's turn from each other, which the
/// circle's correspondence admits within the distance it allows the arcs' ends.
@Suite("Cylinder flush notch")
struct CylinderFlushNotchTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    @Test(.timeLimit(.minutes(3)))
    func aSlotFlushWithACylindersTopCutsItEveryTime() throws {
        let (radius, height, half, depth) = (0.02, 0.01, 0.005, 0.005)
        // The strip |x| ≤ half across the disc, by ∫ 2√(r² − x²) dx.
        let strip = 2 * half * (radius * radius - half * half).squareRoot() + 2 * radius * radius * asin(half / radius)
        let expected = Double.pi * radius * radius * height - strip * depth
        // Each build draws new identities, which order the arrangement differently.
        for _ in 0..<8 {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let cylinder = try builder.cylinder(radius: length(radius), height: length(height))
            let slot = try builder.box(placement: PrimitivePlacement(origin: Point3D(x: -half, y: -0.03, z: height - depth), axis: .unitZ,
                                                                     referenceDirection: .unitX),
                                       width: length(2 * half), depth: length(0.06), height: length(depth))
            _ = try builder.boolean(targets: [cylinder], tool: slot, operation: .difference)
            let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "slot"))
            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-12)
        }
    }
}
