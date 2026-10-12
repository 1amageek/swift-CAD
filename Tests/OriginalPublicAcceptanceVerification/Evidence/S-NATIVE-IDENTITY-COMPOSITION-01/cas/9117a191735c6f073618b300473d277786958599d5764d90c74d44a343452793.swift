#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

enum ExactTopologyAccess {
 static func add(_ a: Int, _ b: Int) throws -> Int {
  let r = a.addingReportingOverflow(b)
  guard a >= 0, b >= 0, !r.overflow else { throw ExactRealTopologyFailure.countOverflow }; return r.partialValue
 }
 static func multiply(_ a: Int, _ b: Int) throws -> Int {
  let r = a.multipliedReportingOverflow(by:b)
  guard a >= 0, b >= 0, !r.overflow else { throw ExactRealTopologyFailure.countOverflow }; return r.partialValue
 }
 static func storage<T,A: ExactScalarAdmission & ~Copyable>(_ count: Int, _ type: T.Type, _ a: inout A) throws {
  try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:type))
 }
 static func accepts(_ sign: ExactSign, _ relation: ExactRealCellSignRelation) -> Bool {
  switch relation {
  case .equal: return sign == .zero
  case .notEqual: return sign != .zero
  case .less: return sign == .negative
  case .lessOrEqual: return sign != .positive
  case .greater: return sign == .positive
  case .greaterOrEqual: return sign != .negative
  }
 }
}
