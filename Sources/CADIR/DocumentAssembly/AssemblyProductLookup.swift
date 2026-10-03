public struct AssemblyProductLookup: AssemblyProductLookingUp {
    public init() {}
    public func product(for id: AssemblyDefinitionID, in assembly: DocumentAssembly,
                        maximumWork: Int) throws -> AssemblyProductLookupResult {
        try Task.checkCancellation()
        var work = 0
        func charge(_ count: Int) throws {
            guard count <= maximumWork - work else { throw AssemblyError.resourceLimitExceeded("product lookup work") }
            work += count
        }
        try charge(assembly.definitions.count)
        guard let definition = assembly.definitions.first(where: { $0.id == id }) else { throw AssemblyError.missingDefinition(id) }
        try charge(assembly.formations.count)
        guard let formation = assembly.formations.first(where: { $0.id == definition.formationID }) else { throw AssemblyError.invalidSource("Missing product formation.") }
        try charge(assembly.products.count)
        guard let product = assembly.products.first(where: { $0.id == formation.productID }) else { throw AssemblyError.invalidSource("Missing product.") }
        return AssemblyProductLookupResult(product: product, consumedWork: work)
    }
}
