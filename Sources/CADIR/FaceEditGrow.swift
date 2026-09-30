import CADCore

/// How a face moved by Push Face, Draft Face or Match Face treats a wall it runs into. The faces
/// around a moved face are re-solved in place, so the three agree wherever the moved face meets
/// no other wall.
public enum FaceEditGrow: String, Codable, Hashable, Sendable, CaseIterable {
    /// The wall it runs into moves with it.
    case moving
    /// It stops at the wall.
    case fixed
    /// It keeps going by itself, the wall unaffected.
    case none
}
