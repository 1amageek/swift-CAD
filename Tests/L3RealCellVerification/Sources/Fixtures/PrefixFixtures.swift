import L0
import L1
import L2
import L3

public enum PrefixFixtures {
 private typealias Field=CellFixtures.Field
 private typealias Domain=CellFixtures.Domain
 private typealias Partition=ExactRealCellPartition<CellFixtures.Base>
 private typealias Cell=ExactRealCellID<CellFixtures.Base>

 private static func location(_ coordinates:[Int],field:Field,domain:Domain,partition:Partition,
  _ a:inout ExactScalarLedger) throws -> Cell {
  var values:[Field.Value]=[]
  for value in coordinates { values.append(try field.integer(value,using:&a)) }
  let point=try domain.point(field:field,coordinates:values,using:&a)
  guard let cell=try domain.locate(point,in:partition,limits:.init(maximumRoots:100),using:&a) else {
   throw ExactRealCellFailure.invalidCoverage
  }
  let condition=try domain.condition(of:cell,in:partition,using:&a)
  try CellFixtures.require(try domain.contains(point,in:condition,limits:.init(maximumRoots:100),using:&a))
  for count in 0...coordinates.count {
   let prefix=try domain.prefixPoint(field:field,coordinates:Array(values.prefix(count)),using:&a)
   guard let located=try domain.locatePrefix(prefix,in:partition,limits:.init(maximumRoots:100),using:&a) else {
    throw ExactRealCellFailure.invalidCoverage
   }
   var ancestor=cell
   for _ in count..<coordinates.count {
    guard let parent=ancestor.parent else { throw ExactRealCellFailure.invalidCoverage }; ancestor=parent
   }
   try CellFixtures.require(located == ancestor)
   let condition=try domain.condition(of:ancestor,in:partition,using:&a)
   try CellFixtures.require(condition.branches.count == count)
   try CellFixtures.require(try domain.contains(prefix,in:condition,limits:.init(maximumRoots:100),using:&a))
   try CellFixtures.require(try domain.contains(point,in:condition,limits:.init(maximumRoots:100),using:&a))
  }
  return cell
 }

 private static func movingBranches() throws {
  for variant in 0..<3 {
   var a=try CellFixtures.ledger()
   let (field,domain,all)=try CellFixtures.setup(2,&a),p=domain.polynomials
   let x=try p.variable(0,using:&a),y=try p.variable(1,using:&a),square=try p.multiplying(x,x,using:&a)
   let laws:[CellFixtures.Polynomial]
   if variant == 0 { laws=[try p.subtracting(y,square,using:&a)] }
   else if variant == 1 { laws=[try p.subtracting(y,x,using:&a),try p.adding(y,x,using:&a)] }
   else { laws=[try p.subtracting(p.multiplying(y,y,using:&a),p.multiplying(square,x,using:&a),using:&a)] }
   let source=try domain.bind(polynomials:laws,domains:[all,all],using:&a)
   let partition=try domain.decompose(source,limits:.init(maximumStoredCells:300,maximumRootsPerStack:50),using:&a)
   let first=try location(variant == 2 ? [4,8]:[1,1],field:field,domain:domain,partition:partition,&a)
   let second=try location(variant == 0 ? [2,4] : variant == 1 ? [2,2]:[9,27],
    field:field,domain:domain,partition:partition,&a)
   try CellFixtures.require(first == second && first.signs.first == .zero)
   if variant == 0 {
    let above=try location([2,5],field:field,domain:domain,partition:partition,&a)
    try CellFixtures.require(above != first && above.signs == [.positive])
   } else {
    let lower=try location(variant == 1 ? [1,-1]:[4,-8],field:field,domain:domain,partition:partition,&a)
    let next=try location(variant == 1 ? [2,-2]:[9,-27],field:field,domain:domain,partition:partition,&a)
    try CellFixtures.require(lower == next && lower != first)
    try CellFixtures.require(lower.signs == (variant == 1 ? [.negative,.zero]:[.zero]))
    let origin=try location([0,0],field:field,domain:domain,partition:partition,&a)
    try CellFixtures.require(origin.dimension == 0 && origin.signs.allSatisfy { $0 == .zero })
   }
  }
 }

