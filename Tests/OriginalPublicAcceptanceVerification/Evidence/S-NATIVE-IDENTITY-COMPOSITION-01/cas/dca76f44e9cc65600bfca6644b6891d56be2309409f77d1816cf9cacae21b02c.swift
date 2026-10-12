#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalSourceBindingIssuer<Provider: OriginalSourceSnapshotting>: OriginalSourceBindingIssuing {
    public typealias Input = Provider.Input
    public typealias Source = Provider.Source
    public let provider: Provider
    public init(provider: Provider) { self.provider = provider }

    public func bind<A: ExactScalarAdmission & ~Copyable>(
        _ input: borrowing Input, limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceBinding<Source> {
        do {
            try admission.checkpoint()
            try admission.consumeWork(1)
            let snapshot = try provider.snapshot(input, limits: limits, using: &admission)
            guard snapshot.sourceDepth >= 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
            guard snapshot.sourceDepth <= limits.remainingSourceDepth else {
                throw OriginalSourceIssuanceFailure.sourceDepthLimit
            }
            let payload = try exactScalarPayloadBytes(count: 1, of: OriginalSourceSnapshot<Source>.self)
            let header = try exactScalarPayloadBytes(count: 2, of: UnsafeRawPointer.self)
            let bytes = payload.addingReportingOverflow(header)
            guard !bytes.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try admission.retainStorage(bytes: bytes.partialValue)
            let result = OriginalSourceBinding(owner: .init(snapshot))
            try admission.checkpoint()
            return result
        } catch { throw .init(preserving: error) }
    }
}
