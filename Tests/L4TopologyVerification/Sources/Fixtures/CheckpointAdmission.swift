import L0

public struct CheckpointAdmission: ~Copyable, ExactScalarAdmission {
 public var ledger: ExactScalarLedger
 public private(set) var checkpoints = 0
 public let stop: Int?
 public init(stop: Int? = nil) throws {
  ledger = try TopologyFixtures.ledger(); self.stop = stop
 }
 public mutating func checkpoint() throws(ExactScalarFailure) {
  checkpoints += 1
  if checkpoints == stop { throw .cancelled }
  try ledger.checkpoint()
 }
 public mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units); try checkpoint() }
 public mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes); try checkpoint() }
 public mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
  try ledger.admitDepth(value:value,coefficient:coefficient); try checkpoint()
 }
}
