/// Selects the invariant set enforced for a B-rep validation request.
public enum BRepValidationLevel: String, Codable, Hashable, Sendable, CaseIterable {
    case modeling
    case exact
    case volumetric
}
