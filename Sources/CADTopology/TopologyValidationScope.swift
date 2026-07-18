/// Identifies an independently executable B-rep invariant group.
public enum TopologyValidationScope: String, Codable, Hashable, Sendable, CaseIterable {
    case references
    case loops
    case pcurves
    case orientation
    case manifold
    case watertight
    case volume
}
