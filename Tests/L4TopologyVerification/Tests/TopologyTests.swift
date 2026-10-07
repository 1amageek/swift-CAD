import Testing
import L4Fixtures
@Test(.timeLimit(.minutes(1))) func affineClosures() throws { try TopologyFixtures.affineClosures() }
@Test(.timeLimit(.minutes(1))) func quantifiedClosure() throws { try TopologyFixtures.quantifiedClosure() }
@Test(.timeLimit(.minutes(1))) func graphClosure() throws { try TopologyFixtures.graphClosure() }

@Test(.timeLimit(.minutes(1))) func zeroAndFailures() throws { try TopologyFixtures.zeroAndFailures() }
@Test(.timeLimit(.minutes(1))) func connectivity() throws { try TopologyFixtures.connectivity() }
@Test(.timeLimit(.minutes(1))) func partialTarget() throws { try TopologyFixtures.partialTarget() }

@Test(.timeLimit(.minutes(1))) func singularComponents() throws { try TopologyFixtures.singularComponents() }
@Test(.timeLimit(.minutes(1))) func partialIncidence() throws { try TopologyFixtures.partialIncidence() }
@Test(.timeLimit(.minutes(2))) func folded() throws { try TopologyFixtures.folded() }

@Test(.timeLimit(.minutes(1))) func retainedAlgebraicField() throws { try LifecycleFixtures.retained() }
@Test(.timeLimit(.minutes(1))) func countLimitsAndCancellation() throws { try LifecycleFixtures.resourcesAndCancellation() }

import L0
import L1
import L2
import L3
@testable import L4
@Test(.timeLimit(.minutes(1))) func concurrentRetainedReaders() async throws {
 let closure = try LifecycleFixtures.escaped()
 var setup = try TopologyFixtures.ledger()
 let field = closure.definition.coefficientField, d = try TopologyFixtures.Cells(retaining:closure.definition.partition.source,using:&setup)
 let point = try d.point(field:field,coordinates:[field.integer(2,using:&setup)],using:&setup)
 let topology = TopologyFixtures.Topology(cells:TopologyFixtures.Cells.self), cap = try TopologyFixtures.limits()
 try await withThrowingTaskGroup(of:Bool.self) { group in
  for _ in 0..<8 { group.addTask {
   var admission = try TopologyFixtures.ledger()
   return try topology.contains(point,in:closure,limits:cap,using:&admission)
  } }
  for try await contained in group { try TopologyFixtures.require(contained) }
 }
}
@Test(.timeLimit(.minutes(1))) func differentialStrategiesAndPorts() throws {
 var a = try TopologyFixtures.ledger()
 let (f,d,line) = try TopologyFixtures.setup(1,&a)
 let source = try d.bind(polynomials:[d.polynomials.variable(0,using:&a)],domains:[line],using:&a)
 let partition = try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:10),using:&a)
 let cap = try TopologyFixtures.limits(), topology = TopologyFixtures.Topology(cells:TopologyFixtures.Cells.self)
 func issue<T: ExactRealClosureProducing & ExactRealTopologyQuerying & ExactRealIncidenceProducing & ExactRealComponentsProducing>(
  _ t: T, _ partition: ExactRealCellPartition<T.Base>, _ admission: inout ExactScalarLedger) throws {
  let cl = try t.closure(of:partition.cells[0],in:partition,strategy:.automatic,limits:cap,using:&admission)
  let d = try ExactRealCellDomain(retaining:partition.source,using:&admission)
  let sample = try d.sample(of:partition.cells[0],in:partition,using:&admission)
  try TopologyFixtures.require(try t.contains(sample,in:cl,limits:cap,using:&admission))
  let selection = try d.select(partition,matching:d.predicate(instructions:[.literal(true)],for:partition.source,using:&admission),using:&admission)
  let incidence = try t.incidence(of:selection,strategy:.automatic,limits:cap,using:&admission)
  try TopologyFixtures.require(try t.components(of:incidence,limits:cap,using:&admission).count == 1)
 }
 try issue(topology,partition,&a)
 for cell in partition.cells {
  let automatic = try topology.closure(of:cell,in:partition,strategy:.automatic,limits:cap,using:&a)
  let general = try topology.closure(of:cell,in:partition,strategy:.quantifiedOnly,limits:cap,using:&a)
  for value in [-1,0,1] {
   let point = try d.point(field:f,coordinates:[f.integer(value,using:&a)],using:&a)
   let expected = try topology.contains(point,in:automatic,limits:cap,using:&a)
   try TopologyFixtures.require(try topology.contains(point,in:general,limits:cap,using:&a) == expected)
  }
 }
}

@Test(.timeLimit(.minutes(1))) func closeDistinctPoints() throws { try TopologyFixtures.closeDistinctPoints() }
@Test func checkedCountOverflow() throws {
 #expect(throws: ExactRealTopologyFailure.self) { _ = try ExactTopologyAccess.add(Int.max,1) }
 #expect(throws: ExactRealTopologyFailure.self) { _ = try ExactTopologyAccess.multiply(Int.max,2) }
 #expect(throws: ExactRealTopologyFailure.self) { _ = try ExactRealTopologyLimits(maximumGeneratedCells:-1,maximumRootsPerStack:0,maximumClosures:0,maximumAttachmentPieces:0,maximumComponents:0) }
}
