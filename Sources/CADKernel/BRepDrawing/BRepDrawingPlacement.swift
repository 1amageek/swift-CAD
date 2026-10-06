import CADCore
import CADGeometry
import CADTopology

/// One authored occurrence of an original body, before page/unit conversion.
public struct BRepDrawingPlacement: Equatable, Sendable {
    public let identity: String
    public let bodyID: BodyID
    /// Authored affine law for legacy inputs; display candidate when operationWord is present.
    public let transform: AffineTransform3D
    public let operationWord: OriginalAffineOperationWord?

    public init(identity: String, bodyID: BodyID, transform: AffineTransform3D) throws {
        guard !identity.isEmpty else { throw TopologyError.missingReference("Drawing placement identity is empty.") }
        try transform.validate()
        self.identity = identity
        self.bodyID = bodyID
        self.transform = transform
        self.operationWord = nil
    }
    public init(identity: String, bodyID: BodyID, operationWord: OriginalAffineOperationWord,
                displayTransform: AffineTransform3D) throws {
        guard !identity.isEmpty else { throw TopologyError.missingReference("Drawing placement identity is empty.") }
        try displayTransform.validate()
        self.identity = identity; self.bodyID = bodyID
        self.operationWord = operationWord; self.transform = displayTransform
    }

}
