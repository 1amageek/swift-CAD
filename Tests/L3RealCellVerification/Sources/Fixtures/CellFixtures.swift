import L0
import L1
import L2
import L3

public enum CellFixtures {
 public typealias Base = ExactRationalScalarDomain
 public typealias Field = ExactAlgebraicScalarDomain<Base>
 public typealias Domain = ExactRealCellDomain<Base>
 public typealias Polynomial = ExactPolynomial<Field>
 public static func require(_ condition: Bool) throws { if !condition { throw ExactRealCellFailure.invalidCoverage } }
 public static func ledger() throws -> ExactScalarLedger {
  .init(limits:try .init(work:200_000_000,storageBytes:700_000_000,valueDepth:400,coefficientDepth:400))
 }
 public static func setup(_ count: Int, _ a: inout ExactScalarLedger) throws -> (Field,Domain,ExactRealRootInterval<Field.Value>) {
  let f = try Field.base(field:Base(),maximumExtensionLevel:10,using:&a)
  let d = try Domain(field:f,variableCount:count,using:&a)
  let r = try ExactRealRootDomain(field:f,using:&a)
  return (f,d,try r.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a))
 }
 public static func nullification() throws {
  var a = try ledger()
  let (_,d,all) = try setup(2,&a), p=d.polynomials
  let x=try p.variable(0,using:&a), y=try p.variable(1,using:&a)
  let s=try d.bind(polynomials:[p.multiplying(x,y,using:&a)],domains:[all,all],using:&a)
  let partition=try d.decompose(s,limits:.init(maximumStoredCells:100,maximumRootsPerStack:20),using:&a)
  var zeroDimensions: [Int] = []
  for cell in partition.cells where cell.signs[0] == .zero { zeroDimensions.append(cell.dimension) }
  try require(zeroDimensions == [1,1,1])
  let (_,d3,all3) = try setup(3,&a), q=d3.polynomials
  let x3=try q.variable(0,using:&a), y3=try q.variable(1,using:&a), z3=try q.variable(2,using:&a)
  let s3=try d3.bind(polynomials:[q.adding(q.multiplying(x3,z3,using:&a),y3,using:&a)],domains:[all3,all3,all3],using:&a)
  let cells=try d3.decompose(s3,limits:.init(maximumStoredCells:300,maximumRootsPerStack:20),using:&a).cells
  try require(cells.contains { $0.signs[0] == .zero && $0.dimension == 1 })
 }
 public static func singularities() throws {
  var a=try ledger()
  let (f,d,all)=try setup(2,&a),p=d.polynomials
  let x=try p.variable(0,using:&a),y=try p.variable(1,using:&a)
  let xx=try p.multiplying(x,x,using:&a), yy=try p.multiplying(y,y,using:&a)
  let cases = [try p.adding(xx,yy,using:&a),
   try p.subtracting(yy,p.multiplying(xx,x,using:&a),using:&a),
   try p.multiplying(p.subtracting(x,y,using:&a),p.subtracting(x,y,using:&a),using:&a)]
  for (index,law) in cases.enumerated() {
   let s=try d.bind(polynomials:[law],domains:[all,all],using:&a)
   let result=try d.decompose(s,limits:.init(maximumStoredCells:200,maximumRootsPerStack:30),using:&a)
   let zeros=result.cells.filter { $0.signs[0] == .zero }
   if index == 0 { try require(zeros.count == 1 && zeros[0].dimension == 0) }
   else { try require(zeros.contains { $0.dimension == 1 }) }
  }
  let shifted=try p.subtracting(x,p.constant(f.integer(1,using:&a),using:&a),using:&a)
  let mixed=try p.multiplying(x,p.adding(p.multiplying(shifted,shifted,using:&a),yy,using:&a),using:&a)
  let source=try d.bind(polynomials:[mixed],domains:[all,all],using:&a)
  let mixedCells=try d.decompose(source,limits:.init(maximumStoredCells:400,maximumRootsPerStack:50),using:&a).cells
  try require(mixedCells.contains { $0.signs == [.zero] && $0.dimension == 0 })
  try require(mixedCells.contains { $0.signs == [.zero] && $0.dimension == 1 })
 }
 public static func domains() throws {
  var a=try ledger()
  let (f,d,_)=try setup(1,&a),p=d.polynomials
  let r=try ExactRealRootDomain(field:f,using:&a), zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
  for lower in [false,true] { for upper in [false,true] {
   let box=try r.domain(lower:.finite(zero),upper:.finite(one),includesLower:lower,includesUpper:upper,using:&a)
   let s=try d.bind(polynomials:[],domains:[box],using:&a)
   let result=try d.decompose(s,limits:.init(maximumStoredCells:20,maximumRootsPerStack:10),using:&a)
   try require(result.cells.count == 1 + (lower ? 1:0) + (upper ? 1:0))
  } }
  let singleton=try r.domain(lower:.finite(zero),upper:.finite(zero),using:&a)
  let s=try d.bind(polynomials:[p.zero(using:&a)],domains:[singleton],using:&a)
  let result=try d.decompose(s,limits:.init(maximumStoredCells:20,maximumRootsPerStack:10),using:&a)
  try require(result.cells.count == 1 && result.cells.first!.dimension == 0)
  let openSingleton=try r.domain(lower:.finite(zero),upper:.finite(zero),includesLower:false,using:&a)
  let os=try d.bind(polynomials:[],domains:[openSingleton],using:&a)
  try require(try d.decompose(os,limits:.init(maximumStoredCells:0,maximumRootsPerStack:0),using:&a).cells.isEmpty)
  let empty=try r.emptyDomain(using:&a)
  let es=try d.bind(polynomials:[],domains:[empty],using:&a)
  let er=try d.decompose(es,limits:.init(maximumStoredCells:0,maximumRootsPerStack:0),using:&a)
  try require(er.cells.isEmpty && er.storedCellCount == 0)
  let (_,d0,_)=try setup(0,&a)
  let z=try d0.bind(polynomials:[d0.polynomials.zero(using:&a)],domains:[],using:&a)
  let zr=try d0.decompose(z,limits:.init(maximumStoredCells:1,maximumRootsPerStack:0),using:&a)
  try require(zr.cells.count == 1 && zr.cells.first!.signs == [.zero])
 }
}
