import Testing
import L0
import L1
import L2
@testable import L3
@Test(.timeLimit(.minutes(1))) func projectionAndSource() throws {
 var a = ExactScalarLedger(limits: try ExactScalarLimits(work: 100_000_000, storageBytes: 300_000_000, valueDepth: 100, coefficientDepth: 100))
 let f = try ExactAlgebraicScalarDomain.base(field: ExactRationalScalarDomain(), maximumExtensionLevel: 10, using: &a)
 let d = try ExactRealCellDomain(field: f, variableCount: 2, using: &a)
 let p = d.polynomials, x = try p.variable(0, using: &a), y = try p.variable(1, using: &a)
 let law = try p.subtracting(p.multiplying(y,y,using:&a),x,using:&a)
 let r = try ExactRealRootDomain(field:f, using:&a)
 let all = try r.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
 let s = try d.bind(polynomials:[law],domains:[all,all],using:&a)
 _ = try d.predicate(instructions:[.sign(polynomial:0,relation:.equal)],for:s,using:&a)
 try ExactCellAccess.run(&a) { usage in
  let derivative = try p.differentiated(law,in:1,using:&usage)
  let psc = try d.principal(law,derivative,axis:1,index:0,&usage)
  let resultant = try p.resultant(law,derivative,eliminating:1,using:&usage)
  #expect(try p.equals(psc,resultant,using:&usage))
  let g = try p.adding(p.multiplying(y,y,using:&usage),p.constant(f.integer(1,using:&usage),using:&usage),using:&usage)
  let higher = try d.principal(law,g,axis:1,index:1,&usage)
  #expect(try p.isZero(higher,using:&usage))
  let withLinear=try p.adding(p.multiplying(y,y,using:&usage),y,using:&usage)
  let nonzeroHigher=try d.principal(law,withLinear,axis:1,index:1,&usage)
  #expect(try p.equals(nonzeroHigher,p.constant(f.integer(1,using:&usage),using:&usage),using:&usage))
  let factor=try p.subtracting(y,x,using:&usage)
  let squared=try p.multiplying(factor,factor,using:&usage)
  let sharedPSC=try d.principal(squared,factor,axis:1,index:0,&usage)
  #expect(try p.isZero(sharedPSC,using:&usage))
  #expect(try p.degree(of:p.greatestCommonDivisor(squared,factor,using:&usage),in:1,using:&usage) == 1)
  let levels = try d.projection(s,&usage)
  #expect(levels.count == 2)
  #expect(!levels[0].laws.isEmpty)
 }
}

@Test(.timeLimit(.minutes(1))) func sourceFailures() throws {
 var a = ExactScalarLedger(limits: try ExactScalarLimits(work: 10_000_000, storageBytes: 30_000_000, valueDepth: 100, coefficientDepth: 100))
 let f = try ExactAlgebraicScalarDomain.base(field: ExactRationalScalarDomain(), maximumExtensionLevel: 5, using:&a)
 let d = try ExactRealCellDomain(field:f,variableCount:0,using:&a)
 let s = try d.bind(polynomials:[d.polynomials.zero(using:&a)],domains:[],using:&a)
 do { _ = try d.predicate(instructions:[.and],for:s,using:&a); Issue.record("Accepted invalid program") } catch ExactRealCellFailure.invalidPredicate { }
 for instructions: [ExactRealCellInstruction] in [[],[.literal(true),.literal(false)],[.sign(polynomial: -1,relation:.equal)],[.sign(polynomial:1,relation:.equal)]] {
  do { _ = try d.predicate(instructions:instructions,for:s,using:&a); Issue.record("Accepted invalid postfix/index") } catch ExactRealCellFailure.invalidPredicate { }
 }
 let other = try ExactRealCellDomain(field:f,variableCount:0,using:&a)
 do { _ = try other.predicate(instructions:[.literal(true)],for:s,using:&a); Issue.record("Accepted foreign source") } catch ExactRealCellFailure.incompatibleDomain { }
 let retained = try ExactRealCellDomain(retaining:s,using:&a)
 _ = try retained.predicate(instructions:[.sign(polynomial:0,relation:.equal)],for:s,using:&a)
 do { _ = try d.bind(polynomials:[other.polynomials.zero(using:&a)],domains:[],using:&a); Issue.record("Accepted foreign polynomial") } catch { }
}

