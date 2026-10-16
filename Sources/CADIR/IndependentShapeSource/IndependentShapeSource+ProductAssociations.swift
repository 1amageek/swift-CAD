import CADCore
import CADGeometry

extension IndependentShapeSource {
    /// Validates real document ownership using the original source validation allowance.
    public func validateProductAssociations(in assembly: DocumentAssembly?, limits: IndependentShapeSourceLimits,
        after validation: IndependentShapeSourceValidation, check: @escaping @Sendable () throws -> Void = {}) throws -> IndependentShapeSourceValidation {
        var execution = try IndependentShapeSourceExecutionOwner.execution(limits: limits, check: check)
        try IndependentShapeSourceExecutionOwner.charge(records: validation.consumedRecords,
            work: validation.consumedWork, textBytes: validation.consumedTextBytes, using: &execution)
        return try validateProductAssociations(in: assembly, limits: limits, after: validation, using: &execution)
    }

    public func validateProductAssociations(in assembly: DocumentAssembly?, limits: IndependentShapeSourceLimits,
        after validation: IndependentShapeSourceValidation,
        using execution: inout OriginalQueryExecution) throws -> IndependentShapeSourceValidation {
        try limits.validate()
        let records = validation.consumedRecords, work = validation.consumedWork
        guard records >= 0, records <= limits.maximumRecords, work >= 0, work <= limits.maximumWork,
              validation.consumedTextBytes <= limits.maximumTextBytes, validation.maximumObservedDepth <= limits.maximumDepth else {
            throw IndependentShapeSourceError.resourceLimitExceeded("Product association validation receipt exceeds source allowance.")
        }
        if productAssociations.isEmpty { try execution.checkpoint(); return validation }
        let starting = (records: execution.localRecords, storageBytes: execution.localSourceTextBytes, work: execution.localWork)
        return try execution.withAllocationScope(policy: .uint32Words,
            recordLimit: limits.maximumRecords - validation.consumedRecords,
            sourceTextByteLimit: limits.maximumTextBytes - validation.consumedTextBytes,
            workLimit: limits.maximumWork - validation.consumedWork) { execution in
            if !productAssociations.isEmpty {
                guard let assembly else { throw IndependentShapeSourceError.missingReference("Product-associated independent source requires its original document assembly.") }
                try IndependentShapeSourceExecutionOwner.charge(records: assembly.definitions.count, work: assembly.definitions.count, using: &execution)
                var owners = Set<AssemblyDefinitionID>()
                for definition in assembly.definitions {
                    try execution.consumeWork(1)
                    guard owners.insert(definition.id).inserted else { throw IndependentShapeSourceError.invalidSource("Duplicate document product definition.") }
                }
                for association in productAssociations {
                    try execution.consumeWork(1)
                    guard owners.contains(association.definitionID) else { throw IndependentShapeSourceError.missingReference("Independent representation product definition.") }
                }
            }
            try execution.checkpoint()
            let completed = (records: execution.localRecords, storageBytes: execution.localSourceTextBytes, work: execution.localWork)
            return IndependentShapeSourceValidation(consumedRecords: validation.consumedRecords + completed.records - starting.records,
                consumedTextBytes: validation.consumedTextBytes + completed.storageBytes - starting.storageBytes,
                consumedWork: validation.consumedWork + completed.work - starting.work, maximumObservedDepth: validation.maximumObservedDepth)
        }
    }
}
