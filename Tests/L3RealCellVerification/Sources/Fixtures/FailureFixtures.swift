import L0
import L1
import L2
import L3

public enum FailureFixtures {
 public static func sourceTraversal() throws {
  var preparation = try CellFixtures.ledger()
  for count in [0, 1, 100_000] {
   let (_, domain, all) = try CellFixtures.setup(count, &preparation)
   let domains = Array(repeating: all, count: count)
   let requiredWork = count + 1
   var short = ExactScalarLedger(limits: try .init(work: requiredWork - 1,
    storageBytes: 100_000, valueDepth: 400, coefficientDepth: 400))
   do {
    _ = try domain.bind(polynomials: [], domains: domains, using: &short)
    throw ExactRealCellFailure.invalidCoverage
   } catch ExactRealCellFailure.scalar(.resourceLimit(.work)) { }
   var exact = ExactScalarLedger(limits: try .init(work: requiredWork,
    storageBytes: 100_000, valueDepth: 400, coefficientDepth: 400))
   let source = try domain.bind(polynomials: [], domains: domains, using: &exact)
   try CellFixtures.require(source.domains.count == count && exact.work == requiredWork)
  }
 }
 public static func resources() throws {
  var a=try CellFixtures.ledger()
  let (_,d,all)=try CellFixtures.setup(1,&a),p=d.polynomials
  let s=try d.bind(polynomials:[p.variable(0,using:&a)],domains:[all],using:&a)
  let limits=try ExactRealCellLimits(maximumStoredCells:10,maximumRootsPerStack:10)
  var observed=TerminalAdmission()
  let result=try d.decompose(s,limits:limits,using:&observed)
  var final=TerminalAdmission(cancelAt:observed.checkpoints)
  do { _ = try d.decompose(s,limits:limits,using:&final); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.scalar(.cancelled) { }
  var exact=ExactScalarLedger(limits:try .init(work:observed.work,storageBytes:observed.storage,valueDepth:400,coefficientDepth:400))
  try CellFixtures.require(try d.decompose(s,limits:limits,using:&exact).cells.count == result.cells.count)
  for axis in 0..<2 {
   var short=ExactScalarLedger(limits:try .init(work:axis == 0 ? observed.work-1:observed.work,storageBytes:axis == 1 ? observed.storage-1:observed.storage,valueDepth:400,coefficientDepth:400))
   do { _ = try d.decompose(s,limits:limits,using:&short); throw ExactRealCellFailure.invalidCoverage }
   catch ExactRealCellFailure.scalar(.resourceLimit(let resource)) { try CellFixtures.require(resource == (axis == 0 ? .work:.storage)) }
  }
  do { _ = try d.decompose(s,limits:.init(maximumStoredCells:1,maximumRootsPerStack:10),using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.cellLimit { }
  do { _ = try d.decompose(s,limits:.init(maximumStoredCells:10,maximumRootsPerStack:0),using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.root(.resultLimit) { }
  var cancelled=try CellFixtures.ledger(); cancelled.cancel()
  do { _ = try d.decompose(s,limits:limits,using:&cancelled); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.scalar(.cancelled) { }
  let sourceField=try CellFixtures.Field(retaining:s.polynomials[0].terms.first!.coefficient,using:&a)
  let ax=try p.variable(0,using:&a)
  let depthSource=try d.bind(polynomials:[p.subtracting(p.multiplying(ax,ax,using:&a),p.constant(sourceField.integer(2,using:&a),using:&a),using:&a)],domains:[all],using:&a)
  let deep=try d.decompose(depthSource,limits:limits,using:&a)
  try CellFixtures.require(deep.depth.value > 0)
  var shallow=ExactScalarLedger(limits:try .init(work:10_000_000,storageBytes:30_000_000,valueDepth:deep.depth.value-1,coefficientDepth:400))
  do { _ = try d.sample(of:deep.cells.first!,in:deep,using:&shallow); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.scalar(.resourceLimit(.valueDepth)) { }
  let cell=result.cells.first!,sample=try d.sample(of:cell,in:result,using:&a)
  var query=TerminalAdmission(); _ = try d.locate(sample,in:result,limits:.init(maximumRoots:10),using:&query)
  var cancelQuery=TerminalAdmission(cancelAt:query.checkpoints)
  do { _ = try d.locate(sample,in:result,limits:.init(maximumRoots:10),using:&cancelQuery); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.scalar(.cancelled) { }
  do { _ = try d.locate(sample,in:result,limits:.init(maximumRoots:0),using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.root(.resultLimit) { }
  let pred=try d.predicate(instructions:[.literal(true)],for:s,using:&a)
  var selected=TerminalAdmission(); _ = try d.select(result,matching:pred,using:&selected)
  var cancelSelect=TerminalAdmission(cancelAt:selected.checkpoints)
  do { _ = try d.select(result,matching:pred,using:&cancelSelect); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.scalar(.cancelled) { }
  // An explicit coefficient-field extension ceiling is a failure, not a fallback.
  let f=try CellFixtures.Field.base(field:CellFixtures.Base(),maximumExtensionLevel:0,using:&a)
  let ad=try CellFixtures.Domain(field:f,variableCount:1,using:&a),ap=ad.polynomials,x=try ap.variable(0,using:&a)
  let ar=try ExactRealRootDomain(field:f,using:&a),domain=try ar.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
  let asource=try ad.bind(polynomials:[ap.subtracting(ap.multiplying(x,x,using:&a),ap.constant(f.integer(2,using:&a),using:&a),using:&a)],domains:[domain],using:&a)
  do { _ = try ad.decompose(asource,limits:limits,using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.root(.extensionLevelLimit) { }
 }
 public static func escapedOwnership() throws {
  func escape() throws -> ExactRealCellCondition<ExactRationalScalarDomain> {
   var a=try CellFixtures.ledger()
   let (_,d,all)=try CellFixtures.setup(2,&a),p=d.polynomials
   let source=try d.bind(polynomials:[p.variable(0,using:&a)],domains:[all,all],using:&a)
   let partition=try d.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:10),using:&a)
   return try d.condition(of:partition.cells.first!,in:partition,using:&a)
  }
  let condition=try escape()
  // Only the issued condition survives; its cell retains the source, graph and field.
  var a=try CellFixtures.ledger()
  let d=try CellFixtures.Domain(retaining:condition.cell.source,using:&a)
  let f=try CellFixtures.Field.base(field:CellFixtures.Base(),maximumExtensionLevel:2,using:&a)
  do { _ = try d.point(field:f,coordinates:[f.integer(0,using:&a),f.integer(0,using:&a)],using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.scalar(.incompatibleDomain) { }
  let view=condition.cell.source
  let retained=try CellFixtures.Domain(retaining:view,using:&a)
  // Recreate a point in the retained original field through its polynomial coefficient owner.
  let one=try retained.polynomials.constant(condition.cell.projectionLaws.first!.terms.first!.coefficient,using:&a)
  let field=try CellFixtures.Field(retaining:one.terms.first!.coefficient,using:&a)
  let point=try retained.point(field:field,coordinates:[field.integer(-2,using:&a),field.integer(7,using:&a)],using:&a)
  try CellFixtures.require(try retained.contains(point,in:condition,limits:.init(maximumRoots:10),using:&a))
 }
}
