import L0
import L1
import L2
@testable import L3
import L4

@main struct LayerBenchmark {
 static func ledger() throws -> ExactScalarLedger {
  .init(limits:try .init(work:200_000_000,storageBytes:700_000_000,valueDepth:400,coefficientDepth:400))
 }
 static func phase<T>(_ label: String, _ a: inout ExactScalarLedger, _ body: (inout ExactScalarLedger) throws -> T) throws -> T {
  let work = a.work, storage = a.storageBytes, start = ContinuousClock.now
  let result = try body(&a)
  print("\(label) elapsed=\(start.duration(to:.now)) work=\(a.work-work) storage=\(a.storageBytes-storage)")
  return result
 }
 static func main() throws {
  var setup = try ledger()
  let f = ExactRationalScalarDomain(), one = try f.integer(1,using:&setup)
  let p = try ExactPolynomialDomain(field:f,variableCount:2,using:&setup)
  let law = try p.polynomial(terms:(0..<64).map { .init(powers:[$0,63-$0],coefficient:one) },using:&setup)
  let monomial = try p.polynomial(terms:[.init(powers:[2,3],coefficient:try f.integer(-2,using:&setup))],using:&setup)
  var l1 = try ledger()
  try phase("L1.monomial100",&l1) { a in
   for _ in 0..<100 {
    guard try p.multiplying(law,monomial,using:&a).termCount == 64 else { throw ExactPolynomialFailure.invalidCertificate }
   }
  }
  let r = try ExactRealRootDomain(field:f,using:&setup), rp = r.polynomials
  let x = try rp.variable(0,using:&setup)
  let value = try f.integer(2,using:&setup)
  let source = try r.bind(rp.subtracting(x,rp.constant(value,using:&setup),using:&setup),using:&setup)
  let singleton = try r.domain(lower:.finite(value),upper:.finite(value),using:&setup)
  let root = try r.isolate(source,in:singleton,limits:.init(maximumRoots:1),using:&setup).roots[0]
  let query = try r.bind(rp.polynomial(terms:[.init(powers:[6],coefficient:one),.init(powers:[0],coefficient:one)],using:&setup),using:&setup)
  var l2 = try ledger()
  try phase("L2.singleton100",&l2) { a in
   for _ in 0..<100 { guard try r.sign(of:query,at:root,using:&a) == .positive else { throw ExactRealRootFailure.invalidEvidence } }
  }
  let field = try ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:10,using:&setup)
  let d = try ExactRealCellDomain(field:field,variableCount:1,using:&setup)
  let coefficient = try field.integer(1,using:&setup)
  let quartic = try d.polynomials.polynomial(terms:[.init(powers:[4],coefficient:coefficient),.init(powers:[2],coefficient:coefficient),.init(powers:[0],coefficient:coefficient)],using:&setup)
  let roots = try ExactRealRootDomain(field:field,using:&setup)
  let all = try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&setup)
  let input = try d.bind(polynomials:[quartic],domains:[all],using:&setup)
  var l3 = try ledger()
  try phase("L3.projection3",&l3) { a in
   for _ in 0..<3 {
    let result = try ExactCellAccess.run(&a,inherited:input.depth) { try d.projection(input,&$0) }
    guard result.count == 1 else { throw ExactRealCellFailure.invalidCoverage }
   }
  }
  var a = try ledger()
  let cells = try ExactRealCellDomain(field:field,variableCount:4,using:&a), cp = cells.polynomials
  let variables = try (0..<4).map { try cp.variable($0,using:&a) }
  let box = try roots.domain(lower:.finite(field.integer(-1,using:&a)),upper:.finite(field.integer(1,using:&a)),using:&a)
  let folded = try cells.bind(polynomials:[cp.subtracting(cp.multiplying(variables[0],variables[0],using:&a),cp.multiplying(variables[2],variables[2],using:&a),using:&a),cp.subtracting(variables[1],variables[3],using:&a)],domains:[box,box,box,box],using:&a)
  let start = ContinuousClock.now
  let partition = try phase("pipeline.partition",&a) { try cells.decompose(folded,limits:.init(maximumStoredCells:2000,maximumRootsPerStack:40),using:&$0) }
  let selection = try cells.select(partition,matching:cells.predicate(instructions:[.sign(polynomial:0,relation:.equal),.sign(polynomial:1,relation:.equal),.and],for:folded,using:&a),using:&a)
  let topology = ExactRealTopology(cells:ExactRealCellDomain<ExactRationalScalarDomain>.self)
  let limits = try ExactRealTopologyLimits(maximumGeneratedCells:20000,maximumRootsPerStack:100,maximumClosures:1000,maximumAttachmentPieces:20000,maximumComponents:1000)
  let incidence = try phase("L4.incidence",&a) { try topology.incidence(of:selection,strategy:.automatic,limits:limits,using:&$0) }
  let components = try phase("L4.components",&a) { try topology.components(of:incidence,limits:limits,using:&$0) }
  guard selection.cells.count == 45, incidence.pairs.count == 2025, incidence.attachments.count == 108, components.count == 1 else { throw ExactRealTopologyFailure.invalidCoverage }
  print("pipeline.total elapsed=\(start.duration(to:.now)) work=\(a.work) storage=\(a.storageBytes)")
 }
}
