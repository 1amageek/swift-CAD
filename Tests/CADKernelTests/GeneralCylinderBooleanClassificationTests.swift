import Testing
import CADCore
import CADIR
import CADModeling
@testable import CADKernel

@Suite("General Cylinder Boolean Classification")
struct GeneralCylinderBooleanClassificationTests {
    @Test(.timeLimit(.minutes(1)))
    func unequalSolidCylindersProduceExactIntersection() throws {
        let result = try evaluate(operation: .intersect)

        #expect(result.brep.bodies.count == 1)
        #expect(result.lineage.isEmpty == false)
        let volume = try result.brep.volume(tolerance: .standard)
        #expect(abs(volume - 70.936_109_698_9) <= 1.0e-4)
    }

    @Test(.timeLimit(.minutes(1)))
    func unequalSolidCylindersProduceExactDifferenceComponents() throws {
        let result = try evaluate(operation: .difference)

        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.shells.count == 2)
        #expect(result.lineage.isEmpty == false)
        let volume = try result.brep.volume(tolerance: .standard)
        #expect(abs(volume - 29.594_855_215_98) <= 1.0e-4)
    }

    @Test(.timeLimit(.minutes(1)))
    func unequalSolidCylindersProduceExactUnion() throws {
        let result = try evaluate(operation: .union)

        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.shells.count == 1)
        #expect(result.lineage.isEmpty == false)
        let volume = try result.brep.volume(tolerance: .standard)
        #expect(abs(volume - 199.240_858_509_82) <= 1.0e-4)
    }

    private func evaluate(operation: BooleanOperation) throws -> EvaluationResult {
        let fixture = try ExactCylinderBooleanFixture.unequalOrthogonalIntersection()
        let allSubshapes = fixture.subshapes.merging(fixture.toolSubshapes) { current, _ in current }
        return try BooleanPipeline(evaluator: ExactBRepBooleanEvaluator()).evaluate(
            operation: operation,
            targetBodyIDs: [fixture.targetBodyID],
            toolBodyID: fixture.toolBodyID,
            keepTools: false,
            featureID: FeatureID(),
            model: fixture.model,
            subshapes: allSubshapes,
            toolSubshapes: fixture.toolSubshapes,
            inputLineage: fixture.lineage,
            tolerance: .standard
        )
    }
}
