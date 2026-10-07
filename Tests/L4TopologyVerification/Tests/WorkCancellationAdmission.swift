import L0

struct WorkCancellationAdmission: ~Copyable, ExactScalarAdmission {
 var ledger: ExactScalarLedger
 let stop: Int
 init(stop: Int) throws {
  ledger = .init(limits:try .init(work:200_000_000,storageBytes:700_000_000,valueDepth:400,coefficientDepth:400))
  self.stop = stop
 }
 mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
 mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
  try ledger.consumeWork(units)
  if ledger.work >= stop { throw .cancelled }
 }
 mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
 mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
  try ledger.admitDepth(value:value,coefficient:coefficient)
 }
}
