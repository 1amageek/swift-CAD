import L0
import L1
import L2
import L3

public enum VisitAdmissionFixtures {
 private enum Rejection: Error { case cellLimit }

 private struct Admission: ~Copyable, ExactScalarAdmission {
  private var ledger: ExactScalarLedger
  let maximumVisits: Int
  var visits = 0
  var valueVisits = 0
  var coefficientVisits = 0
  var maximumValueDepth = 0
  var maximumCoefficientDepth = 0
  var cancelAtVisit: Int?

  init(maximumVisits: Int = Int.max, cancelAtVisit: Int? = nil) throws {
   self.maximumVisits = maximumVisits; self.cancelAtVisit = cancelAtVisit
   ledger = try CellFixtures.ledger()
  }

  mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
  mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
  mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes: bytes) }
  mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
   try ledger.admitDepth(value: value, coefficient: coefficient)
  }
  mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
   try ledger.visitCell(axis: axis, depth: depth)
   guard visits < maximumVisits else { throw .admissionRejected(Rejection.cellLimit) }
   visits += 1
   switch axis {
   case .value: valueVisits += 1; maximumValueDepth = max(maximumValueDepth, depth)
   case .coefficient: coefficientVisits += 1; maximumCoefficientDepth = max(maximumCoefficientDepth, depth)
   }
   if visits == cancelAtVisit { ledger.cancel() }
  }
 }

 public static func run() throws {
  var preparation = try CellFixtures.ledger()
  let (_, zeroDomain, _) = try CellFixtures.setup(0, &preparation)
  let zeroSource = try zeroDomain.bind(polynomials: [], domains: [], using: &preparation)
  var origin = try Admission(maximumVisits: 1)
  let zero = try zeroDomain.decompose(zeroSource,
   limits: .init(maximumStoredCells: 1, maximumRootsPerStack: 0), using: &origin)
  try CellFixtures.require(zero.storedCellCount == 1 && origin.visits == 1 && origin.valueVisits == 1)
  var absent = try Admission(maximumVisits: 0)
  do {
   _ = try zeroDomain.decompose(zeroSource,
    limits: .init(maximumStoredCells: 1, maximumRootsPerStack: 0), using: &absent)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.scalar(.admissionRejected(let cause)) {
   guard case Rejection.cellLimit = cause else { throw cause }
  }
  var cancelled = try Admission(cancelAtVisit: 1)
  do {
   _ = try zeroDomain.decompose(zeroSource,
    limits: .init(maximumStoredCells: 1, maximumRootsPerStack: 0), using: &cancelled)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.scalar(.cancelled) { }
  try CellFixtures.require(cancelled.visits == 1)

  let (_, domain, all) = try CellFixtures.setup(1, &preparation)
  let source = try domain.bind(polynomials: [domain.polynomials.variable(0, using: &preparation)],
   domains: [all], using: &preparation)
  let limits = try ExactRealCellLimits(maximumStoredCells: 20, maximumRootsPerStack: 10)
  var measured = try Admission()
  let first = try domain.decompose(source, limits: limits, using: &measured)
  let firstVisits = measured.visits
  try CellFixtures.require(first.cells.count == 3 && first.storedCellCount == 4
   && firstVisits > first.storedCellCount && measured.valueVisits == firstVisits
   && first.depth.value >= measured.maximumValueDepth)
  let second = try domain.decompose(source, limits: limits, using: &measured)
  try CellFixtures.require(second.storedCellCount == first.storedCellCount
   && measured.visits == firstVisits * 2)

  var exact = try Admission(maximumVisits: measured.visits)
  _ = try domain.decompose(source, limits: limits, using: &exact)
  _ = try domain.decompose(source, limits: limits, using: &exact)
  try CellFixtures.require(exact.visits == measured.visits)
  var short = try Admission(maximumVisits: measured.visits - 1)
  _ = try domain.decompose(source, limits: limits, using: &short)
  do {
   _ = try domain.decompose(source, limits: limits, using: &short)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.scalar(.admissionRejected(let cause)) {
   guard case Rejection.cellLimit = cause else { throw cause }
  }
  try CellFixtures.require(short.visits == measured.visits - 1)
 }
}
