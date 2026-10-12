#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

/// Existentially removes a suffix while retaining every original lifted cell.
public protocol ExactRealProjectionProducing<Base>: Sendable {
    associatedtype Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Base.Source == Base.Value
    func project<A: ExactScalarAdmission & ~Copyable>(_ selection: borrowing ExactRealCellSelection<Base>,
        retainingPrefix coordinateCount: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A)
        throws(ExactRealTopologyFailure) -> ExactRealProjection<Base>
}
