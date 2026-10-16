import CADCore
import CADGeometry
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

    package func bodyID(generatedBy featureID: FeatureID) throws -> BodyID {
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

    func subshapeIDs(for reference: TopologyReference) throws -> [SubshapeID] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try subshapeIDs(for: reference, using: &execution)
    }

    func subshapeIDs(for reference: TopologyReference,
        using execution: inout OriginalQueryExecution) throws -> [SubshapeID] {
        var result: [SubshapeID] = []
        for (id, candidate) in subshapes.entries {
            try execution.consumeWork(1)
            guard candidate == reference else { continue }
            try sewingAppend(id, to: &result, using: &execution)
        }
        try execution.retainStorage(count: result.count, stride: MemoryLayout<SubshapeID>.stride)
        return try result.sorted { first, second in
            try execution.consumeWork(1)
            for _ in first.role.utf8 { try execution.consumeWork(1) }
            for _ in second.role.utf8 { try execution.consumeWork(1) }
            return first < second
        }
    }
}
