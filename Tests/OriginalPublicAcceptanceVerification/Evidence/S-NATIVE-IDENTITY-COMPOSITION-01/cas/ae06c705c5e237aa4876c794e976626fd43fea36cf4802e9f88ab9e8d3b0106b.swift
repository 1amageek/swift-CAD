#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain {
 func power(_ value: Field.Value, _ exponent: Int, field: Field, _ a: inout ExactCellBorrowedAdmission) throws -> Field.Value {
  // Import retains field authority and depth without allocating a unit product.
  if exponent == 1 { return try field.importing(value,using:&a) }
  var result = try field.integer(1,using:&a), factor=value, n=exponent
  while n > 0 {
   try a.consumeWork(1)
   if n & 1 == 1 { result = try field.multiplying(result,factor,using:&a) }
   n /= 2; if n > 0 { factor = try field.multiplying(factor,factor,using:&a) }
  }; return result
 }
 func specialize(_ law: Polynomial, prefix: ExactRealCellSample<Base>, axis: Int,
  into p: ExactPolynomialDomain<Field>, _ a: inout ExactCellBorrowedAdmission) throws -> Polynomial {
  try ExactCellAccess.admit(law.depth,&a); try ExactCellAccess.admit(prefix.depth,&a)
  guard axis == prefix.coordinates.count, axis < law.variableCount, p.variableCount == 1 else { throw ExactRealCellFailure.invalidVariable }
  try ExactCellAccess.storage(law.termCount,ExactPolynomialTerm<Field.Value>.self,&a)
  var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
  for term in law.terms {
   var coefficient = try prefix.field.importing(term.coefficient,using:&a)
   for slot in term.powers.indices {
    try a.consumeWork(1)
    if slot < axis && term.powers[slot] > 0 {
     coefficient = try prefix.field.multiplying(coefficient,power(prefix.coordinates[slot],term.powers[slot],field:prefix.field,&a),using:&a)
    } else if slot > axis && term.powers[slot] != 0 { throw ExactRealCellFailure.invalidCoverage }
   }
   try ExactCellAccess.storage(1,Int.self,&a)
   terms.append(.init(powers:[term.powers[axis]],coefficient:coefficient))
  }
  return try p.polynomial(terms:terms,using:&a)
 }
 func evaluate(_ law: Polynomial, at point: ExactRealCellSample<Base>, _ a: inout ExactCellBorrowedAdmission) throws -> Field.Value {
  try ExactCellAccess.admit(law.depth,&a); try ExactCellAccess.admit(point.depth,&a)
  var sum = try point.field.integer(0,using:&a)
  for term in law.terms {
   var value = try point.field.importing(term.coefficient,using:&a)
   for slot in term.powers.indices where term.powers[slot] != 0 {
    try a.consumeWork(1)
    guard slot < point.coordinates.count else { throw ExactRealCellFailure.invalidCoverage }
    value = try point.field.multiplying(value,power(point.coordinates[slot],term.powers[slot],field:point.field,&a),using:&a)
   }
   sum = try point.field.adding(sum,value,using:&a)
  }; return sum
 }
 func inside(_ value: Field.Value, field: Field, domain: ExactRealRootInterval<Field.Value>, _ a: inout ExactCellBorrowedAdmission) throws -> Bool {
  try ExactCellAccess.admit(domain.depth,&a)
  if domain.isEmpty { return false }
  if case .finite(let lower) = domain.lower {
   let order = try field.compare(value,field.importing(lower,using:&a),using:&a)
   if order == .less || (order == .equal && !domain.includesLower) { return false }
  }
  if case .finite(let upper) = domain.upper {
   let order = try field.compare(value,field.importing(upper,using:&a),using:&a)
   if order == .greater || (order == .equal && !domain.includesUpper) { return false }
  }; return true
 }
}
