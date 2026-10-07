#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

public enum ExactRealTopologyFailure: Error {
 case invalidDefinition, invalidFormula, foreignReceipt, invalidCoverage, countOverflow, unresolved
 case generatedCellLimit, closureLimit, attachmentLimit, componentLimit
 case scalar(ExactScalarFailure), polynomial(ExactPolynomialFailure), cell(ExactRealCellFailure)
 case root(ExactRealRootFailure), operationRejected(any Error)
 static func preserving(_ error: any Error) -> Self {
  if let e = error as? Self { return e }
  if let e = error as? ExactScalarFailure { return .scalar(e) }
  if let e = error as? ExactPolynomialFailure { return .polynomial(e) }
  if let e = error as? ExactRealCellFailure { return .cell(e) }
  if let e = error as? ExactRealRootFailure { return .root(e) }
  return .operationRejected(error)
 }
}
