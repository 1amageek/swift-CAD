#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
 func constantLeading<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, axis: Int, _ a: inout A) throws -> Bool {
  var degree = 0
  for term in law.terms { try a.consumeWork(1); degree = max(degree,term.powers[axis]) }
  if degree == 0 { return false }
  for term in law.terms {
   try a.consumeWork(1)
   if term.powers[axis] != degree { continue }
   for slot in term.powers.indices { try a.consumeWork(1); if slot != axis && term.powers[slot] != 0 { return false } }
  }
  return true
 }
 func invariantAtoms<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, atoms: [Polynomial], instructions: [ExactRealCellInstruction], quantifiers: [Bool], counts: inout ExactTopologyCounts, _ a: inout A) throws -> [ExactRealTopologySignInvariant<Base>]? {
  if !quantifiers.isEmpty { return nil }
  let f = definition.coefficientField, n = definition.coordinateCount
  let p = try ExactPolynomialDomain(field:f,variableCount:n,using:&a)
  try ExactTopologyAccess.storage(atoms.count,ExactRealTopologySignInvariant<Base>.self,&a)
  var certificates: [ExactRealTopologySignInvariant<Base>] = []; certificates.reserveCapacity(atoms.count)
  for rawIndex in atoms.indices {
   let raw = atoms[rawIndex]
   let law = try p.importing(raw,using:&a)
   var axis: Int? = nil
   for term in law.terms {
    var degree = 0
    for slot in term.powers.indices {
     try a.consumeWork(1); degree = try ExactTopologyAccess.add(degree,term.powers[slot])
     if term.powers[slot] != 0 { axis = max(axis ?? 0,slot) }
    }
    if degree > 1 { return nil }
   }
   guard let axis else {
    let sign = try f.sign(of:law.terms.first?.coefficient ?? f.integer(0,using:&a),using:&a)
    certificates.append(.init(polynomial:law,incomingLaw:nil,quotient:nil,remainder:nil,assumptions:[],reductions:[],axis:nil,constant:sign)); continue
   }
   var certificate: ExactRealTopologySignInvariant<Base>? = nil
   let step = definition.steps[axis]
   for position in 0..<5 {
    try a.consumeWork(1)
    let incoming: Polynomial
    if position < 3 {
     guard let root = position == 0 ? step.section : position == 1 ? step.lower:step.upper else { continue }
     incoming = try p.importing(root.incomingLaw,using:&a)
     if try !constantLeading(incoming,axis:axis,&a) { continue }
    } else {
     let box = definition.partition.source.domains[axis]
     guard case .finite(let value) = position == 3 ? box.lower:box.upper else { continue }
     incoming = try p.subtracting(p.variable(axis,using:&a),p.constant(value,using:&a),using:&a)
    }
    let division = try p.divided(incoming,by:law,using:&a)
    var remainder = division.remainder
    try ExactTopologyAccess.storage(rawIndex,Int.self,&a)
    try ExactTopologyAccess.storage(rawIndex,ExactPolynomialDivision<Field>.self,&a)
    var assumptions: [Int] = [], reductions: [ExactPolynomialDivision<Field>] = []
    for instruction in instructions {
     try a.consumeWork(1)
     guard case .sign(let index,.equal) = instruction, index < rawIndex else { continue }
     if try p.isZero(remainder,using:&a) { break }
     let equality = atoms[index]
     var lower = true
     for term in equality.terms { for slot in axis..<n { try a.consumeWork(1); if term.powers[slot] != 0 { lower = false } } }
     if try !lower || p.isZero(p.importing(equality,using:&a),using:&a) { continue }
     let reduction = try p.divided(remainder,by:p.importing(equality,using:&a),using:&a)
     try counts.retain(reduction.quotient.depth,&a); try counts.retain(reduction.remainder.depth,&a)
     assumptions.append(index); reductions.append(reduction); remainder = reduction.remainder
    }
    if try !p.isZero(remainder,using:&a) { continue }
    try counts.retain(incoming.depth,&a); try counts.retain(division.quotient.depth,&a)
    certificate = .init(polynomial:law,incomingLaw:incoming,quotient:division.quotient,remainder:division.remainder,assumptions:assumptions,reductions:reductions,axis:axis,constant:nil); break
   }
   guard let certificate else { return nil }; certificates.append(certificate)
  }
  return certificates
 }
 func reusedRegion<A: ExactScalarAdmission & ~Copyable>(_ closure: ExactRealClosure<Base>, target: ExactRealClosure<Base>,
  certificate: [ExactRealTopologySignInvariant<Base>], cover: [ExactRealCellID<Base>], counts: inout ExactTopologyCounts, _ a: inout A) throws -> ExactRealTopologyRegion<Base> {
  let partition = closure.definition.partition
  let provider = try Cells(retaining:partition.source,using:&a)
  let sample = try provider.sample(of:target.definition.cell,in:partition,using:&a)
  let included = try certifiedTruth(closure.region.instructions,certificate:certificate,sample:sample,counts:&counts,&a)
  try counts.retain(sample.depth,&a)
  try ExactTopologyAccess.storage(cover.count,Bool.self,&a)
  var labels = Array(repeating:false,count:cover.count), found = false
  for index in cover.indices {
   try a.consumeWork(1)
   if cover[index] == target.definition.cell { labels[index] = included; found = true }
  }
  guard found else { throw ExactRealTopologyFailure.foreignReceipt }
  return .init(partition:partition,coordinateCount:closure.definition.coordinateCount,cells:cover,included:labels,
   excludesExterior:true,formulaAtoms:closure.region.formulaAtoms,signInvariants:certificate,certifiedTarget:target.definition.cell,reductions:[],eliminations:[],depth:counts.depth,
   decisions:[],quantifiers:[],instructions:closure.region.instructions)
 }
}
