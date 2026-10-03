import CADGeometry

public struct ExpandedAssemblyOccurrence: Sendable, Equatable {
    public let path: AssemblyOccurrencePath
    public let definitionID: AssemblyDefinitionID
    public let placement: RigidTransform3D
    public init(path: AssemblyOccurrencePath, definitionID: AssemblyDefinitionID, placement: RigidTransform3D) {
        self.path = path; self.definitionID = definitionID; self.placement = placement
    }
}
