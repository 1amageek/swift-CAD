import L0
import L1
import L2
import L3
import L4

public enum ConstantCutGraphFixtures {
 public static func run() throws {
  var a = try TopologyFixtures.ledger()
  let (f, d, _) = try TopologyFixtures.setup(2, &a), p = d.polynomials
  let x = try p.variable(0, using: &a), y = try p.variable(1, using: &a)
  let square = try p.multiplying(x, x, using: &a)
  let roots = try ExactRealRootDomain(field: f, using: &a)
  let horizontal = try roots.domain(lower: .finite(f.integer(-2, using: &a)),
   upper: .finite(f.integer(2, using: &a)), using: &a)
  let vertical = try roots.domain(lower: .finite(f.integer(0, using: &a)),
   upper: .finite(f.integer(4, using: &a)), using: &a)
  let source = try d.bind(polynomials: [p.subtracting(y, square, using: &a),
   p.subtracting(square, p.constant(f.integer(1, using: &a), using: &a), using: &a)],
   domains: [horizontal, vertical], using: &a)
  let partition = try d.decompose(source, limits: .init(maximumStoredCells: 2000, maximumRootsPerStack: 100), using: &a)
  let selected = try d.select(partition, matching: d.predicate(instructions: [
   .sign(polynomial: 0, relation: .equal), .sign(polynomial: 1, relation: .greaterOrEqual), .and
  ], for: source, using: &a), using: &a)
  let topology = TopologyFixtures.Topology(cells: TopologyFixtures.Cells.self), cap = try TopologyFixtures.limits()
  let incidence = try topology.incidence(of: selected, strategy: .automatic, limits: cap, using: &a)
  try TopologyFixtures.require(try topology.components(of: incidence, limits: cap, using: &a).count == 2)
  var proved = 0
  for closure in incidence.closures where closure.definition.cell.dimension > 0 {
   try TopologyFixtures.require(closure.proof == .polynomialGraph)
   try TopologyFixtures.require(closure.region.signInvariants.contains { $0.projectionInvariant != nil })
   for proof in closure.region.signInvariants where proof.projectionInvariant != nil {
    try TopologyFixtures.require(proof.incomingLaw == nil && proof.quotient == nil && proof.remainder == nil)
   }
   let sample = try d.sample(of: closure.definition.cell, in: partition, using: &a)
   let side = try sample.field.sign(of: sample.coordinates[0], using: &a)
   for value in [-2, -1, 0, 1, 2] {
    let point = try d.point(field: f, coordinates: [f.integer(value, using: &a),
     f.integer(value * value, using: &a)], using: &a)
    let expected = side == .negative ? value <= -1 : value >= 1
    try TopologyFixtures.require(try topology.contains(point, in: closure, limits: cap, using: &a) == expected)
   }
   proved += 1
  }
  try TopologyFixtures.require(proved == 2)
  print("PASS: constant-cut polynomial closures preserve both roots work=\(a.work) storage=\(a.storageBytes)")
 }
}
