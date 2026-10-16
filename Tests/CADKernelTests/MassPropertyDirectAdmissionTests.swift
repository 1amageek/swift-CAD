import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADKernel
import Foundation
import Testing

@Suite("Mass property direct admission", .timeLimit(.minutes(1)))
struct MassPropertyDirectAdmissionTests {
    @Test func actualPublicEntriesPreserveMassTensorAndCallerAttribution() throws {
        try MassPropertyDirectAdmissionChecks.actualPublicEntriesPreserveMassTensorAndCallerAttribution()
    }
    @Test func repeatedOccurrencesAndOriginalPlacementsPreserveComposition() throws {
        try MassPropertyDirectAdmissionChecks.repeatedOccurrencesAndOriginalPlacementsPreserveComposition()
    }
    @Test func callerResourcesAndCancellationRefusePublication() throws {
        try MassPropertyDirectAdmissionChecks.callerResourcesAndCancellationRefusePublication()
    }
    @Test func evaluatedSourceAndPublishedResultRetainTheirOwners() throws {
        try MassPropertyDirectAdmissionChecks.evaluatedSourceAndPublishedResultRetainTheirOwners()
    }
    @Test func authoredDensityAssignmentFeedsTheDirectMassConsumer() throws {
        try MassPropertyDirectAdmissionChecks.authoredDensityAssignmentFeedsTheDirectMassConsumer()
    }
    @Test func nativeDefaultAttributeResolverRefusesUnassociatedRawSource() throws {
        let input = VolumeMomentLoopAdmissionChecks.cube()
        let evaluated = MassPropertyDirectAdmissionChecks.document(input.model)
        let resolver: any ProductAttributeResolving = ProductAttributeResolver()
        var execution = try VolumeMomentLoopAdmissionChecks.execution(OriginalQueryBudget())
        do {
            _ = try resolver.resolve(evaluated, limits: .standard, using: &execution)
            throw VolumeMomentLoopAdmissionChecks.Failure(message: "The default resolver accepted an unassociated raw source.")
        } catch ProductAttributeError.inconsistentArtifact(let message) {
            try VolumeMomentLoopAdmissionChecks.require(message == "Missing or stale producer source/exact B-rep association.",
                "A different artifact failure replaced the actual missing source-association refusal.")
        }
    }
    @Test func nativeDefaultProducerUsesTheActualRawCube() throws {
        let input = VolumeMomentLoopAdmissionChecks.cube()
        let tolerance = VolumeMomentLoopAdmissionChecks.tolerance
        let evaluators: [any MassPropertyMeasuring] = [MassPropertyEvaluator(tolerance: tolerance),
            MassPropertyEvaluator(tolerance: tolerance, momentMeasurer: DefaultBRepVolumeMomentMeasurer()),
            MassPropertyEvaluator(tolerance: tolerance, attributes: ProductAttributeResolver())]
        for evaluator in evaluators {
            let result = try evaluator.measure([.init(bodyID: input.bodyID, densityKilogramsPerCubicMeter: 2)],
                in: MassPropertyDirectAdmissionChecks.document(input.model), options: VolumeMomentLoopAdmissionChecks.options,
                reference: MassPropertyDirectAdmissionChecks.center)
            try MassPropertyDirectAdmissionChecks.checkUnitCube(result)
        }
    }
    @Test func nativeUncachedDocumentCodecRetainsItsExactRefusals() throws {
        let source = MassPropertyDirectAdmissionChecks.document(BRepModel())
        do {
            _ = try JSONEncoder().encode(source)
            throw VolumeMomentLoopAdmissionChecks.Failure(message: "An uncached evaluated document unexpectedly encoded.")
        } catch CacheValidationError.missingBRepCache {}

        // Author the wire input from the actual public empty document's fields.
        let encoder = JSONEncoder()
        func json<T: Encodable>(_ value: T) throws -> Any {
            try JSONSerialization.jsonObject(with: encoder.encode(value), options: .fragmentsAllowed)
        }
        var wire: [String: Any] = ["document": try json(source.document), "parameters": try json(source.parameters),
            "brep": try json(source.brep), "meshes": try json(source.meshes), "curves": try json(source.curves),
            "caches": try json(source.caches), "subshapes": try json(source.subshapes), "lineage": try json(source.lineage),
            "configuration": try json(source.configuration), "assembly": NSNull(), "evaluationMetrics": try json(source.evaluationMetrics)]
        do {
            _ = try JSONDecoder().decode(EvaluatedDocument.self, from: JSONSerialization.data(withJSONObject: wire))
            throw VolumeMomentLoopAdmissionChecks.Failure(message: "An uncached evaluated document unexpectedly decoded.")
        } catch CacheValidationError.missingBRepCache {}
        wire["unexpected"] = true
        do {
            _ = try JSONDecoder().decode(EvaluatedDocument.self, from: JSONSerialization.data(withJSONObject: wire))
            throw VolumeMomentLoopAdmissionChecks.Failure(message: "The evaluated document codec accepted an unexpected key.")
        } catch DecodingError.dataCorrupted(let context) {
            try VolumeMomentLoopAdmissionChecks.require(context.codingPath.last?.stringValue == "unexpected"
                && context.debugDescription == "Unexpected key unexpected.",
                "A different decoding error replaced strict evaluated-document key rejection.")
        }
    }
}
