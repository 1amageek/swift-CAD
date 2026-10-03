import CADGeometry
import CADIR

public struct AssemblyOccurrenceCorrespondence: Codable, Sendable, Equatable {
    public let path: AssemblyOccurrencePath
    public let definitionID: AssemblyDefinitionID
    public let placement: RigidTransform3D
    public let features: [AssemblyFeatureCorrespondence]
    public init(path: AssemblyOccurrencePath, definitionID: AssemblyDefinitionID,
                placement: RigidTransform3D, features: [AssemblyFeatureCorrespondence]) {
        self.path = path; self.definitionID = definitionID
        self.placement = placement; self.features = features
    }
}
