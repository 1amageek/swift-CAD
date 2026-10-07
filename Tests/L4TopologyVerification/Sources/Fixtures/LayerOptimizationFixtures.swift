import L0
import L1
import L2
import L3
import L4

public enum LayerOptimizationFixtures {
 public static func orderedProducts() throws {
  var a = try TopologyFixtures.ledger()
  let f = ExactRationalScalarDomain(), p = try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
  let one = try f.integer(1,using:&a), negative = try f.integer(-3,using:&a)
  let law = try p.polynomial(terms:[.init(powers:[2,0],coefficient:one),.init(powers:[1,4],coefficient:negative),.init(powers:[0,1],coefficient:one)],using:&a)
  let mono = try p.polynomial(terms:[.init(powers:[3,2],coefficient:negative)],using:&a)
  var expected: [ExactPolynomialTerm<ExactRationalScalarDomain.Value>] = []
  for term in law.terms { expected.append(.init(powers:[term.powers[0]+3,term.powers[1]+2],coefficient:try f.multiplying(term.coefficient,negative,using:&a))) }
  let reference = try p.polynomial(terms:expected,using:&a)
  try TopologyFixtures.require(try p.equals(p.multiplying(law,mono,using:&a),reference,using:&a))
  try TopologyFixtures.require(try p.equals(p.multiplying(mono,law,using:&a),reference,using:&a))
  for integer in [-3,0,2] {
   let factor = try f.integer(integer,using:&a)
   expected = []
   for term in law.terms { expected.append(.init(powers:term.powers,coefficient:try f.multiplying(term.coefficient,factor,using:&a))) }
   try TopologyFixtures.require(try p.equals(p.scaled(law,by:factor,using:&a),p.polynomial(terms:expected,using:&a),using:&a))
  }
  let foreign = try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
  let other = try foreign.variable(0,using:&a)
  do { _ = try p.multiplying(law,other,using:&a); throw ExactRealTopologyFailure.invalidCoverage }
  catch ExactPolynomialFailure.incompatibleDomain { }
  let huge = try p.polynomial(terms:[.init(powers:[Int.max,0],coefficient:one)],using:&a)
  do { _ = try p.multiplying(huge,p.variable(0,using:&a),using:&a); throw ExactRealTopologyFailure.invalidCoverage }
  catch ExactPolynomialFailure.exponentOverflow { }
  var noStorage = ExactScalarLedger(limits:try .init(work:10000,storageBytes:0,valueDepth:400,coefficientDepth:400))
  do { _ = try p.multiplying(law,mono,using:&noStorage); throw ExactRealTopologyFailure.invalidCoverage }
  catch ExactPolynomialFailure.scalar(.resourceLimit(.storage)) { }
  var trace = try CheckpointAdmission()
  _ = try p.multiplying(law,mono,using:&trace)
  var cancel = try CheckpointAdmission(stop:trace.checkpoints)
  do { _ = try p.multiplying(law,mono,using:&cancel); throw ExactRealTopologyFailure.invalidCoverage }
  catch ExactPolynomialFailure.scalar(.cancelled) { }
 }
 public static func singletonSigns() throws {
  var a = try TopologyFixtures.ledger()
  let f = ExactRationalScalarDomain(), r = try ExactRealRootDomain(field:f,using:&a), p = r.polynomials
  let one = try f.integer(1,using:&a), two = try f.integer(2,using:&a), x = try p.variable(0,using:&a)
  let rootLaw = try r.bind(p.subtracting(x,p.constant(two,using:&a),using:&a),using:&a)
  let point = try r.domain(lower:.finite(two),upper:.finite(two),using:&a)
  let root = try r.isolate(rootLaw,in:point,limits:.init(maximumRoots:1),using:&a).roots[0]
  var saved: ExactRealRootSource<ExactRationalScalarDomain>? = nil
  for constant in [-5,-4,-3] {
   let law = try p.polynomial(terms:[.init(powers:[2],coefficient:one),.init(powers:[0],coefficient:try f.integer(constant,using:&a))],using:&a)
   let query = try r.bind(law,using:&a); saved = query
   let expected = try f.sign(of:p.evaluated(law,at:[two],using:&a).value,using:&a)
   try TopologyFixtures.require(try r.sign(of:query,at:root,using:&a) == expected)
  }
  let query = saved!
  let foreign = try ExactRealRootDomain(field:f,using:&a)
  do { _ = try foreign.sign(of:query,at:root,using:&a); throw ExactRealTopologyFailure.invalidCoverage }
  catch ExactRealRootFailure.incompatibleDomain { }
  var noWork = ExactScalarLedger(limits:try .init(work:0,storageBytes:100000,valueDepth:400,coefficientDepth:400))
  do { _ = try r.sign(of:query,at:root,using:&noWork); throw ExactRealTopologyFailure.invalidCoverage }
  catch ExactRealRootFailure.scalar(.resourceLimit(.work)) { }
  var trace = try CheckpointAdmission()
  _ = try r.sign(of:query,at:root,using:&trace)
  var cancel = try CheckpointAdmission(stop:trace.checkpoints)
  do { _ = try r.sign(of:query,at:root,using:&cancel); throw ExactRealTopologyFailure.invalidCoverage }
  catch ExactRealRootFailure.scalar(.cancelled) { }
 }
 public static func retainedPairTruth() throws {
  var a = try TopologyFixtures.ledger()
  let (f,d,_) = try TopologyFixtures.setup(1,&a), p = d.polynomials
  let r = try ExactRealRootDomain(field:f,using:&a)
  let box = try r.domain(lower:.finite(f.integer(-2,using:&a)),upper:.finite(f.integer(2,using:&a)),using:&a)
  let source = try d.bind(polynomials:[p.variable(0,using:&a)],domains:[box],using:&a)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:10),using:&a)
  let selection = try d.select(partition,matching:d.predicate(instructions:[.literal(true)],for:source,using:&a),using:&a)
  let topology = TopologyFixtures.Topology(cells:TopologyFixtures.Cells.self), limits = try TopologyFixtures.limits()
  let incidence = try topology.incidence(of:selection,strategy:.automatic,limits:limits,using:&a)
  let queries = try [-2,-1,0,1,2].map { try d.point(field:f,coordinates:[f.integer($0,using:&a)],using:&a) }
  try TopologyFixtures.require(selection.cells.count == 5)
  // Exact analytic oracle for {-2}, (-2,0), {0}, (0,2), {2}.
  // Each query is the unique listed representative of its original target cell.
  for i in selection.cells.indices {
   for j in selection.cells.indices where i != j {
    let pair = incidence.pairs[i*selection.cells.count+j], region = pair.region!
    let provider = try TopologyFixtures.Cells(retaining:region.partition.source,using:&a)
    for q in queries.indices {
     let inClosure = i == 0 ? q == 0 : i == 1 ? q <= 2 : i == 2 ? q == 2 : i == 3 ? q >= 2 : q == 4
     let expected = q == j && inClosure
     guard let id = try provider.locatePrefix(queries[q],in:region.partition,limits:.init(maximumRoots:10),using:&a),
      let index = region.cells.firstIndex(of:id) else { throw ExactRealTopologyFailure.invalidCoverage }
     try TopologyFixtures.require(region.included[index] == expected)
    }
   }
  }
  let components = try topology.components(of:incidence,limits:limits,using:&a)
  try TopologyFixtures.require(components.count == 1 && components.members == Array(selection.cells))
  try TopologyFixtures.require(components.witnesses == Array(incidence.attachments.indices))
  let x = try p.variable(0,using:&a)
  let one = try p.constant(f.integer(1,using:&a),using:&a)
  let split = try d.bind(polynomials:[p.subtracting(x,one,using:&a),p.adding(x,one,using:&a)],domains:[box],using:&a)
  let splitPartition = try d.decompose(split,limits:.init(maximumStoredCells:100,maximumRootsPerStack:10),using:&a)
  let separated = try d.select(splitPartition,matching:d.predicate(instructions:[.sign(polynomial:0,relation:.notEqual),.sign(polynomial:1,relation:.notEqual),.and],for:split,using:&a),using:&a)
  let graph = try topology.incidence(of:separated,strategy:.automatic,limits:limits,using:&a)
  let parts = try topology.components(of:graph,limits:limits,using:&a)
  try TopologyFixtures.require(parts.memberRanges.map { $0.count } == [2,1,2])
  try TopologyFixtures.require(parts.witnessRanges.map { $0.count } == [1,0,1])
  try TopologyFixtures.require(parts.members == Array(separated.cells) && parts.witnesses == [0,1])
 }
 public static func run() throws {
  try orderedProducts(); try singletonSigns(); try retainedPairTruth()
  print("PASS: ordered products, singleton signs and complete retained pair truth")
 }
}
