import CADCore

extension IndependentShapeSource {
    /// Validates real document ownership using the original source validation allowance.
    public func validateProductAssociations(in assembly: DocumentAssembly?, limits: IndependentShapeSourceLimits,
        after validation: IndependentShapeSourceValidation, check: () throws -> Void = {}) throws -> IndependentShapeSourceValidation {
        try limits.validate()
        var records = validation.consumedRecords, work = validation.consumedWork
        guard records >= 0, records <= limits.maximumRecords, work >= 0, work <= limits.maximumWork,
              validation.consumedTextBytes <= limits.maximumTextBytes, validation.maximumObservedDepth <= limits.maximumDepth else {
            throw IndependentShapeSourceError.resourceLimitExceeded("Product association validation receipt exceeds source allowance.")
        }
        func checkpoint() throws { try CurrentTaskCancellationChecker().checkCancellation(); try check() }
        func charge(_ count: Int, records countRecords: Int = 0) throws {
            try checkpoint()
            guard count >= 0, count <= limits.maximumWork - work, countRecords >= 0, countRecords <= limits.maximumRecords - records else {
                throw IndependentShapeSourceError.resourceLimitExceeded("Product association cumulative allowance.")
            }
            work += count; records += countRecords
        }
        if !productAssociations.isEmpty {
            guard let assembly else { throw IndependentShapeSourceError.missingReference("Product-associated independent source requires its original document assembly.") }
            try charge(assembly.definitions.count, records: assembly.definitions.count)
            var owners = Set<AssemblyDefinitionID>()
            for definition in assembly.definitions {
                try charge(1)
                guard owners.insert(definition.id).inserted else { throw IndependentShapeSourceError.invalidSource("Duplicate document product definition.") }
            }
            for association in productAssociations {
                try charge(1)
                guard owners.contains(association.definitionID) else { throw IndependentShapeSourceError.missingReference("Independent representation product definition.") }
            }
        }
        try checkpoint()
        return IndependentShapeSourceValidation(consumedRecords: records, consumedTextBytes: validation.consumedTextBytes,
            consumedWork: work, maximumObservedDepth: validation.maximumObservedDepth)
    }
}
