#if !hasFeature(Embedded)
/// Native exact source capability/context failures remain explicit.
public enum NativeRationalSourceDecodingError: Error, Sendable {
    case missingCallerAllowance
    case invalidCallerContext
    case synchronizationCapabilityUnavailable
    case unboundedWordContainer
}
#endif
