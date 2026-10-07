import L0
import L1
import L2
import L3

public enum InspectionFixtures {
 public static func ports<D: ExactRealCellDescribing & ExactRealCellTraversing & ExactRealCellQuerying>(_ d: D,
  _ partition: ExactRealCellPartition<D.Base>, _ a: inout ExactScalarLedger) throws {
  _ = try d.coefficientField(of:partition.source,using:&a)
  if let root = try d.root(in:partition,using:&a) {
   _ = try d.children(of:root,in:partition,using:&a)
   _ = try d.definition(of:root,in:partition,using:&a)
   let origin = try d.sample(of:root,in:partition,using:&a)
   try CellFixtures.require(try d.locatePrefix(origin,in:partition,limits:.init(maximumRoots:0),using:&a) == root)
  }
 }
 public static func run() throws {
  var a = try CellFixtures.ledger()
  let (f,d,all) = try CellFixtures.setup(2,&a), p = d.polynomials
  let x = try p.variable(0,using:&a), y = try p.variable(1,using:&a)
  let law = try p.subtracting(p.multiplying(y,y,using:&a),x,using:&a)
  let source = try d.bind(polynomials:[law],domains:[all,all],using:&a)
  let partition = try d.decompose(source,limits:.init(maximumStoredCells:200,maximumRootsPerStack:20),using:&a)
  try ports(d,partition,&a)
  let field = try d.coefficientField(of:source,using:&a)
  _ = try field.integer(1,using:&a)
  let root = try d.root(in:partition,using:&a)!
  let first = try d.children(of:root,in:partition,using:&a)
  try CellFixtures.require(first.count == 3)
  let prefixDomain = try CellFixtures.Domain(field:f,variableCount:1,using:&a)
  let prefix = try prefixDomain.point(field:f,coordinates:[f.integer(4,using:&a)],using:&a)
  try CellFixtures.require(try d.locatePrefix(prefix,in:partition,limits:.init(maximumRoots:20),using:&a) == first[2])
  let emptyDomain = try CellFixtures.Domain(field:f,variableCount:0,using:&a)
  let origin = try emptyDomain.point(field:f,coordinates:[],using:&a)
  try CellFixtures.require(try d.locatePrefix(origin,in:partition,limits:.init(maximumRoots:0),using:&a) == root)
  do { _ = try d.locate(prefix,in:partition,limits:.init(maximumRoots:20),using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.invalidVariable { }
  let second = try d.children(of:first[2],in:partition,using:&a)
  try CellFixtures.require(second.count == 5)
  let negative = try d.definition(of:second[1],in:partition,using:&a)
  let positive = try d.definition(of:second[3],in:partition,using:&a)
  try CellFixtures.require(negative.coordinateCount == 2 && negative.steps[1].section!.derivativeSigns == [.zero,.negative,.positive])
  try CellFixtures.require(positive.steps[1].section!.derivativeSigns == [.zero,.positive,.positive])
  let actual = try d.point(field:f,coordinates:[f.integer(4,using:&a),f.integer(2,using:&a)],using:&a)
  try CellFixtures.require(try d.locatePrefix(actual,in:partition,limits:.init(maximumRoots:20),using:&a) == second[3])
  let sector = try d.definition(of:second[2],in:partition,using:&a)
  try CellFixtures.require(sector.steps[1].lower!.rootOrdinal == 0 && sector.steps[1].upper!.rootOrdinal == 1)
  try CellFixtures.require(try d.children(of:second[2],in:partition,using:&a).isEmpty)
  let nullified = try d.children(of:first[1],in:partition,using:&a)
  try CellFixtures.require(nullified.count == 3)
  let repeated = try d.definition(of:nullified[1],in:partition,using:&a)
  try CellFixtures.require(repeated.steps[1].section!.derivativeSigns.first == .zero)
  let r = try ExactRealRootDomain(field:f,using:&a)
  let empty = try d.bind(polynomials:[],domains:[all,r.emptyDomain(using:&a)],using:&a)
  let ep = try d.decompose(empty,limits:.init(maximumStoredCells:0,maximumRootsPerStack:0),using:&a)
  try CellFixtures.require(try d.root(in:ep,using:&a) == nil)
  try CellFixtures.require(try d.locatePrefix(origin,in:ep,limits:.init(maximumRoots:0),using:&a) == nil)
  // Distinct close roots, shared multiplicity and clipped neighboring boundaries.
  let (g,oneD,line) = try CellFixtures.setup(1,&a), q = oneD.polynomials
  let t = try q.variable(0,using:&a), one = try g.integer(1,using:&a)
  let near = try g.adding(one,g.dividing(one,g.integer(1000000,using:&a),using:&a),using:&a)
  let l = try q.subtracting(t,q.constant(one,using:&a),using:&a)
  let h = try q.subtracting(t,q.constant(near,using:&a),using:&a)
  let rr = try ExactRealRootDomain(field:g,using:&a)
  let clipped = try rr.domain(lower:.finite(one),upper:.finite(near),includesLower:false,using:&a)
  let cs = try oneD.bind(polynomials:[q.multiplying(l,l,using:&a),q.multiplying(l,h,using:&a)],domains:[clipped],using:&a)
  let cp = try oneD.decompose(cs,limits:.init(maximumStoredCells:20,maximumRootsPerStack:20),using:&a)
  try CellFixtures.require(cp.cells.count == 2)
  let cd = try oneD.definition(of:cp.cells[0],in:cp,using:&a)
  try CellFixtures.require(cd.steps[0].lower!.rootOrdinal == 0 && cd.steps[0].upper!.rootOrdinal == 1)
  // Original algebraic coefficients remain in their family after the provider is dropped.
  let roots = try rr.isolate(rr.bind(rr.polynomials.polynomial(terms:[.init(powers:[2],coefficient:one),.init(powers:[0],coefficient:g.integer(-2,using:&a))],using:&a),using:&a),in:line,limits:.init(maximumRoots:10),using:&a)
  let extensionField = try g.adjoin(roots.roots[1],using:&a)
  let alg = try CellFixtures.Domain(field:extensionField.domain,variableCount:1,using:&a)
  let ap = alg.polynomials
  let al = try ap.subtracting(ap.variable(0,using:&a),ap.constant(extensionField.generator,using:&a),using:&a)
  let ar = try ExactRealRootDomain(field:extensionField.domain,using:&a)
  let az = try alg.bind(polynomials:[al],domains:[ar.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)],using:&a)
  let azp = try alg.decompose(az,limits:.init(maximumStoredCells:20,maximumRootsPerStack:10),using:&a)
  let azd = try alg.definition(of:azp.cells[1],in:azp,using:&a)
  try CellFixtures.require(azd.coefficientField.extensionLevel == 1 && azd.steps[0].section!.derivativeSigns == [.zero,.positive])
  let foreign = try d.decompose(source,limits:.init(maximumStoredCells:200,maximumRootsPerStack:20),using:&a)
  do { _ = try d.definition(of:foreign.cells[0],in:partition,using:&a); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.invalidCell { }
 }
}
