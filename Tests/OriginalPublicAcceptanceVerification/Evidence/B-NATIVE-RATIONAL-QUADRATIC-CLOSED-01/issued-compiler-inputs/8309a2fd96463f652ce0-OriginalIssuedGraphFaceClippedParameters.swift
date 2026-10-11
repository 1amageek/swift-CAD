import CADGeometry
import CADTopology

/// Original face authority retained beside complete lifted graph material refinement.
public struct OriginalIssuedGraphFaceClippedParameters<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable>: Sendable {
    public let original: ValidatedBRepModel
    public let faceID: FaceID
    public let loops: [Loop]
    public let parameters: OriginalIssuedGraphClippedParameters<S, E, C, T, F, D>

    init(original: ValidatedBRepModel, faceID: FaceID, loops: [Loop], parameters: OriginalIssuedGraphClippedParameters<S, E, C, T, F, D>) {
        self.original = original
        self.faceID = faceID
        self.loops = loops
        self.parameters = parameters
    }
}
