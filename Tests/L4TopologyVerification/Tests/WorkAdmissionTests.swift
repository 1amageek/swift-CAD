import Testing
import L0
import L1
import L2
import L3
import L4Fixtures
@testable import L4

private func workLedger(_ work: Int) throws -> ExactScalarLedger {
 .init(limits:try .init(work:work,storageBytes:700_000_000,valueDepth:400,coefficientDepth:400))
}

@Test(.timeLimit(.minutes(1))) func eliminationAdmissionRepair() throws {
 var setup = try TopologyFixtures.ledger()
 let field = try TopologyFixtures.Field.base(field:TopologyFixtures.Base(),maximumExtensionLevel:10,using:&setup)
 let topology = TopologyFixtures.Topology(cells:TopologyFixtures.Cells.self)
 for quantifiers in [Array(repeating:true,count:64), [true,false,true,true], [false,false], []] {
  let polynomials = try ExactPolynomialDomain(field:field,variableCount:quantifiers.count,using:&setup)
  var formula = ExactTopologyFormula(field:field,polynomials:polynomials,freeCount:0,
   conjunctionEnd:1,quantifiers:quantifiers)
  formula.instructions = [.literal(true)]
  let suffix = quantifiers.reversed().prefix(while: { $0 }).count
  let scan = suffix + (suffix < quantifiers.count ? 1:0)
  let required = scan + 2*suffix
  var exact = try workLedger(required)
  let result = try topology.eliminateEqualities(formula,&exact)
  #expect(result.eliminations.isEmpty)
  #expect(result.quantifiers == quantifiers)
  #expect(exact.work == required)
  if required > 0 {
   var insufficient = try workLedger(required-1)
   do {
    _ = try topology.eliminateEqualities(formula,&insufficient)
    Issue.record("Missing admission for a quantifier or equality-candidate visit")
   } catch ExactScalarFailure.resourceLimit(.work) { }
   var cancelled = try WorkCancellationAdmission(stop:1)
   do {
    _ = try topology.eliminateEqualities(formula,&cancelled)
    Issue.record("Cancellation must abort before reading the quantifier")
   } catch ExactScalarFailure.cancelled { }
   #expect(cancelled.ledger.work == 1)
  }
 }
 // Removing the final existential slot must preserve the preceding universal
 // barrier; eliminating x0 from x0-x1=0 across that barrier would change truth.
 let p = try ExactPolynomialDomain(field:field,variableCount:3,using:&setup)
 var mixed = ExactTopologyFormula(field:field,polynomials:p,freeCount:0,
  conjunctionEnd:5,quantifiers:[true,false,true])
 mixed.atoms = [try p.subtracting(p.variable(0,using:&setup),p.variable(1,using:&setup),using:&setup),
  try p.variable(2,using:&setup)]
 mixed.instructions = [.literal(true),.sign(polynomial:0,relation:.equal),.and,
  .sign(polynomial:1,relation:.equal),.and]
 var admission = try TopologyFixtures.ledger()
 let reduced = try topology.eliminateEqualities(mixed,&admission)
 #expect(reduced.eliminations.count == 1)
 #expect(reduced.eliminations.first?.variable == 2)
 #expect(reduced.quantifiers == [true,false])
 #expect(reduced.polynomials.variableCount == 2)
}

@Test(.timeLimit(.minutes(1))) func factorAdmissionRepair() throws {
 var setup = try TopologyFixtures.ledger()
 let topology = TopologyFixtures.Topology(cells:TopologyFixtures.Cells.self)
 for n in [0,1,4,16] {
  let (field,cells,line) = try TopologyFixtures.setup(n,&setup)
  let source = try cells.bind(polynomials:[],domains:Array(repeating:line,count:n),using:&setup)
  let partition = try cells.decompose(source,limits:.init(maximumStoredCells:100,maximumRootsPerStack:10),using:&setup)
  let definition = try cells.definition(of:partition.cells[0],in:partition,using:&setup)
  var preparation = try TopologyFixtures.ledger()
  _ = try TopologyFixtures.Cells(retaining:source,using:&preparation)
  _ = try topology.formula(field:field,free:n,quantifiers:[],&preparation)
  let required = preparation.work + 3*n
  var exact = try workLedger(required)
  let factors = try topology.certifiedFactors(definition,&exact)
  #expect(factors.isEmpty)
  #expect(exact.work == required)
  var insufficient = try workLedger(required-1)
  do {
   _ = try topology.certifiedFactors(definition,&insufficient)
   Issue.record("An absent boundary must still consume work")
  } catch ExactRealCellFailure.scalar(.resourceLimit(.work)) { }
    catch ExactPolynomialFailure.scalar(.resourceLimit(.work)) { }
    catch ExactScalarFailure.resourceLimit(.work) { }
  if n > 0 {
   var cancelled = try WorkCancellationAdmission(stop:preparation.work+1)
   do {
    _ = try topology.certifiedFactors(definition,&cancelled)
    Issue.record("Cancellation must abort at the first absent boundary")
   } catch ExactScalarFailure.cancelled { }
   #expect(cancelled.ledger.work == preparation.work+1)
  }
 }
}
