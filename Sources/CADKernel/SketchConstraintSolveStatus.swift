public enum SketchConstraintSolveStatus: String, Hashable, Sendable {
    case fullyConstrained
    case underConstrained
    case overConstrained
    case conflicting
    case singular
}

#if !hasFeature(Embedded)
extension SketchConstraintSolveStatus: Codable {}
#endif
