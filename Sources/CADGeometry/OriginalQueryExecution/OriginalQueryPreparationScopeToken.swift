/// Issuer-bound handle to one exclusive preparation observation scope.
public struct OriginalQueryPreparationScopeToken: Sendable {
    let issuer: OriginalQueryScopeIssuer
    let ordinal: Int
}
