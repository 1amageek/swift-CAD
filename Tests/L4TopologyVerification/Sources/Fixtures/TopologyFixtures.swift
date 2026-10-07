import L0
import L1
import L2
import L3
import L4

public enum TopologyFixtures {
 public typealias Base = ExactRationalScalarDomain
 public typealias Field = ExactAlgebraicScalarDomain<Base>
 public typealias Cells = ExactRealCellDomain<Base>
 public typealias Topology = ExactRealTopology<Base>
 public static func ledger() throws -> ExactScalarLedger { .init(limits:try .init(work:200_000_000,storageBytes:700_000_000,valueDepth:400,coefficientDepth:400)) }
 public static func limits() throws -> ExactRealTopologyLimits { try .init(maximumGeneratedCells:20000,maximumRootsPerStack:100,maximumClosures:1000,maximumAttachmentPieces:20000,maximumComponents:1000) }
 public static func require(_ condition: Bool) throws { if !condition { throw ExactRealTopologyFailure.invalidCoverage } }
 public static func setup(_ n: Int, _ a: inout ExactScalarLedger) throws -> (Field,Cells,ExactRealRootInterval<Field.Value>) {
  let f = try Field.base(field:Base(),maximumExtensionLevel:10,using:&a)
  let d = try Cells(field:f,variableCount:n,using:&a)
  let r = try ExactRealRootDomain(field:f,using:&a)
  return (f,d,try r.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a))
 }
 public static func affineClosures() throws {
  var a = try ledger()
  let (f,d,line) = try setup(1,&a)
  let source = try d.bind(polynomials:[d.polynomials.variable(0,using:&a)],domains:[line],using:&a)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:20),using:&a)
  let topology = Topology(cells:Cells.self), cap = try limits()
  for (index,cell) in partition.cells.enumerated() {
   let closure = try topology.closure(of:cell,in:partition,strategy:.automatic,limits:cap,using:&a)
   for value in [-2,0,2] {
    let point = try d.point(field:f,coordinates:[f.integer(value,using:&a)],using:&a)
    let expected = index == 0 ? value <= 0 : index == 1 ? value == 0 : value >= 0
    try require(try topology.contains(point,in:closure,limits:cap,using:&a) == expected)
   }
  }
  let r = try ExactRealRootDomain(field:f,using:&a)
  let box = try r.domain(lower:.finite(f.integer(0,using:&a)),upper:.finite(f.integer(1,using:&a)),includesLower:false,includesUpper:false,using:&a)
  let bounded = try d.bind(polynomials:[],domains:[box],using:&a)
  let bp = try d.decompose(bounded,limits:.init(maximumStoredCells:100,maximumRootsPerStack:20),using:&a)
  let closed = try topology.closure(of:bp.cells[0],in:bp,strategy:.automatic,limits:cap,using:&a)
  for value in [-1,0,1,2] {
   let point = try d.point(field:f,coordinates:[f.integer(value,using:&a)],using:&a)
   try require(try topology.contains(point,in:closed,limits:cap,using:&a) == (value == 0 || value == 1))
  }
  print("PASS: affine ambient closures work=\(a.work) storage=\(a.storageBytes)")
 }
 public static func quantifiedClosure() throws {
  var a = try ledger()
  let (f,d,line) = try setup(1,&a)
  let source = try d.bind(polynomials:[d.polynomials.variable(0,using:&a)],domains:[line],using:&a)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:20),using:&a)
  let topology = Topology(cells:Cells.self), cap = try limits()
  let closure = try topology.closure(of:partition.cells[2],in:partition,strategy:.quantifiedOnly,limits:cap,using:&a)
  for value in [-1,0,1] {
   let point = try d.point(field:f,coordinates:[f.integer(value,using:&a)],using:&a)
   try require(try topology.contains(point,in:closure,limits:cap,using:&a) == (value >= 0))
  }
  print("PASS: quantified closure work=\(a.work) storage=\(a.storageBytes)")
 }
 public static func graphClosure() throws {
  var a = try ledger()
  let (f,d,line) = try setup(2,&a), p = d.polynomials
  let x = try p.variable(0,using:&a), y = try p.variable(1,using:&a)
  let source = try d.bind(polynomials:[p.subtracting(p.multiplying(y,y,using:&a),x,using:&a)],domains:[line,line],using:&a)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:200,maximumRootsPerStack:20),using:&a)
  let cell = partition.cells.first { $0.signs == [.zero] && $0.dimension == 1 && $0.projectionSigns.last == .positive }!
  let topology = Topology(cells:Cells.self), cap = try limits()
  let closure = try topology.closure(of:cell,in:partition,strategy:.automatic,limits:cap,using:&a)
  guard case .boundedSectionGraph = closure.proof else { throw ExactRealTopologyFailure.invalidCoverage }
  for coordinates in [[0,0],[4,2],[4,-2],[-1,0]] {
   let values = try coordinates.map { try f.integer($0,using:&a) }
   let point = try d.point(field:f,coordinates:values,using:&a)
   let expected = coordinates == [0,0] || coordinates == [4,2]
   try require(try topology.contains(point,in:closure,limits:cap,using:&a) == expected)
  }
  print("PASS: bounded section graph work=\(a.work) storage=\(a.storageBytes)")
 }
 public static func zeroAndFailures() throws {
  var setup = try ledger()
  let (f,d,_) = try self.setup(0,&setup)
  let source = try d.bind(polynomials:[],domains:[],using:&setup)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:1,maximumRootsPerStack:0),using:&setup)
  let topology = Topology(cells:Cells.self), cap = try limits()
  var baseline = try ledger()
  let closure = try topology.closure(of:partition.cells[0],in:partition,strategy:.automatic,limits:cap,using:&baseline)
  let point = try d.point(field:f,coordinates:[],using:&setup)
  try require(try topology.contains(point,in:closure,limits:cap,using:&setup))
  let work = baseline.work, storage = baseline.storageBytes, value = baseline.valueDepth, coefficient = baseline.coefficientDepth
  var exact = ExactScalarLedger(limits:try .init(work:work,storageBytes:storage,valueDepth:value,coefficientDepth:coefficient))
  _ = try topology.closure(of:partition.cells[0],in:partition,strategy:.automatic,limits:cap,using:&exact)
  for axis in 0..<4 {
   var failed = false
   var limited = ExactScalarLedger(limits:try .init(work:axis == 0 ? work-1:work,storageBytes:axis == 1 ? storage-1:storage,
    valueDepth:axis == 2 ? max(0,value-1):value,coefficientDepth:axis == 3 ? max(0,coefficient-1):coefficient))
   if (axis == 2 && value == 0) || (axis == 3 && coefficient == 0) { continue }
   do { _ = try topology.closure(of:partition.cells[0],in:partition,strategy:.automatic,limits:cap,using:&limited) } catch { failed = true }
   try require(failed)
  }
  for generated in [0,1] {
   var a = try ledger()
   let small = try ExactRealTopologyLimits(maximumGeneratedCells:generated,maximumRootsPerStack:0,maximumClosures:1,maximumAttachmentPieces:0,maximumComponents:0)
   do {
    _ = try topology.closure(of:partition.cells[0],in:partition,strategy:.automatic,limits:small,using:&a)
    try require(generated >= 0)
   } catch { throw error }
  }
  var zero = try ledger()
  do {
   _ = try topology.closure(of:partition.cells[0],in:partition,strategy:.automatic,
    limits:.init(maximumGeneratedCells:100,maximumRootsPerStack:10,maximumClosures:0,maximumAttachmentPieces:0,maximumComponents:0),using:&zero)
   throw ExactRealTopologyFailure.invalidCoverage
  } catch ExactRealTopologyFailure.closureLimit { }
  var cancelled = try ledger(); cancelled.cancel()
  do { _ = try topology.closure(of:partition.cells[0],in:partition,strategy:.automatic,limits:cap,using:&cancelled); throw ExactRealTopologyFailure.invalidCoverage } catch ExactRealTopologyFailure.scalar(.cancelled) { }
  print("PASS: zero-arity closure and exact admission boundaries")
 }
 public static func connectivity() throws {
  let topology = Topology(cells:Cells.self), cap = try limits()
  for test in 0..<3 {
   var a = try ledger()
   let (_,d,line) = try setup(test == 0 ? 1:2,&a), p = d.polynomials
   let x = try p.variable(0,using:&a)
   let laws: [ExactPolynomial<Field>], program: [ExactRealCellInstruction]
   if test == 0 { laws = [x]; program = [.sign(polynomial:0,relation:.notEqual)] }
   else {
    let y = try p.variable(1,using:&a)
    laws = [try p.multiplying(x,y,using:&a),x,y]
    program = test == 1 ? [.sign(polynomial:0,relation:.equal)] :
     [.sign(polynomial:0,relation:.equal),.sign(polynomial:1,relation:.notEqual),.sign(polynomial:2,relation:.notEqual),.or,.and]
   }
   let source = try d.bind(polynomials:laws,domains:Array(repeating:line,count: d.polynomials.variableCount),using:&a)
   let partition = try d.decompose(source,limits:.init(maximumStoredCells:200,maximumRootsPerStack:20),using:&a)
   let selection = try d.select(partition,matching:d.predicate(instructions:program,for:source,using:&a),using:&a)
   let incidence = try topology.incidence(of:selection,strategy:.automatic,limits:cap,using:&a)
   let components = try topology.components(of:incidence,limits:cap,using:&a)
   try require(components.count == [2,1,4][test])
   try require(components.members.count == selection.cells.count && incidence.pairs.count == selection.cells.count*selection.cells.count)
   try require(components.witnesses.count == incidence.attachments.count)
   print("PASS: connectivity case=\(test) components=\(components.count) work=\(a.work) storage=\(a.storageBytes)")
  }
 }
 public static func partialTarget() throws {
  var a = try ledger()
  let (f,d,line) = try setup(3,&a), p = d.polynomials
  let x = try p.variable(0,using:&a), y = try p.variable(1,using:&a), z = try p.variable(2,using:&a)
  let equation = try p.subtracting(p.multiplying(x,z,using:&a),y,using:&a)
  let source = try d.bind(polynomials:[equation,x,p.subtracting(x,p.constant(f.integer(1,using:&a),using:&a),using:&a),y,p.subtracting(x,y,using:&a)],domains:[line,line,line],using:&a)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:1000,maximumRootsPerStack:40),using:&a)
  let cell = partition.cells.first { $0.signs == [.zero,.positive,.negative,.positive,.positive] }!
  let topology = Topology(cells:Cells.self), cap = try limits()
  let closure = try topology.closure(of:cell,in:partition,strategy:.automatic,limits:cap,using:&a)
  guard case .polynomialGraph = closure.proof else { throw ExactRealTopologyFailure.invalidCoverage }
  for value in [-1,0,1,2] {
   let point = try d.point(field:f,coordinates:[f.integer(0,using:&a),f.integer(0,using:&a),f.integer(value,using:&a)],using:&a)
   try require(try topology.contains(point,in:closure,limits:cap,using:&a) == (value == 0 || value == 1))
  }
  print("PASS: partial nullified target work=\(a.work) storage=\(a.storageBytes)")
 }

 public static func singularComponents() throws {
  let topology = Topology(cells:Cells.self), cap = try limits()
  for test in 0..<4 {
   var a = try ledger()
   let (f,d,line) = try setup(2,&a), p = d.polynomials
   let x = try p.variable(0,using:&a), y = try p.variable(1,using:&a)
   let xx = try p.multiplying(x,x,using:&a), yy = try p.multiplying(y,y,using:&a)
   let law: ExactPolynomial<Field>
   switch test {
   case 0: law = try p.subtracting(yy,p.multiplying(xx,x,using:&a),using:&a)
   case 1: law = try p.multiplying(y,p.subtracting(y,xx,using:&a),using:&a)
   case 2: let delta = try p.subtracting(x,y,using:&a); law = try p.multiplying(delta,delta,using:&a)
   default:
    let delta = try p.subtracting(x,p.constant(f.integer(1,using:&a),using:&a),using:&a)
    law = try p.multiplying(x,p.adding(p.multiplying(delta,delta,using:&a),yy,using:&a),using:&a)
   }
   let source = try d.bind(polynomials:[law],domains:[line,line],using:&a)
   let partition = try d.decompose(source,limits:.init(maximumStoredCells:1000,maximumRootsPerStack:100),using:&a)
   let predicate = try d.predicate(instructions:[.sign(polynomial:0,relation:.equal)],for:source,using:&a)
   let selection = try d.select(partition,matching:predicate,using:&a)
   let incidence = try topology.incidence(of:selection,strategy:.automatic,limits:cap,using:&a)
   let components = try topology.components(of:incidence,limits:cap,using:&a)
   try require(components.count == (test == 3 ? 2:1))
   print("PASS: singular case=\(test) components=\(components.count) work=\(a.work) storage=\(a.storageBytes)")
  }
 }
 public static func partialIncidence() throws {
  var a = try ledger()
  let (f,d,line) = try setup(3,&a), p = d.polynomials
  let x = try p.variable(0,using:&a), y = try p.variable(1,using:&a), z = try p.variable(2,using:&a)
  let equation = try p.subtracting(p.multiplying(x,z,using:&a),y,using:&a)
  let source = try d.bind(polynomials:[equation,x,p.subtracting(x,p.constant(f.integer(1,using:&a),using:&a),using:&a),y,p.subtracting(x,y,using:&a)],domains:[line,line,line],using:&a)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:1000,maximumRootsPerStack:40),using:&a)
  let c = partition.cells.first { $0.signs == [.zero,.positive,.negative,.positive,.positive] }!
  let target = partition.cells.first { $0.signs == [.zero,.zero,.negative,.zero,.zero] }!
  let program: [ExactRealCellInstruction] = [
   .sign(polynomial:0,relation:.equal),.sign(polynomial:1,relation:.greater),.and,
   .sign(polynomial:2,relation:.less),.and,.sign(polynomial:3,relation:.greater),.and,.sign(polynomial:4,relation:.greater),.and,
   .sign(polynomial:1,relation:.equal),.sign(polynomial:3,relation:.equal),.and,.or]
  let selection = try d.select(partition,matching:d.predicate(instructions:program,for:source,using:&a),using:&a)
  try require(selection.cells.count == 2)
  let topology = Topology(cells:Cells.self), cap = try limits()
  let incidence = try topology.incidence(of:selection,strategy:.automatic,limits:cap,using:&a)
  let pair = incidence.pairs.first { $0.source == c && $0.target == target }!
  let reverse = incidence.pairs.first { $0.source == target && $0.target == c }!
  try require(pair.attachments.count == 3 && reverse.attachments.isEmpty)
  let region = pair.region!, retained = try Cells(retaining:region.partition.source,using:&a)
  for value in [-1,0,1,2] {
   let point = try d.point(field:f,coordinates:[f.integer(0,using:&a),f.integer(0,using:&a),f.integer(value,using:&a)],using:&a)
   let cell = try retained.locatePrefix(point,in:region.partition,limits:.init(maximumRoots:40),using:&a)!
   let i = region.cells.firstIndex(of:cell)!
   try require(region.included[i] == (value == 0 || value == 1))
  }
  try require(try topology.components(of:incidence,limits:cap,using:&a).count == 1)
  print("PASS: partial directed incidence pieces=3 work=\(a.work) storage=\(a.storageBytes)")
 }
 public static func folded() throws {
  var a = try ledger()
  let (f,d,_) = try setup(4,&a), p = d.polynomials
  let x0 = try p.variable(0,using:&a), x1 = try p.variable(1,using:&a), x2 = try p.variable(2,using:&a), x3 = try p.variable(3,using:&a)
  let r = try ExactRealRootDomain(field:f,using:&a)
  let box = try r.domain(lower:.finite(f.integer(-1,using:&a)),upper:.finite(f.integer(1,using:&a)),using:&a)
  let source = try d.bind(polynomials:[p.subtracting(p.multiplying(x0,x0,using:&a),p.multiplying(x2,x2,using:&a),using:&a),p.subtracting(x1,x3,using:&a)],domains:[box,box,box,box],using:&a)
  print("PHASE: folded source bound work=\(a.work) storage=\(a.storageBytes)")
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:2000,maximumRootsPerStack:40),using:&a)
  print("PHASE: folded partition work=\(a.work) storage=\(a.storageBytes) cells=\(partition.cells.count)")
  let selection = try d.select(partition,matching:d.predicate(instructions:[.sign(polynomial:0,relation:.equal),.sign(polynomial:1,relation:.equal),.and],for:source,using:&a),using:&a)
  let topology = Topology(cells:Cells.self), cap = try limits()
  var positive = false, negative = false, meeting = false
  print("PHASE: folded selected cells=\(selection.cells.count)")
  for cell in selection.cells {
   var caller = try ledger()
   let sample = try d.sample(of:cell,in:partition,using:&caller)
   let sx = try sample.field.sign(of:sample.coordinates[0],using:&caller)
   let sz = try sample.field.sign(of:sample.coordinates[2],using:&caller)
   if sx == .positive && sz == .positive { positive = true }
   if sx == .positive && sz == .negative { negative = true }
   if sx == .zero && sz == .zero { meeting = true }
   let closure = try topology.closure(of:cell,in:partition,strategy:.automatic,limits:cap,using:&caller)
   try require(try topology.contains(sample,in:closure,limits:cap,using:&caller))
   print("PHASE: folded closure proof=\(closure.proof) work=\(caller.work) storage=\(caller.storageBytes)")
  }
  try require(positive && negative && meeting)
  print("PHASE: folded incidence start")
  let incidence = try topology.incidence(of:selection,strategy:.automatic,limits:cap,using:&a)
  let components = try topology.components(of:incidence,limits:cap,using:&a)
  try require(components.count == 1 && components.members.count == selection.cells.count)
  print("PASS: folded sheets members=\(selection.cells.count) pieces=\(incidence.attachments.count) work=\(a.work) storage=\(a.storageBytes)")
 }

 public static func closeDistinctPoints() throws {
  var a = try ledger()
  let (f,d,line) = try setup(1,&a), p = d.polynomials
  let x = try p.variable(0,using:&a), one = try f.integer(1,using:&a)
  let near = try f.adding(one,f.dividing(one,f.integer(1000000,using:&a),using:&a),using:&a)
  let law = try p.multiplying(p.subtracting(x,p.constant(one,using:&a),using:&a),p.subtracting(x,p.constant(near,using:&a),using:&a),using:&a)
  let source = try d.bind(polynomials:[law],domains:[line],using:&a)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:10),using:&a)
  let selection = try d.select(partition,matching:d.predicate(instructions:[.sign(polynomial:0,relation:.equal)],for:source,using:&a),using:&a)
  let topology = Topology(cells:Cells.self), cap = try limits()
  let incidence = try topology.incidence(of:selection,strategy:.automatic,limits:cap,using:&a)
  let components = try topology.components(of:incidence,limits:cap,using:&a)
  try require(selection.cells.count == 2 && components.count == 2 && incidence.attachments.isEmpty)
  print("PASS: close distinct exact points remain separate")
 }

}
