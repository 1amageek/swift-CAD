import CADCore
import CADGeometry
import CADIR
import CADTopology
import Testing
@testable import CADModeling

@Suite("Bridge surface failure classification", .timeLimit(.minutes(1)))
struct BridgeSurfaceFailureClassificationTests {
    @Test
    func actualEvaluatorPreservesItsTypedRequestFailureAndLowerPhase() throws {
        let featureID = FeatureID(PortableIdentity128(high: 202, low: 1))
        let length = CADExpression.constant(.length(1, unit: .meter))
        // A real authored request for another evaluator exercises Bridge's
        // existing public request rejection, without constructing false source receipts.
        let feature = FeatureNode(id: featureID, operation: .primitive(.init(definition:
            .box(.init(width: length, depth: length, height: length)))))
        let context = EvaluationContext(parameters: .init(), brep: BRepModel(),
            profiles: [:], tolerance: .standard)
        var execution = OriginalQueryExecution(budget: try .init(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .conversion, entry: .admitted, stage: .request))
        do {
            _ = try BridgeSurfaceFeatureEvaluator().evaluateValidated(feature: feature,
                context: context, using: &execution)
            Issue.record("Bridge accepted another evaluator's authored request.")
        } catch {
            let failure = try #require(error as? OriginalQueryFailure)
            let original = try #require(failure.originalError as? KernelError)
            #expect(original.phase == .validation)
            #expect(original.code == .invalidInput)
            #expect(failure.kernelFailure.phase == original.phase)
            #expect(failure.kernelFailure.code == original.code)
            #expect(failure.kernelFailure.featureID == featureID)
            #expect(failure.kernelFailure.tolerance == .standard)
            #expect(failure.context.operation == .conversion)
            #expect(failure.context.entry == .admitted)
            #expect(failure.context.stage == .request)
        }
    }
    @Test func actualRuledBuilderPublishesANonemptyBridge() throws {
        try BridgeSurfaceFailureClassificationChecks.actualRuledBuilderPublishesANonemptyBridge()
    }
    @Test func actualRuledBuilderWorkRefusalKeepsItsCauseAndFeatureContext() throws {
        try BridgeSurfaceFailureClassificationChecks.actualRuledBuilderWorkRefusalKeepsItsCauseAndFeatureContext()
    }
    @Test func actualRuledBuilderStorageRefusalKeepsItsCauseAndFeatureContext() throws {
        try BridgeSurfaceFailureClassificationChecks.actualRuledBuilderStorageRefusalKeepsItsCauseAndFeatureContext()
    }
    @Test func actualRuledBuilderCancellationKeepsItsCause() throws {
        try BridgeSurfaceFailureClassificationChecks.actualRuledBuilderCancellationKeepsItsCause()
    }

}
