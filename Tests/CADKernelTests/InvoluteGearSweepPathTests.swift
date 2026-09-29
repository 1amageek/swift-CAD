import CADCore
import CADIR
import CADKernel
import CADModeling
import Foundation
import Testing

/// A gear generates both its sweep's section and its path; the sweep refuses a path that is one of
/// its sections, so the path carries an identity of its own.
@Suite("Involute gear sweep path", .timeLimit(.minutes(3)))
struct InvoluteGearSweepPathTests {
    private let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)

    @Test func aSpurGearEvaluatesToOneValidBody() throws {
        let gear = InvoluteGearFeature(toothCount: 32, dimensions: [
            .baseRadius: .constant(.length(0.032 * cos(.pi / 9), unit: .meter)),
            .pitchRadius: .constant(.length(0.032, unit: .meter)),
            .tipRadius: .constant(.length(0.034, unit: .meter)),
            .rootRadius: .constant(.length(0.0295, unit: .meter)),
            .filletRadius: .constant(.length(0.00076, unit: .meter)),
            .pitchToothAngle: .constant(.angle(.pi / 32, unit: .radian)),
            .width: .constant(.length(0.01, unit: .meter)),
            .twistAngle: .constant(.angle(0, unit: .radian)),
            .profileError: .constant(.length(1e-7, unit: .meter)),
            .sweepError: .constant(.length(1e-6, unit: .meter))
        ], doubleHelical: false)
        var document = CADDocument(units: .meters)
        let feature = try FeatureNodeFactory.make(operation: .involuteGear(gear), in: document, tolerance: tolerance)
        document.designGraph = DesignGraph(nodes: [feature.id: feature], order: [feature.id])
        let result = try DocumentEvaluator(tolerance: tolerance).evaluateExact(document)
        #expect(result.brep.bodies.count == 1)
        try result.brep.validate(level: .exact, tolerance: tolerance)
        let heights = result.brep.vertices.values.map(\.point.z)
        #expect(abs(try #require(heights.min())) < 1e-9)
        #expect(abs(try #require(heights.max()) - 0.01) < 1e-9)
    }

    @Test func thePathIdentityIsFixedAndNeverTheGears() {
        let gear = FeatureID()
        let path = InvoluteGearFeatureEvaluator.pathFeatureID(of: gear)
        #expect(path != gear)
        #expect(path == InvoluteGearFeatureEvaluator.pathFeatureID(of: gear))
        #expect(path != InvoluteGearFeatureEvaluator.pathFeatureID(of: FeatureID()))
    }
}
