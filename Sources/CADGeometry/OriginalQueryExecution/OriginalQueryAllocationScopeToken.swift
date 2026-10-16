/// Issuer-bound handle to a lexical allocation policy and contribution ceiling.
public struct OriginalQueryAllocationScopeToken: Sendable {
    let issuer: OriginalQueryScopeIssuer
    let ordinal: Int
}
