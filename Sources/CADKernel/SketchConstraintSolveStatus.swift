public enum SketchConstraintSolveStatus: String, Codable, Hashable, Sendable {
    case fullyConstrained
    case underConstrained
    case overConstrained
    case conflicting
    case singular
}
