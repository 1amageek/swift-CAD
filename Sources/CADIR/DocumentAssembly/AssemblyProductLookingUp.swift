import CADGeometry

public protocol AssemblyProductLookingUp: Sendable {
    func product(for definition: AssemblyDefinitionID, in assembly: DocumentAssembly,
                 maximumWork: Int) throws -> AssemblyProductLookupResult
    func product(for definition: AssemblyDefinitionID, in assembly: DocumentAssembly,
                 maximumWork: Int, using execution: inout OriginalQueryExecution) throws -> AssemblyProductLookupResult
}

public extension AssemblyProductLookingUp {
    // FIXME(INCOMPLETE_IMPLEMENTATION): An ordinary-only injected lookup has no
    // direct traversal on the composing query. Product resolution must refuse it
    // until its real definition/formation/product scan consumes that execution.
    func product(for definition: AssemblyDefinitionID, in assembly: DocumentAssembly,
                 maximumWork: Int, using execution: inout OriginalQueryExecution) throws -> AssemblyProductLookupResult {
        throw AssemblyError.invalidSource("Product lookup lacks original execution support.")
    }
}
