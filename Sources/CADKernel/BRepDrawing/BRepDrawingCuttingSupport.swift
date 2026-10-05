import CADCore
import CADGeometry

/// Authored cutting plane and its original application-order placement authority.
public struct BRepDrawingCuttingSupport: Hashable, Sendable {
    public let originalPlane: Plane3D
    public let operationWord: OriginalAffineOperationWord
    public let sourceIdentity: String

    public init(originalPlane: Plane3D, operationWord: OriginalAffineOperationWord, sourceIdentity: String) {
        self.originalPlane = originalPlane
        self.operationWord = operationWord
        self.sourceIdentity = sourceIdentity
    }
}
