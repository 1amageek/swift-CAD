/// Issuer-bound handle to one exclusive conversion-policy scope.
public struct OriginalQueryConversionScopeToken: Sendable {
    let issuer: OriginalQueryScopeIssuer
    let ordinal: Int
}

