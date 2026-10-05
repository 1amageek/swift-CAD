import CADGeometry

public struct ExpandedAssemblyOccurrence: Sendable, Equatable {
    public let path: AssemblyOccurrencePath
    public let definitionID: AssemblyDefinitionID
    public let placement: AssemblyPlacementWord
    public init(path: AssemblyOccurrencePath, definitionID: AssemblyDefinitionID, placement: RigidTransform3D) {
        self.path = path; self.definitionID = definitionID; self.placement = AssemblyPlacementWord(placement: placement)
    }
    public init(path: AssemblyOccurrencePath, definitionID: AssemblyDefinitionID, placement: AssemblyPlacementWord) {
        self.path = path; self.definitionID = definitionID; self.placement = placement
    }
}
