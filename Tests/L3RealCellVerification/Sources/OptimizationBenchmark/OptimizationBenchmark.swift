import L0
import L1
import L2
import L2Fixtures
import L3Fixtures
@testable import L3

@main struct OptimizationBenchmark {
 static func ledger() throws -> ExactScalarLedger {
  .init(limits: try .init(work: 200_000_000, storageBytes: 700_000_000, valueDepth: 400, coefficientDepth: 400))
 }
 static func report(_ label: String, _ repetitions: Int, _ body: (inout ExactScalarLedger) throws -> Void) throws {
  var a = try ledger()
  let elapsed = try ContinuousClock().measure {
   for _ in 0..<repetitions { try body(&a) }
  }
  print("\(label) repetitions=\(repetitions) work=\(a.work) storage=\(a.storageBytes) elapsed=\(elapsed)")
 }
 static func relations(_ repetitions: Int) throws {
  let weighted = try ContinuousClock().measure {
   for _ in 0..<repetitions { try WeightedOriginalFixtures.verify() }
  }
  let tower = try ContinuousClock().measure {
   for _ in 0..<repetitions { try FieldFixtures.tower() }
  }
  print("L3.weighted repetitions=\(repetitions) elapsed=\(weighted)")
  print("L2.tower repetitions=\(repetitions) elapsed=\(tower)")
 }
 static func main() throws {
  if CommandLine.arguments.contains("--relations") { try relations(3); return }
  if CommandLine.arguments.contains("--profile") { try relations(8); return }
  var a = try ledger()
  let f = ExactRationalScalarDomain()
  let left = try f.canonical(sign: 1, numerator: [1,0,0,0,7], denominator: [3], using: &a)
  let right = try f.canonical(sign: 1, numerator: [2,0,0,0,8], denominator: [3], using: &a)
  try report("L0.compare", 1000) { q in
   guard try f.compare(left, right, using: &q) == .less else { throw ExactScalarFailure.invalidEvidence }
  }
  let p = try ExactPolynomialDomain(field: f, variableCount: 1, using: &a)
  let one = try f.integer(1, using: &a)
  let lhs = try p.polynomial(terms: (0..<64).map { .init(powers: [2*$0], coefficient: one) }, using: &a)
  let rhs = try p.polynomial(terms: (0..<64).map { .init(powers: [2*$0+1], coefficient: one) }, using: &a)
  try report("L1.add", 100) { q in
   guard try p.adding(lhs,rhs,using:&q).termCount == 128 else { throw ExactPolynomialFailure.invalidCertificate }
  }
  let r = try ExactRealRootDomain(field:f,using:&a), rp = r.polynomials
  let x = try rp.variable(0,using:&a)
  let law = try rp.multiplying(rp.subtracting(x,rp.constant(f.integer(-2,using:&a),using:&a),using:&a), rp.subtracting(x,rp.constant(f.integer(3,using:&a),using:&a),using:&a),using:&a)
  let source = try r.bind(law,using:&a)
  let all = try r.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
  let roots = try r.isolate(source,in:all,limits:.init(maximumRoots:10),using:&a).roots
  try report("L2.compare",100) { q in
   guard try r.compare(roots[0],roots[1],using:&q) == .less else { throw ExactRealRootFailure.invalidEvidence }
  }
  let field = try ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:10,using:&a)
  let d = try ExactRealCellDomain(field:field,variableCount:2,using:&a)
  let coefficient = try field.integer(1,using:&a)
  let sparse = try d.polynomials.polynomial(terms:(0..<4).map { .init(powers:[$0+1,$0*16],coefficient:coefficient) },using:&a)
  try report("L3.coefficients",100) { q in
   let cs = try ExactCellAccess.run(&q) { try d.coefficientVector(sparse,axis:1,&$0) }
   guard cs.count == 49 else { throw ExactRealCellFailure.invalidCoverage }
  }
 }
}
