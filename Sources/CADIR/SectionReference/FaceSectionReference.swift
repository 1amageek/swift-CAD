import CADCore

/// A planar face of a body or sheet taken as a section: its loops, read where the face is when the
/// feature is evaluated, bound the region the section stands for, and its outward normal is the
/// section's normal.
public struct FaceSectionReference: Codable, Hashable, Sendable {
    /// The feature whose body or sheet owns the face.
    public var featureID: FeatureID
    public var face: StableSubshapeReference
    /// The port the owning feature publishes the face's body on: `.body` or `.sheet`.
    public var bodyRole: FeaturePort

    public init(featureID: FeatureID, face: StableSubshapeReference, bodyRole: FeaturePort) {
        self.featureID = featureID
        self.face = face
        self.bodyRole = bodyRole
    }

    public func validate() throws {
        try face.validate()
        guard bodyRole == .body || bodyRole == .sheet else {
            throw FeatureEvaluationError.invalidGraph("A face section's owner publishes a body or a sheet.")
        }
    }
}
