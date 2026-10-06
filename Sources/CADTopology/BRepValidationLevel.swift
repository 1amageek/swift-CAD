/// Selects the invariant set enforced for a B-rep validation request.
public enum BRepValidationLevel: String, Hashable, Sendable, CaseIterable {
    case modeling
    case exact
    case volumetric
}

#if !hasFeature(Embedded)
extension BRepValidationLevel: Codable {}
#endif