 private static func nullificationAndLengths() throws {
  var a=try CellFixtures.ledger()
  let (field,domain,all)=try CellFixtures.setup(3,&a),p=domain.polynomials
  let x=try p.variable(0,using:&a),y=try p.variable(1,using:&a),z=try p.variable(2,using:&a)
  let source=try domain.bind(polynomials:[p.adding(p.multiplying(x,z,using:&a),y,using:&a)],
   domains:[all,all,all],using:&a)
  let partition=try domain.decompose(source,limits:.init(maximumStoredCells:300,maximumRootsPerStack:50),using:&a)
  let first=try location([0,0,7],field:field,domain:domain,partition:partition,&a)
  let next=try location([0,0,-9],field:field,domain:domain,partition:partition,&a)
  try CellFixtures.require(first == next && first.dimension == 1 && first.signs == [.zero])
  guard let secondPrefix=first.parent,let firstPrefix=secondPrefix.parent else { throw ExactRealCellFailure.invalidCoverage }
  let condition=try domain.condition(of:firstPrefix,in:partition,using:&a)
  let zero=try field.integer(0,using:&a)
  for length in [0,2] {
   let invalid=try domain.prefixPoint(field:field,coordinates:Array(repeating:zero,count:length),using:&a)
   do {
    _ = try domain.contains(invalid,in:condition,limits:.init(maximumRoots:50),using:&a)
    throw ExactRealCellFailure.invalidCoverage
   } catch ExactRealCellFailure.invalidVariable { }
  }
  let prefix=try domain.prefixPoint(field:field,coordinates:[zero,zero],using:&a)
  do {
   _ = try domain.locate(prefix,in:partition,limits:.init(maximumRoots:50),using:&a)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.invalidVariable { }
  do {
   _ = try domain.point(field:field,coordinates:[zero],using:&a)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.invalidVariable { }
  do {
   _ = try domain.prefixPoint(field:field,coordinates:[zero,zero,zero,zero],using:&a)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.invalidVariable { }
  let foreign=try Field.base(field:CellFixtures.Base(),maximumExtensionLevel:2,using:&a)
  do {
   _ = try domain.prefixPoint(field:foreign,coordinates:[],using:&a)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.scalar(.incompatibleDomain) { }
  do {
   _ = try domain.prefixPoint(field:field,coordinates:[foreign.integer(0,using:&a)],using:&a)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.scalar(.incompatibleDomain) { }
  let another=try Domain(field:field,variableCount:3,using:&a)
  do {
   _ = try another.locatePrefix(prefix,in:partition,limits:.init(maximumRoots:50),using:&a)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.incompatibleDomain { }

  // Preparing a point in a descendant field admits the source field's ancestor embedding.
  let roots=try ExactRealRootDomain(field:field,using:&a),q=roots.polynomials
  let law=try roots.bind(q.polynomial(terms:[.init(powers:[2],coefficient:field.integer(1,using:&a)),
   .init(powers:[0],coefficient:field.integer(-2,using:&a))],using:&a),using:&a)
  let selected=try roots.domain(lower:.finite(field.integer(1,using:&a)),upper:.finite(field.integer(2,using:&a)),using:&a)
  let child=try field.adjoin(roots.isolate(law,in:selected,limits:.init(maximumRoots:1),using:&a).roots[0],using:&a)
  let childPoint=try domain.prefixPoint(field:child.domain,
   coordinates:[child.domain.importing(zero,using:&a)],using:&a)
  try CellFixtures.require(try domain.locatePrefix(childPoint,in:partition,limits:.init(maximumRoots:50),using:&a) == firstPrefix)
  var observed=TerminalAdmission()
  _ = try domain.prefixPoint(field:child.domain,coordinates:childPoint.coordinates,using:&observed)
  var cancelled=TerminalAdmission(cancelAt:observed.checkpoints)
  do {
   _ = try domain.prefixPoint(field:child.domain,coordinates:childPoint.coordinates,using:&cancelled)
   throw ExactRealCellFailure.invalidCoverage
  } catch ExactRealCellFailure.scalar(.cancelled) { }
 }

 private static func dimensionsAndOutside() throws {
  for count in [0,5] {
   var a=try CellFixtures.ledger()
   let (field,domain,_)=try CellFixtures.setup(count,&a),roots=try ExactRealRootDomain(field:field,using:&a)
   let zero=try field.integer(0,using:&a)
   let singleton=try roots.domain(lower:.finite(zero),upper:.finite(zero),using:&a)
   let source=try domain.bind(polynomials:[],domains:Array(repeating:singleton,count:count),using:&a)
   let partition=try domain.decompose(source,limits:.init(maximumStoredCells:10,maximumRootsPerStack:5),using:&a)
   try CellFixtures.require(partition.cells.count == 1 && partition.cells[0].dimension == 0)
   _ = try location(Array(repeating:0,count:count),field:field,domain:domain,partition:partition,&a)
   if count > 0 {
    let outside=try domain.prefixPoint(field:field,coordinates:[field.integer(1,using:&a)],using:&a)
    try CellFixtures.require(try domain.locatePrefix(outside,in:partition,limits:.init(maximumRoots:5),using:&a) == nil)
    var full=Array(repeating:zero,count:count); full[count-1]=try field.integer(1,using:&a)
    let point=try domain.point(field:field,coordinates:full,using:&a)
    try CellFixtures.require(try domain.locate(point,in:partition,limits:.init(maximumRoots:5),using:&a) == nil)
   }
  }
 }

 public static func verify() throws {
  try movingBranches()
  try nullificationAndLengths()
  try dimensionsAndOutside()
  print("PASS: public prefixes, non-sample branches, nullification, lengths, field lineage, outside domains and dimensions zero/five")
 }
}
