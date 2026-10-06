/// Original three-valued standard logical assertion.
public enum OriginalSTEPLogical: String, Sendable {
    case trueValue = "T", falseValue = "F", unknown = "U"
    public var stepToken: String { "." + rawValue + "." }
}
#if !hasFeature(Embedded)
extension OriginalSTEPLogical: Codable {}
#endif
