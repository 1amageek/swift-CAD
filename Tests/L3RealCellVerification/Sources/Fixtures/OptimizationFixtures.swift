import L0
import L1
import L2

public enum OptimizationFixtures {
 public static func run() throws {
  var a = try CellFixtures.ledger()
  let f = ExactRationalScalarDomain()
  var values: [ExactRationalCoefficient] = []
  for integer in -2...2 { values.append(try f.integer(integer,using:&a)) }
  for denominator in [3,5,7] {
   values.append(try f.dividing(f.integer(1,using:&a),f.integer(denominator,using:&a),using:&a))
   values.append(try f.dividing(f.integer(2,using:&a),f.integer(denominator,using:&a),using:&a))
  }
  let large = try f.canonical(sign:1,numerator:[1,0,0,0,7],denominator:[3],using:&a)
  values.append(large); values.append(try f.negated(large,using:&a))
  for lhs in values { for rhs in values {
   let sign = try f.sign(of:f.subtracting(lhs,rhs,using:&a),using:&a)
   let expected: ExactOrder = sign == .zero ? .equal : sign == .negative ? .less : .greater
   try CellFixtures.require(try f.compare(lhs,rhs,using:&a) == expected)
  } }
  var observed = TerminalAdmission()
  _ = try f.compare(large,large,using:&observed)
  var cancelled = TerminalAdmission(cancelAt:observed.checkpoints)
  do { _ = try f.compare(large,large,using:&cancelled); throw ExactScalarFailure.invalidEvidence }
  catch ExactScalarFailure.cancelled { }
  var denied = ExactScalarLedger(limits:try .init(work:0,storageBytes:1000,valueDepth:400,coefficientDepth:400))
  do { _ = try f.compare(large,large,using:&denied); throw ExactScalarFailure.invalidEvidence }
  catch ExactScalarFailure.resourceLimit(.work) { }

  let p = try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
  let lhs = try p.polynomial(terms:[.init(powers:[3,0],coefficient:f.integer(2,using:&a)),
   .init(powers:[1,1],coefficient:f.integer(3,using:&a)),.init(powers:[0,0],coefficient:f.integer(4,using:&a))],using:&a)
  let rhs = try p.polynomial(terms:[.init(powers:[4,0],coefficient:f.integer(-1,using:&a)),
   .init(powers:[3,0],coefficient:f.integer(-2,using:&a)),.init(powers:[1,1],coefficient:f.integer(5,using:&a)),
   .init(powers:[0,1],coefficient:f.integer(6,using:&a)),.init(powers:[0,0],coefficient:f.integer(-4,using:&a))],using:&a)
  let sum = try p.polynomial(terms:lhs.terms+rhs.terms,using:&a)
  var differenceTerms = lhs.terms
  for term in rhs.terms { differenceTerms.append(.init(powers:term.powers,coefficient:try f.negated(term.coefficient,using:&a))) }
  let difference = try p.polynomial(terms:differenceTerms,using:&a)
  try CellFixtures.require(try p.equals(p.adding(lhs,rhs,using:&a),sum,using:&a))
  try CellFixtures.require(try p.equals(p.subtracting(lhs,rhs,using:&a),difference,using:&a))
  try CellFixtures.require(try p.isZero(p.subtracting(lhs,lhs,using:&a),using:&a))
  let zero = try p.zero(using:&a)
  try CellFixtures.require(try p.equals(p.adding(zero,lhs,using:&a),lhs,using:&a))
  let foreign = try ExactPolynomialDomain(field:f,variableCount:2,using:&a).zero(using:&a)
  do { _ = try p.adding(lhs,foreign,using:&a); throw ExactPolynomialFailure.invalidCertificate }
  catch ExactPolynomialFailure.incompatibleDomain { }
  var merge = TerminalAdmission(); _ = try p.adding(lhs,rhs,using:&merge)
  var cancelledMerge = TerminalAdmission(cancelAt:merge.checkpoints)
  do { _ = try p.adding(lhs,rhs,using:&cancelledMerge); throw ExactPolynomialFailure.invalidCertificate }
  catch ExactPolynomialFailure.scalar(.cancelled) { }
  var noStorage = ExactScalarLedger(limits:try .init(work:10000,storageBytes:0,valueDepth:400,coefficientDepth:400))
  do { _ = try p.adding(lhs,rhs,using:&noStorage); throw ExactPolynomialFailure.invalidCertificate }
  catch ExactPolynomialFailure.scalar(.resourceLimit(.storage)) { }

  let r = try ExactRealRootDomain(field:f,using:&a), rp = r.polynomials
  let x = try rp.variable(0,using:&a)
  let law = try rp.multiplying(rp.subtracting(x,rp.constant(f.integer(-2,using:&a),using:&a),using:&a),rp.subtracting(x,rp.constant(f.integer(3,using:&a),using:&a),using:&a),using:&a)
  let all = try r.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
  let roots = try r.isolate(r.bind(law,using:&a),in:all,limits:.init(maximumRoots:10),using:&a).roots
  try CellFixtures.require(try r.compare(roots[0],roots[1],using:&a) == .less)
  try CellFixtures.require(try r.compare(roots[1],roots[0],using:&a) == .greater)
  try CellFixtures.require(try r.compare(roots[0],roots[0],using:&a) == .equal)
  let linear = try rp.subtracting(x,rp.constant(f.integer(3,using:&a),using:&a),using:&a)
  let same = try r.isolate(r.bind(linear,using:&a),in:all,limits:.init(maximumRoots:10),using:&a).roots[0]
  try CellFixtures.require(try r.compare(roots[1],same,using:&a) == .equal)
  var comparison = TerminalAdmission(); _ = try r.compare(roots[0],roots[1],using:&comparison)
  var cancelledComparison = TerminalAdmission(cancelAt:comparison.checkpoints)
  do { _ = try r.compare(roots[0],roots[1],using:&cancelledComparison); throw ExactRealRootFailure.invalidEvidence }
  catch ExactRealRootFailure.scalar(.cancelled) { }
  let other = try ExactRealRootDomain(field:f,using:&a)
  do { _ = try other.compare(roots[0],roots[1],using:&a); throw ExactRealRootFailure.invalidEvidence }
  catch ExactRealRootFailure.incompatibleDomain { }
 }
}
