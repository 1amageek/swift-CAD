import CADGeometry

public struct AssemblyProductLookup: AssemblyProductLookingUp {
    public init() {}
    public func product(for id: AssemblyDefinitionID, in assembly: DocumentAssembly,
                        maximumWork: Int) throws -> AssemblyProductLookupResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try product(for: id, in: assembly, maximumWork: maximumWork, using: &execution)
    }
    public func product(for id: AssemblyDefinitionID, in assembly: DocumentAssembly,
                        maximumWork: Int, using execution: inout OriginalQueryExecution) throws -> AssemblyProductLookupResult {
        try execution.checkpoint()
        var work = 0
        func admitTable(_ count: Int, using execution: inout OriginalQueryExecution) throws {
            guard count <= maximumWork - work else { throw AssemblyError.resourceLimitExceeded("product lookup work") }
            try execution.consumeWork(count)
            work += count
        }
        try admitTable(assembly.definitions.count, using: &execution)
        var definition: AssemblyDefinition?
        for candidate in assembly.definitions {
            try execution.checkpoint()
            if candidate.id == id { definition = candidate; break }
        }
        guard let definition else { throw AssemblyError.missingDefinition(id) }
        try admitTable(assembly.formations.count, using: &execution)
        var formation: AssemblyProductFormation?
        for candidate in assembly.formations {
            try execution.checkpoint()
            if candidate.id == definition.formationID { formation = candidate; break }
        }
        guard let formation else { throw AssemblyError.invalidSource("Missing product formation.") }
        try admitTable(assembly.products.count, using: &execution)
        var product: AssemblyProduct?
        for candidate in assembly.products {
            try execution.checkpoint()
            if candidate.id == formation.productID { product = candidate; break }
        }
        guard let product else { throw AssemblyError.invalidSource("Missing product.") }
        try execution.checkpoint()
        return AssemblyProductLookupResult(product: product, consumedWork: work)
    }
}
