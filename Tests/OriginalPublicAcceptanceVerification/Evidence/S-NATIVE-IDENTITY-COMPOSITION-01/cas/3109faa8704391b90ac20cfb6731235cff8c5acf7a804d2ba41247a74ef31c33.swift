#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public struct ExactRealTopologyDomain<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting, Cells: ExactRealCellPreparing & ExactRealCellProducing & ExactRealCellQuerying & ExactRealCellDescribing & ExactRealCellTraversing>: Sendable where Base.Source == Base.Value, Cells.Base == Base {
 public typealias Field = ExactAlgebraicScalarDomain<Base>
 public typealias Polynomial = ExactPolynomial<Field>
 public init(cells: Cells.Type) {}
}
