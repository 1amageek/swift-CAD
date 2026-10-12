#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// One retained provenance owner; equal-valued independent bindings stay distinct.
public struct OriginalSourceBinding<Source: Sendable>: Sendable {
    final class Owner: Sendable {
        let original: Source
        let sourceDepth: Int
        init(_ snapshot: OriginalSourceSnapshot<Source>) {
            original = snapshot.original
            sourceDepth = snapshot.sourceDepth
        }
    }
    let owner: Owner
    public var original: Source { owner.original }
    public var sourceDepth: Int { owner.sourceDepth }
    init(owner: Owner) { self.owner = owner }

    /// A chart candidate retains provenance; its family issuer still validates membership.
    public func chart<Selection: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ selection: Selection, limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceChart<Source, Selection> {
        do {
            try admission.checkpoint()
            try admission.consumeWork(1)
            try require(limits)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalSourceChart<Source, Selection>.self))
            let chart = OriginalSourceChart(binding: self, selection: selection)
            try admission.checkpoint()
            return chart
        } catch { throw .init(preserving: error) }
    }

    public func owns<Selection: Sendable>(_ chart: borrowing OriginalSourceChart<Source, Selection>) -> Bool {
        owner === chart.binding.owner
    }

    func require(_ limits: OriginalSourceIssuanceLimits) throws(OriginalSourceIssuanceFailure) {
        guard sourceDepth >= 0 else { throw .invalidSource }
        guard sourceDepth <= limits.remainingSourceDepth else { throw .sourceDepthLimit }
    }
}
