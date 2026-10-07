import L0
import L1
import L2
import L3

public enum QueryFixtures {
 typealias F=CellFixtures.Field
 typealias D=CellFixtures.Domain
 static func verifySamples(_ d: D, _ partition: ExactRealCellPartition<ExactRationalScalarDomain>, _ a: inout ExactScalarLedger) throws {
  for cell in partition.cells {
   let sample=try d.sample(of:cell,in:partition,using:&a)
   try CellFixtures.require(try d.locate(sample,in:partition,limits:.init(maximumRoots:100),using:&a) == cell)
   let condition=try d.condition(of:cell,in:partition,using:&a)
   try CellFixtures.require(try d.contains(sample,in:condition,limits:.init(maximumRoots:100),using:&a))
   try CellFixtures.require(cell.projectionSigns.count == cell.projectionLaws.count)
  }
 }
 public static func selectionAndLocation() throws {
  var a=try CellFixtures.ledger()
  let (f,d,all)=try CellFixtures.setup(1,&a),p=d.polynomials,x=try p.variable(0,using:&a)
  let law=try p.subtracting(p.multiplying(x,x,using:&a),p.constant(f.integer(1,using:&a),using:&a),using:&a)
  let source=try d.bind(polynomials:[law,law],domains:[all],using:&a)
  let part=try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:30),using:&a)
  try verifySamples(d,part,&a)
  let pred=try d.predicate(instructions:[.sign(polynomial:0,relation:.greater),.sign(polynomial:1,relation:.equal),.not,.and],for:source,using:&a)
  let selection=try d.select(part,matching:pred,using:&a)
  try CellFixtures.require(selection.cells.count == 2)
  var ids: [ExactRealCellID<ExactRationalScalarDomain>] = []
  for value in [-3,-2,2,3] {
   let point=try d.point(field:f,coordinates:[f.integer(value,using:&a)],using:&a)
   guard let id=try d.locate(point,in:part,limits:.init(maximumRoots:30),using:&a) else { throw ExactRealCellFailure.invalidCoverage }
   ids.append(id)
  }
  try CellFixtures.require(ids[0] == ids[1] && ids[2] == ids[3] && ids[0] != ids[2])
  let origin=part.cells.first!.parent!
  try CellFixtures.require(try d.sample(of:origin,in:part,using:&a).coordinates.isEmpty)
  let prefix=try d.condition(of:origin,in:part,using:&a)
  let arbitrary=try d.point(field:f,coordinates:[f.integer(11,using:&a)],using:&a)
  try CellFixtures.require(prefix.branches.isEmpty && (try d.contains(arbitrary,in:prefix,limits:.init(maximumRoots:30),using:&a)))
  let second=try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:30),using:&a)
  do { _ = try d.sample(of:part.cells.first!,in:second,using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.invalidCell { }
  let newSource=try d.bind(polynomials:[law,law],domains:[all],using:&a)
  let foreign=try d.predicate(instructions:[.literal(true)],for:newSource,using:&a)
  do { _ = try d.select(part,matching:foreign,using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.incompatibleDomain { }
  let empty=try d.select(part,matching:d.predicate(instructions:[.literal(false)],for:source,using:&a),using:&a)
  try CellFixtures.require(empty.cells.isEmpty && empty.partition.cells.count == part.cells.count)
 }
 public static func nullifiedQuery() throws {
  var a=try CellFixtures.ledger()
  let (f,d,all)=try CellFixtures.setup(3,&a),p=d.polynomials
  let x=try p.variable(0,using:&a),y=try p.variable(1,using:&a),z=try p.variable(2,using:&a)
  let s=try d.bind(polynomials:[p.adding(p.multiplying(x,z,using:&a),y,using:&a)],domains:[all,all,all],using:&a)
  let part=try d.decompose(s,limits:.init(maximumStoredCells:200,maximumRootsPerStack:30),using:&a)
  let first=try d.point(field:f,coordinates:[f.integer(0,using:&a),f.integer(0,using:&a),f.integer(7,using:&a)],using:&a)
  let second=try d.point(field:f,coordinates:[f.integer(0,using:&a),f.integer(0,using:&a),f.integer(-9,using:&a)],using:&a)
  guard let cell=try d.locate(first,in:part,limits:.init(maximumRoots:30),using:&a) else { throw ExactRealCellFailure.invalidCoverage }
  try CellFixtures.require(cell.dimension == 1 && cell.signs == [.zero])
  let condition=try d.condition(of:cell,in:part,using:&a)
  try CellFixtures.require(try d.contains(second,in:condition,limits:.init(maximumRoots:30),using:&a))
 }
 public static func algebraicQueries() throws {
  var a=try CellFixtures.ledger()
  let (f,d,all)=try CellFixtures.setup(2,&a),p=d.polynomials,x=try p.variable(0,using:&a),y=try p.variable(1,using:&a)
  let source=try d.bind(polynomials:[p.subtracting(p.multiplying(x,x,using:&a),p.constant(f.integer(2,using:&a),using:&a),using:&a),p.subtracting(y,x,using:&a)],domains:[all,all],using:&a)
  let part=try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:30),using:&a)
  var exact: [ExactRealCellSample<ExactRationalScalarDomain>] = []
  for cell in part.cells where cell.signs == [.zero,.zero] {
   let sample=try d.sample(of:cell,in:part,using:&a)
   try CellFixtures.require(try d.locate(sample,in:part,limits:.init(maximumRoots:30),using:&a) == cell)
   exact.append(sample)
  }
  try CellFixtures.require(exact.count == 2 && exact[0].field.extensionLevel == 1)
  do { _ = try d.point(field:exact[0].field,coordinates:exact[1].coordinates,using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.scalar(.incompatibleDomain) { }
  let point=try d.point(field:exact[0].field,coordinates:[exact[0].field.importing(f.integer(0,using:&a),using:&a),exact[0].field.importing(f.integer(0,using:&a),using:&a)],using:&a)
  try CellFixtures.require(try d.locate(point,in:part,limits:.init(maximumRoots:30),using:&a) != nil)
  // Ancestor-owned exact bounds are explicitly embedded into a descendant source field.
  let ancestorRoots=try ExactRealRootDomain(field:f,using:&a)
  let ancestorBox=try ancestorRoots.domain(lower:.finite(f.integer(0,using:&a)),upper:.finite(f.integer(1,using:&a)),using:&a)
  let boundedDomain=try D(field:exact[0].field,variableCount:1,using:&a)
  let boundedSource=try boundedDomain.bind(polynomials:[],domains:[ancestorBox],using:&a)
  let boundedPart=try boundedDomain.decompose(boundedSource,limits:.init(maximumStoredCells:10,maximumRootsPerStack:10),using:&a)
  try CellFixtures.require(boundedPart.cells.count == 3)
  try verifySamples(boundedDomain,boundedPart,&a)
  // Construct a source whose authored coefficient is already algebraic.
  let af=exact[1].field, ad=try D(field:af,variableCount:1,using:&a),ap=ad.polynomials
  let ar=try ExactRealRootDomain(field:af,using:&a),box=try ar.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
  let s=try ad.bind(polynomials:[ap.subtracting(ap.variable(0,using:&a),ap.constant(exact[1].coordinates[0],using:&a),using:&a)],domains:[box],using:&a)
  let result=try ad.decompose(s,limits:.init(maximumStoredCells:30,maximumRootsPerStack:10),using:&a)
  try verifySamples(ad,result,&a)
  try CellFixtures.require(result.cells.contains { $0.signs == [.zero] })
 }
 public static func applicationRelations() throws {
  for variant in 0..<5 {
   var a=try CellFixtures.ledger()
   let count=variant < 3 ? 3:4
   let (f,d,all)=try CellFixtures.setup(count,&a),p=d.polynomials
   let t=try p.variable(0,using:&a),u=try p.variable(1,using:&a),v=try p.variable(2,using:&a)
   var laws: [CellFixtures.Polynomial] = []
   if variant == 0 { laws=[try p.subtracting(t,u,using:&a),v,try p.multiplying(t,t,using:&a)] }
   if variant == 1 { laws=[try p.subtracting(t,u,using:&a),v,try p.zero(using:&a)] }
   if variant == 2 { laws=[t,try p.subtracting(p.multiplying(u,u,using:&a),p.constant(f.integer(1,using:&a),using:&a),using:&a),v] }
   if variant >= 3 {
    let w=try p.variable(3,using:&a)
    laws=[try p.subtracting(t,v,using:&a),try p.subtracting(u,w,using:&a),variant == 3 ? u : try p.zero(using:&a)]
   }
   let source=try d.bind(polynomials:laws,domains:Array(repeating:all,count:count),using:&a)
   let part=try d.decompose(source,limits:.init(maximumStoredCells:400,maximumRootsPerStack:50),using:&a)
   let pred=try d.predicate(instructions:[.sign(polynomial:0,relation:.equal),.sign(polynomial:1,relation:.equal),.and,.sign(polynomial:2,relation:.equal),.and],for:source,using:&a)
   let cells=try d.select(part,matching:pred,using:&a).cells
   if variant == 0 { try CellFixtures.require(cells.count == 1 && cells.first!.dimension == 0) }
   if variant == 1 || variant == 3 { try CellFixtures.require(cells.contains { $0.dimension == 1 }) }
   if variant == 2 { try CellFixtures.require(cells.count == 2 && cells.allSatisfy { $0.dimension == 0 }) }
   if variant == 4 { try CellFixtures.require(cells.contains { $0.dimension == 2 }) }
   for cell in cells {
    let sample=try d.sample(of:cell,in:part,using:&a)
    try CellFixtures.require(try d.locate(sample,in:part,limits:.init(maximumRoots:50),using:&a) == cell)
   }
  }
  var a=try CellFixtures.ledger()
  let (_,d,all)=try CellFixtures.setup(6,&a)
  let source=try d.bind(polynomials:[],domains:Array(repeating:all,count:6),using:&a)
  let part=try d.decompose(source,limits:.init(maximumStoredCells:7,maximumRootsPerStack:0),using:&a)
  try CellFixtures.require(part.cells.count == 1 && part.cells.first!.dimension == 6)
  try verifySamples(d,part,&a)
 }
 public static func retainedAndOutside() throws {
  var a=try CellFixtures.ledger()
  let (f,d,_)=try CellFixtures.setup(1,&a),r=try ExactRealRootDomain(field:f,using:&a)
  let box=try r.domain(lower:.finite(f.integer(0,using:&a)),upper:.finite(f.integer(1,using:&a)),includesLower:false,includesUpper:true,using:&a)
  let source=try d.bind(polynomials:[],domains:[box],using:&a)
  let part=try d.decompose(source,limits:.init(maximumStoredCells:20,maximumRootsPerStack:10),using:&a)
  try verifySamples(d,part,&a)
  for value in [-1,0,2] {
   let point=try d.point(field:f,coordinates:[f.integer(value,using:&a)],using:&a)
   try CellFixtures.require(try d.locate(point,in:part,limits:.init(maximumRoots:0),using:&a) == nil)
  }
  let retained=try D(retaining:part.source,using:&a)
  let condition=try retained.condition(of:part.cells.first!,in:part,using:&a)
  let sample=try retained.sample(of:condition.cell,in:part,using:&a)
  try CellFixtures.require(try retained.contains(sample,in:condition,limits:.init(maximumRoots:10),using:&a))
  let unrelated=try F.base(field:CellFixtures.Base(),maximumExtensionLevel:3,using:&a)
  do { _ = try retained.point(field:unrelated,coordinates:[unrelated.integer(0,using:&a)],using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.scalar(.incompatibleDomain) { }
 }
}
