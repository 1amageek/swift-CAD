import CADGeometry
import CADIR

public struct AssemblyOccurrenceCorrespondence: Sendable, Equatable {
    public let path: AssemblyOccurrencePath
    public let definitionID: AssemblyDefinitionID
    public let placement: AssemblyPlacementWord
    public let features: [AssemblyFeatureCorrespondence]
    public init(path: AssemblyOccurrencePath, definitionID: AssemblyDefinitionID,
                placement: RigidTransform3D, features: [AssemblyFeatureCorrespondence]) {
        self.path = path; self.definitionID = definitionID
        self.placement = AssemblyPlacementWord(placement: placement); self.features = features
    }
    public init(path: AssemblyOccurrencePath, definitionID: AssemblyDefinitionID,
                placement: AssemblyPlacementWord, features: [AssemblyFeatureCorrespondence]) {
        self.path = path; self.definitionID = definitionID; self.placement = placement; self.features = features
    }
}

#if !hasFeature(Embedded)
extension AssemblyOccurrenceCorrespondence: Codable {}
#endif
