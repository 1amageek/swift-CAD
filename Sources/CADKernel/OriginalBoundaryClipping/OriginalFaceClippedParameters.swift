import CADCore
import CADGeometry
import CADTopology

/// Complete parameter clipping tied to unchanged original face, loop and coedge identities.
/// Image/fiber strata have not been refined; this is not a geometric overlap publication.
public struct OriginalFaceClippedParameters: Sendable {
    public let original: ValidatedBRepModel
    public let faceID: FaceID
    public let loops: [Loop]
    public let parameters: OriginalClippedNativeParameters
    package init(original: ValidatedBRepModel, faceID: FaceID, loops: [Loop], parameters: OriginalClippedNativeParameters) {
        self.original = original; self.faceID = faceID; self.loops = loops; self.parameters = parameters
    }
}
