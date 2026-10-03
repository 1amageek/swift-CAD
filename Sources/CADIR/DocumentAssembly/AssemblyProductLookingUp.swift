public protocol AssemblyProductLookingUp: Sendable {
    func product(for definition: AssemblyDefinitionID, in assembly: DocumentAssembly,
                 maximumWork: Int) throws -> AssemblyProductLookupResult
}
