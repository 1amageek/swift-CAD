#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI
import SourceIssuer
import OriginalCoordinateTransfer
#endif

/// Converts a complete isolated relation into original parameter tuples, retaining incidences.
public protocol OriginalIssuedCurveSurfacePointResolving {
    associatedtype First: Sendable
    associatedtype FirstSelection: Sendable
    associatedtype Second: Sendable
    associatedtype SecondSelection: Sendable
    func resolve<A: ExactScalarAdmission & ~Copyable>(
        relation: borrowing OriginalIssuedRelation<First, FirstSelection, Second, SecondSelection>,
        maximumPoints: Int, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedCurveSurfacePointSet<First, FirstSelection, Second, SecondSelection>
}
