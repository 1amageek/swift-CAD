#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Retains both complete domain covers, original chart owners and every solved pair.
public struct OriginalIssuedRelation<First: Sendable, FirstSelection: Sendable, Second: Sendable, SecondSelection: Sendable>: Sendable {
    public let kind: ExactParametricRelationKind
    public let first: OriginalIssuedMapPreparation<First, FirstSelection>
    public let second: OriginalIssuedMapPreparation<Second, SecondSelection>
    public let pairs: [OriginalIssuedRelationPair]
    public let isolatedCellCount: Int
    public let coverageCellCount: Int
    public let hasPositiveDimensionalSolutions: Bool
    init(kind: ExactParametricRelationKind, first: OriginalIssuedMapPreparation<First, FirstSelection>,
        second: OriginalIssuedMapPreparation<Second, SecondSelection>, pairs: [OriginalIssuedRelationPair],
        isolatedCellCount: Int, coverageCellCount: Int, hasPositiveDimensionalSolutions: Bool) {
        self.kind = kind; self.first = first; self.second = second; self.pairs = pairs
        self.isolatedCellCount = isolatedCellCount; self.coverageCellCount = coverageCellCount
        self.hasPositiveDimensionalSolutions = hasPositiveDimensionalSolutions
    }
}
