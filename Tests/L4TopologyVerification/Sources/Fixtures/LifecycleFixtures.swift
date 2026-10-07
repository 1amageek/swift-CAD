import L0
import L1
import L2
import L3
import L4

public enum LifecycleFixtures {
 public typealias Field = TopologyFixtures.Field
 public typealias Cells = TopologyFixtures.Cells
 public typealias Base = TopologyFixtures.Base
 public typealias Topology = TopologyFixtures.Topology
 public static func escaped(axis: ExactScalarRootAxis = .coefficient) throws -> ExactRealClosure<Base> {
  var a = try TopologyFixtures.ledger()
  let base = try Field.base(field:Base(),maximumExtensionLevel:1,using:&a)
  let r = try ExactRealRootDomain(field:base,using:&a), p = r.polynomials
  let law = try p.polynomial(terms:[.init(powers:[2],coefficient:base.integer(1,using:&a)),.init(powers:[0],coefficient:base.integer(-2,using:&a))],using:&a)
  let line = try r.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
  let roots = try r.isolate(r.bind(law,refinementAxis:axis,using:&a),in:line,limits:.init(maximumRoots:4),using:&a)
  let extensionValue = try base.adjoin(roots.roots[1],using:&a)
  let f = extensionValue.domain, d = try Cells(field:f,variableCount:1,using:&a), q = d.polynomials
  let cut = try q.subtracting(q.variable(0,using:&a),q.constant(extensionValue.generator,using:&a),using:&a)
  let rr = try ExactRealRootDomain(field:f,using:&a)
  let source = try d.bind(polynomials:[cut],domains:[rr.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)],using:&a)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:10),using:&a)
  return try Topology(cells:Cells.self).closure(of:partition.cells[2],in:partition,strategy:.automatic,limits:TopologyFixtures.limits(),using:&a)
 }
 public static func retained() throws {
  let closure = try escaped(), topology = Topology(cells:Cells.self), cap = try TopologyFixtures.limits()
  var a = try TopologyFixtures.ledger()
  let field = closure.definition.coefficientField
  try TopologyFixtures.require(field.extensionLevel == 1 && field.maximumExtensionLevel == 1)
  let d = try Cells(retaining:closure.definition.partition.source,using:&a)
  for integer in [1,2] {
   let point = try d.point(field:field,coordinates:[field.integer(integer,using:&a)],using:&a)
   try TopologyFixtures.require(try topology.contains(point,in:closure,limits:cap,using:&a) == (integer == 2))
  }
  let rootPoint = try d.sample(of:closure.definition.partition.cells[1],in:closure.definition.partition,using:&a)
  try TopologyFixtures.require(try topology.contains(rootPoint,in:closure,limits:cap,using:&a))
  var shallow = ExactScalarLedger(limits:try .init(work:200_000_000,storageBytes:700_000_000,valueDepth:400,coefficientDepth:0))
  var rejected = false
  do { _ = try topology.contains(rootPoint,in:closure,limits:cap,using:&shallow) } catch { rejected = true }
  try TopologyFixtures.require(rejected)
  let valueClosure = try escaped(axis:.value)
  try TopologyFixtures.require(valueClosure.depth.value > 0)
  let valueDomain = try Cells(retaining:valueClosure.definition.partition.source,using:&a)
  let valuePoint = try valueDomain.sample(of:valueClosure.definition.partition.cells[1],in:valueClosure.definition.partition,using:&a)
  try TopologyFixtures.require(try topology.contains(valuePoint,in:valueClosure,limits:cap,using:&a))
  var noValueDepth = ExactScalarLedger(limits:try .init(work:200_000_000,storageBytes:700_000_000,valueDepth:0,coefficientDepth:400))
  do {
   _ = try topology.contains(valuePoint,in:valueClosure,limits:cap,using:&noValueDepth)
   throw ExactRealTopologyFailure.invalidCoverage
  } catch ExactRealTopologyFailure.scalar(.resourceLimit(.valueDepth)) { }
  print("PASS: retained algebraic field, extension policy and inherited depth")
 }
 public static func resourcesAndCancellation() throws {
  var setup = try TopologyFixtures.ledger()
  let (_,d,line) = try TopologyFixtures.setup(1,&setup), p = d.polynomials
  let source = try d.bind(polynomials:[p.variable(0,using:&setup)],domains:[line],using:&setup)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:10),using:&setup)
  let predicate = try d.predicate(instructions:[.sign(polynomial:0,relation:.notEqual)],for:source,using:&setup)
  let selection = try d.select(partition,matching:predicate,using:&setup)
  let topology = Topology(cells:Cells.self), cap = try TopologyFixtures.limits()
  var baseline = try CheckpointAdmission()
  _ = try topology.incidence(of:selection,strategy:.automatic,limits:cap,using:&baseline)
  for stop in [1,baseline.checkpoints/2,baseline.checkpoints] {
   var cancellation = try CheckpointAdmission(stop:stop), rejected = false
   do { _ = try topology.incidence(of:selection,strategy:.automatic,limits:cap,using:&cancellation) } catch { rejected = true }
   try TopologyFixtures.require(rejected && cancellation.checkpoints == stop)
  }
  var single = try TopologyFixtures.ledger()
  do {
   _ = try topology.incidence(of:selection,strategy:.automatic,limits:.init(maximumGeneratedCells:20000,maximumRootsPerStack:10,maximumClosures:1,maximumAttachmentPieces:20000,maximumComponents:100),using:&single)
   throw ExactRealTopologyFailure.invalidCoverage
  } catch ExactRealTopologyFailure.closureLimit { }
  let included = try d.select(partition,matching:d.predicate(instructions:[.literal(true)],for:source,using:&setup),using:&setup)
  var noPiece = try TopologyFixtures.ledger()
  do {
   _ = try topology.incidence(of:included,strategy:.automatic,limits:.init(maximumGeneratedCells:20000,maximumRootsPerStack:10,maximumClosures:10,maximumAttachmentPieces:0,maximumComponents:100),using:&noPiece)
   throw ExactRealTopologyFailure.invalidCoverage
  } catch ExactRealTopologyFailure.attachmentLimit { }
  var rootLimit = try TopologyFixtures.ledger()
  do {
   _ = try topology.closure(of:partition.cells[2],in:partition,strategy:.quantifiedOnly,
    limits:.init(maximumGeneratedCells:20000,maximumRootsPerStack:0,maximumClosures:10,maximumAttachmentPieces:0,maximumComponents:0),using:&rootLimit)
   throw ExactRealTopologyFailure.invalidCoverage
  } catch ExactRealTopologyFailure.cell(.root(.resultLimit)) { }
  let r = try ExactRealRootDomain(field:try d.coefficientField(of:source,using:&setup),using:&setup)
  let field = try d.coefficientField(of:source,using:&setup)
  let box = try r.domain(lower:.finite(field.integer(0,using:&setup)),upper:.finite(field.integer(1,using:&setup)),includesLower:false,includesUpper:false,using:&setup)
  let open = try d.bind(polynomials:[],domains:[box],using:&setup)
  let openPartition = try d.decompose(open,limits:.init(maximumStoredCells:100,maximumRootsPerStack:10),using:&setup)
  var generatedLimit = try TopologyFixtures.ledger()
  do {
   _ = try topology.closure(of:openPartition.cells[0],in:openPartition,strategy:.automatic,
    limits:.init(maximumGeneratedCells:0,maximumRootsPerStack:10,maximumClosures:1,maximumAttachmentPieces:0,maximumComponents:0),using:&generatedLimit)
   throw ExactRealTopologyFailure.invalidCoverage
  } catch ExactRealTopologyFailure.generatedCellLimit { }
  let incidence = try topology.incidence(of:selection,strategy:.automatic,limits:cap,using:&setup)
  var noComponent = try TopologyFixtures.ledger()
  do {
   _ = try topology.components(of:incidence,limits:.init(maximumGeneratedCells:0,maximumRootsPerStack:0,maximumClosures:0,maximumAttachmentPieces:0,maximumComponents:1),using:&noComponent)
   throw ExactRealTopologyFailure.invalidCoverage
  } catch ExactRealTopologyFailure.componentLimit { }
  let empty = try d.select(partition,matching:d.predicate(instructions:[.literal(false)],for:source,using:&setup),using:&setup)
  let zero = try ExactRealTopologyLimits(maximumGeneratedCells:0,maximumRootsPerStack:0,maximumClosures:0,maximumAttachmentPieces:0,maximumComponents:0)
  let emptyIncidence = try topology.incidence(of:empty,strategy:.automatic,limits:zero,using:&setup)
  try TopologyFixtures.require(try topology.components(of:emptyIncidence,limits:zero,using:&setup).count == 0)
  // A fresh call remains usable after all failed operations.
  try TopologyFixtures.require(try topology.components(of:incidence,limits:cap,using:&setup).count == 2)
  print("PASS: cumulative counts, mid/terminal cancellation, empty selection and recovery")
 }
}
