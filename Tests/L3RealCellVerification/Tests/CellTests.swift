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
 let other = try ExactRealCellDomain(field:f,variableCount:0,using:&a)
 do { _ = try other.predicate(instructions:[.literal(true)],for:s,using:&a); Issue.record("Accepted foreign source") } catch ExactRealCellFailure.incompatibleDomain { }
 let retained = try ExactRealCellDomain(retaining:s,using:&a)
 _ = try retained.predicate(instructions:[.sign(polynomial:0,relation:.equal)],for:s,using:&a)
 do { _ = try d.bind(polynomials:[other.polynomials.zero(using:&a)],domains:[],using:&a); Issue.record("Accepted foreign polynomial") } catch { }
}
