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

/// Composes verified maps without a second solver or a reset query budget.
public protocol OriginalIssuedRelationResolving {
    associatedtype First: Sendable
    associatedtype FirstSelection: Sendable
    associatedtype Second: Sendable
    associatedtype SecondSelection: Sendable
    func resolve<A: ExactScalarAdmission & ~Copyable>(kind: ExactParametricRelationKind,
        first: borrowing OriginalIssuedMapPreparation<First, FirstSelection>,
        second: borrowing OriginalIssuedMapPreparation<Second, SecondSelection>,
        maximumPairs: Int, maximumIsolatedCells: Int, requireDiscrete: Bool,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits,
        using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedRelation<First, FirstSelection, Second, SecondSelection>
}
