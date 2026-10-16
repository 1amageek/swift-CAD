/// An issuer-bound handle for one exclusively nested proof scope.
public struct ExactScalarProofScopeToken: Sendable {
    let owner: ExactScalarProofScopeOwner
    let serial: Int
}

final class ExactScalarProofScopeOwner: Sendable {}
