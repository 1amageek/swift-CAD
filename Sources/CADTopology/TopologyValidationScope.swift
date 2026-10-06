/// Identifies an independently executable B-rep invariant group.
public enum TopologyValidationScope: String, Hashable, Sendable, CaseIterable {
    case references
    case loops
    case pcurves
    case orientation
    case manifold
    case watertight
    case volume
}

#if !hasFeature(Embedded)
extension TopologyValidationScope: Codable {}
#endif
