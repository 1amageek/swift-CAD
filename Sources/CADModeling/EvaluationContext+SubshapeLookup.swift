import CADCore
import CADIR

package extension EvaluationContext {
    func topologyReference(
        generatedBy featureID: FeatureID,
        role: String,
        ordinal: Int = 0
    ) throws -> TopologyReference {
        let subshapeID = SubshapeID(featureID: featureID, role: role, ordinal: ordinal)
        guard let reference = subshapes[subshapeID] else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                featureID: featureID,
                subshapeID: subshapeID,
                tolerance: tolerance,
                message: "Feature output has no live topology reference."
            )
        }
        return reference
    }

    func bodyID(generatedBy featureID: FeatureID) throws -> BodyID {
        let reference = try topologyReference(
            generatedBy: featureID,
            role: GeneratedSubshapeRole.body.rawValue
        )
        guard case let .body(bodyID) = reference else {
            let subshapeID = SubshapeID(
                featureID: featureID,
                role: GeneratedSubshapeRole.body.rawValue,
                ordinal: 0
            )
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: featureID,
                subshapeID: subshapeID,
                tolerance: tolerance,
                message: "Feature body output resolves to a different topology kind."
            )
        }
        return bodyID
    }

    func subshapeIDs(for reference: TopologyReference) -> [SubshapeID] {
        subshapes.entries.compactMap { subshapeID, candidate in
            candidate == reference ? subshapeID : nil
        }.sorted()
    }
}