import L3Fixtures
@Test(.timeLimit(.minutes(1))) func nullification() throws { try CellFixtures.nullification() }
@Test(.timeLimit(.minutes(1))) func singularities() throws { try CellFixtures.singularities() }
@Test(.timeLimit(.minutes(1))) func domainClipping() throws { try CellFixtures.domains() }

@Test(.timeLimit(.minutes(1))) func transportedCoordinates() throws {
 var a=try CellFixtures.ledger()
 let (f,d,all)=try CellFixtures.setup(2,&a),p=d.polynomials
 let x=try p.variable(0,using:&a),y=try p.variable(1,using:&a)
 let law=try p.subtracting(p.multiplying(x,x,using:&a),p.constant(f.integer(2,using:&a),using:&a),using:&a)
 let s=try d.bind(polynomials:[law,p.subtracting(y,x,using:&a)],domains:[all,all],using:&a)
 let result=try d.decompose(s,limits:.init(maximumStoredCells:100,maximumRootsPerStack:20),using:&a)
 var selected=0
 for cell in result.cells where cell.signs == [.zero,.zero] {
  let sample=result.owner.records[cell.index].sample
  #expect(sample.field.extensionLevel == 1)
  #expect(try sample.field.compare(sample.coordinates[0],sample.coordinates[1],using:&a) == .equal)
  selected += 1
 }
 #expect(selected == 2)
}
@Test(.timeLimit(.minutes(1))) func selectionAndLocation() throws { try QueryFixtures.selectionAndLocation() }
@Test(.timeLimit(.minutes(1))) func algebraicQueries() throws { try QueryFixtures.algebraicQueries() }
@Test(.timeLimit(.minutes(1))) func applicationRelations() throws { try QueryFixtures.applicationRelations() }
@Test(.timeLimit(.minutes(1))) func retainedAndOutside() throws { try QueryFixtures.retainedAndOutside() }

@Test(.timeLimit(.minutes(1))) func resources() throws { try FailureFixtures.resources() }
@Test(.timeLimit(.minutes(1))) func escapedOwnership() throws { try FailureFixtures.escapedOwnership() }

@Test(.timeLimit(.minutes(1))) func originalAlgebraicCoefficients() throws { try OriginalCoefficientFixtures.run() }

@Test(.timeLimit(.minutes(1))) func nullifiedQuery() throws { try QueryFixtures.nullifiedQuery() }
@Test(.timeLimit(.minutes(1))) func checkedProjectionSizes() throws {
 #expect(throws:ExactRealCellFailure.self) { _ = try ExactCellAccess.multiply(Int.max,2) }
 #expect(throws:ExactRealCellFailure.self) { _ = try ExactCellAccess.add(Int.max,1) }
 var a=try CellFixtures.ledger()
 let (_,d,_)=try CellFixtures.setup(1,&a)
 do { _ = try ExactCellAccess.run(&a) { try d.determinant([],size:Int.max,&$0) }; Issue.record("Accepted matrix overflow") } catch ExactRealCellFailure.countOverflow { }
}

@Test(.timeLimit(.minutes(1))) func protocolRequirements() throws { try ProtocolFixtures.run() }
@Test(.timeLimit(.minutes(1))) func concurrentImmutableReaders() async throws {
 var a=try CellFixtures.ledger()
 let (f,d,all)=try CellFixtures.setup(1,&a),p=d.polynomials
 let source=try d.bind(polynomials:[p.variable(0,using:&a)],domains:[all],using:&a)
 let partition=try d.decompose(source,limits:.init(maximumStoredCells:10,maximumRootsPerStack:10),using:&a)
 let predicate=try d.predicate(instructions:[.sign(polynomial:0,relation:.greater)],for:source,using:&a)
 let point=try d.point(field:f,coordinates:[f.integer(3,using:&a)],using:&a)
 try await withThrowingTaskGroup(of:Bool.self) { group in
  for _ in 0..<4 { group.addTask {
   var caller=try CellFixtures.ledger()
   let selected=try d.select(partition,matching:predicate,using:&caller)
   return try d.locate(point,in:partition,limits:.init(maximumRoots:10),using:&caller) == selected.cells.first
  } }
  for try await result in group { try CellFixtures.require(result) }
 }
}
