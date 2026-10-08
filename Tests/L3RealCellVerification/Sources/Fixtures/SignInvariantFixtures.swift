import L0
import L1
import L2
import L3

public enum SignInvariantFixtures {
 private static func issued<D: ExactRealCellDescribing & ExactRealCellQuerying>(
  _ domain: D, _ polynomial: ExactPolynomial<ExactAlgebraicScalarDomain<D.Base>>,
  _ partition: ExactRealCellPartition<D.Base>, _ a: inout ExactScalarLedger
 ) throws -> ExactRealCellSignInvariant<D.Base> {
  guard let invariant = try domain.signInvariant(for: polynomial, in: partition, using: &a) else {
   throw ExactRealCellFailure.invalidCoverage
  }
  for cell in partition.cells { _ = try domain.sign(of: invariant, at: cell, using: &a) }
  return invariant
 }

 public static func run() throws {
  var a = try CellFixtures.ledger()
  let (field, domain, _) = try CellFixtures.setup(2, &a), p = domain.polynomials
  let x = try p.variable(0, using: &a), y = try p.variable(1, using: &a)
  let squared = try p.multiplying(x, x, using: &a)
  let one = try field.integer(1, using: &a)
  let quarter = try field.dividing(one, field.integer(4, using: &a), using: &a)
  let roots = try ExactRealRootDomain(field: field, using: &a)
  let xBox = try roots.domain(lower: .finite(field.integer(-1, using: &a)), upper: .finite(one), using: &a)
  let yBox = try roots.domain(lower: .finite(quarter), upper: .finite(one), using: &a)
  let sourceLaw = try p.subtracting(y, squared, using: &a)
  let source = try domain.bind(polynomials: [sourceLaw], domains: [xBox, yBox], using: &a)
  let limits = try ExactRealCellLimits(maximumStoredCells: 200, maximumRootsPerStack: 20)
  let partition = try domain.decompose(source, limits: limits, using: &a)
  let cut = try p.subtracting(squared, p.constant(quarter, using: &a), using: &a)
  let positive = try issued(domain, p.scaled(cut, by: field.integer(2, using: &a), using: &a), partition, &a)
  let negative = try issued(domain, p.scaled(cut, by: field.integer(-3, using: &a), using: &a), partition, &a)
  try CellFixtures.require(positive.axis == 0 && negative.axis == 0)
  try CellFixtures.require(positive.orientation == .positive && negative.orientation == .negative)
  try CellFixtures.require(try p.isZero(positive.remainder, using: &a))
  try CellFixtures.require(try p.equals(positive.polynomial,
   p.multiplying(positive.quotient, positive.projectionLaw, using: &a), using: &a))
  let original = try issued(domain, sourceLaw, partition, &a)
  try CellFixtures.require(original.axis == 1)
  // The quadratic lower-domain cut is projected from the graph and y box, not a source law.
  try CellFixtures.require(try !p.equals(cut, sourceLaw, using: &a))
  let threeQuarters = try field.dividing(field.integer(3, using: &a), field.integer(4, using: &a), using: &a)
  let half = try field.dividing(one, field.integer(2, using: &a), using: &a)
  let zero = try field.integer(0, using: &a)
  for (station, expected) in [(zero, ExactSign.negative), (half, .zero), (threeQuarters, .positive)] {
   let point = try domain.point(field: field, coordinates: [station, half], using: &a)
   guard let cell = try domain.locate(point, in: partition, limits: .init(maximumRoots: 20), using: &a) else {
    throw ExactRealCellFailure.invalidCoverage
   }
   try CellFixtures.require(try domain.sign(of: positive, at: cell, using: &a) == expected)
   let inverse: ExactSign = expected == .negative ? .positive : expected == .positive ? .negative : .zero
   try CellFixtures.require(try domain.sign(of: negative, at: cell, using: &a) == inverse)
   guard let prefix = cell.parent else { throw ExactRealCellFailure.invalidCoverage }
   try CellFixtures.require(try domain.sign(of: positive, at: prefix, using: &a) == expected)
   do {
    _ = try domain.sign(of: original, at: prefix, using: &a)
    throw ExactRealCellFailure.invalidCoverage
   } catch ExactRealCellFailure.invalidCell { }
  }
  // Same source and provider still cannot authorize a different partition's cell.
  let foreign = try domain.decompose(source, limits: limits, using: &a)
  do {
   _ = try domain.sign(of: positive, at: foreign.cells[0], using: &a)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.invalidCell { }
  let (_, foreignDomain, _) = try CellFixtures.setup(2, &a)
  do {
   _ = try foreignDomain.sign(of: positive, at: partition.cells[0], using: &a)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.incompatibleDomain { }
  let unmatched = try p.adding(cut, p.constant(field.integer(7, using: &a), using: &a), using: &a)
  try CellFixtures.require(try domain.signInvariant(for: unmatched, in: partition, using: &a) == nil)
  try CellFixtures.require(try domain.signInvariant(for: p.zero(using: &a), in: partition, using: &a) == nil)
  try failures(domain, cut, partition, positive)
  try auxiliaryAndLifetime()
 }

 private static func failures(_ domain: CellFixtures.Domain, _ law: CellFixtures.Polynomial,
  _ partition: ExactRealCellPartition<CellFixtures.Base>, _ invariant: ExactRealCellSignInvariant<CellFixtures.Base>
 ) throws {
  let cell = partition.cells[0]
  for storage in [false, true] {
   var short = ExactScalarLedger(limits: try .init(work: storage ? 1_000_000 : 0,
    storageBytes: storage ? 0 : 10_000_000, valueDepth: 400, coefficientDepth: 400))
   do {
    _ = try domain.signInvariant(for: law, in: partition, using: &short)
    throw ExactRealCellFailure.invalidCoverage
   } catch ExactRealCellFailure.scalar(.resourceLimit(let resource)) {
    switch resource {
    case .storage: try CellFixtures.require(storage)
    case .work: try CellFixtures.require(!storage)
    default: throw ExactRealCellFailure.invalidCoverage
    }
   }
  }
  try CellFixtures.require(invariant.depth.value > 0)
  var shallow = ExactScalarLedger(limits: try .init(work: 1_000_000, storageBytes: 10_000_000,
   valueDepth: invariant.depth.value - 1, coefficientDepth: 400))
  do {
   _ = try domain.sign(of: invariant, at: cell, using: &shallow)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.scalar(.resourceLimit(.valueDepth)) { }
  var issued = TerminalAdmission()
  _ = try domain.signInvariant(for: law, in: partition, using: &issued)
  var cancelIssue = TerminalAdmission(cancelAt: issued.checkpoints)
  do {
   _ = try domain.signInvariant(for: law, in: partition, using: &cancelIssue)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.scalar(.cancelled) { }
  var queried = TerminalAdmission()
  _ = try domain.sign(of: invariant, at: cell, using: &queried)
  var cancelQuery = TerminalAdmission(cancelAt: queried.checkpoints)
  do {
   _ = try domain.sign(of: invariant, at: cell, using: &cancelQuery)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.scalar(.cancelled) { }
 }

 private static func auxiliaryAndLifetime() throws {
  let retained: ExactRealCellSignInvariant<CellFixtures.Base>
  var a = try CellFixtures.ledger()
  do {
   let (field, domain, all) = try CellFixtures.setup(1, &a), p = domain.polynomials
   let x = try p.variable(0, using: &a)
   let sourceLaw = try p.adding(p.multiplying(x, x, using: &a),
    p.constant(field.integer(1, using: &a), using: &a), using: &a)
   let source = try domain.bind(polynomials: [sourceLaw], domains: [all], using: &a)
   let partition = try domain.decompose(source, limits: .init(maximumStoredCells: 10, maximumRootsPerStack: 10), using: &a)
   try CellFixtures.require(partition.cells.count == 1)
   let derivative = try p.differentiated(sourceLaw, in: 0, using: &a)
   // 2x changes sign in this sole sector despite its stored sample sign being zero.
   try CellFixtures.require(try domain.signInvariant(for: derivative, in: partition, using: &a) == nil)
   retained = try issued(domain, sourceLaw, partition, &a)
   let rootDomain = try ExactRealRootDomain(field: field, using: &a)
   let empty = try domain.bind(polynomials: [sourceLaw], domains: [rootDomain.emptyDomain(using: &a)], using: &a)
   let emptyPartition = try domain.decompose(empty, limits: .init(maximumStoredCells: 0, maximumRootsPerStack: 0), using: &a)
   try CellFixtures.require(try domain.signInvariant(for: sourceLaw, in: emptyPartition, using: &a) == nil)
  }
  let recovered = try CellFixtures.Domain(retaining: retained.partition.source, using: &a)
  try CellFixtures.require(try recovered.sign(of: retained, at: retained.partition.cells[0], using: &a) == .positive)
 }
}
