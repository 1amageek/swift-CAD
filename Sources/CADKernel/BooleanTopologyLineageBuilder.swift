import CADCore
import CADGeometry
import CADIR
import CADTopology

struct BooleanTopologyLineageBuilder {
    func build(
        featureID: FeatureID,
        operandBodyIDs: [BodyID],
        inputModel: BRepModel,
        resultModel: BRepModel,
        inputSubshapes: [SubshapeID: TopologyReference],
        outputSubshapes: [SubshapeID: TopologyReference],
        inputLineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance,
        retainedLineage: [SubshapeID: TopologyLineage] = [:],
        using execution: inout OriginalQueryExecution
    ) throws -> [SubshapeID: TopologyLineage] {
        try tolerance.validate()
        var result: [SubshapeID: TopologyLineage] = [:]
        // Issued sewing provenance is authoritative; geometry cannot replace it.
        for (output, entry) in retainedLineage {
            try visit(using: &execution)
            guard output.featureID == featureID, outputSubshapes[output] != nil,
                  entry.output == output, output.isValid else {
                throw invalidLineage(featureID: featureID, output: output, tolerance: tolerance)
            }
            var previous: SubshapeID?
            for parent in entry.parents {
                try visit(using: &execution)
                guard parent.isValid, parent != output,
                      previous.map({ $0 < parent }) ?? true else {
                    throw invalidLineage(featureID: featureID, output: output, tolerance: tolerance)
                }
                previous = parent
            }
            let validCount: Bool
            switch entry.relation {
            case .generated: validCount = entry.parents.isEmpty
            case .preserved, .split: validCount = entry.parents.count == 1
            case .merged: validCount = entry.parents.count > 1
            }
            guard validCount else {
                throw invalidLineage(featureID: featureID, output: output, tolerance: tolerance)
            }
            try reserve(1, of: (SubshapeID, TopologyLineage).self, using: &execution)
            result[output] = entry
        }
        for output in outputSubshapes.keys {
            try visit(using: &execution)
            guard output.featureID == featureID else {
                throw invalidLineage(featureID: featureID, output: output, tolerance: tolerance)
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): BooleanPipeline calls this path for
            // generated outputs lacking issued provenance. An original source-bound
            // correspondence producer must cover every output before history can
            // publish success; tolerance matching and entry context provide no proof.
            guard result[output] != nil else {
                throw KernelError(phase: .topology, code: .unsupportedCapability,
                    featureID: featureID, subshapeID: output, tolerance: tolerance,
                    message: "Boolean history requires issued original generated-output correspondence.")
            }
        }
        try execution.checkpoint()
        return result
    }

    private func visit(using execution: inout OriginalQueryExecution) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try execution.consumeWork(1)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The public lineage-only admission meters
    // requested typed entries before use. Dictionary growth, canonicalization
    // scratch and physical allocator retention still require actual lower storage
    // owners before this phase can claim a complete cumulative byte guarantee.
    private func reserve<T>(_ count: Int, of type: T.Type,
                            using execution: inout OriginalQueryExecution) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Boolean lineage storage request overflowed.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
    }

    private func invalidLineage(featureID: FeatureID, output: SubshapeID,
                                tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .topologyFailure, featureID: featureID,
            subshapeID: output, tolerance: tolerance,
            message: "Boolean provenance is not structurally bound to its published output.")
    }

}
