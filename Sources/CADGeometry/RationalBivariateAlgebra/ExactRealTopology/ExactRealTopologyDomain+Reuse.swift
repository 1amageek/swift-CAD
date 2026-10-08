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
 func invariantAtoms<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, atoms: [Polynomial], instructions: [ExactRealCellInstruction], quantifiers: [Bool], counts: inout ExactTopologyCounts, sourceSigns: Bool = false, projectionSigns: Bool = false, _ a: inout A) throws -> [ExactRealTopologySignInvariant<Base>]? {
  if !quantifiers.isEmpty { return nil }
  let f = definition.coefficientField, n = definition.coordinateCount
  let p = try ExactPolynomialDomain(field:f,variableCount:n,using:&a)
  try ExactTopologyAccess.storage(atoms.count,ExactRealTopologySignInvariant<Base>.self,&a)
  var certificates: [ExactRealTopologySignInvariant<Base>] = []; certificates.reserveCapacity(atoms.count)
  for rawIndex in atoms.indices {
   let raw = atoms[rawIndex]
   let law = try p.importing(raw,using:&a)
   if sourceSigns, let certificate = try sourceSignInvariant(law, definition: definition, p: p, counts: &counts, &a) {
    certificates.append(certificate); continue
   }
   if projectionSigns {
    let provider = try Cells(retaining: definition.partition.source, using: &a)
    if let proof = try provider.signInvariant(for: law, in: definition.partition, using: &a) {
     try counts.retain(proof.depth, &a)
     certificates.append(.init(polynomial: law, incomingLaw: nil,
      quotient: nil, remainder: nil, assumptions: [], reductions: [],
      axis: proof.axis, constant: nil, projectionInvariant: proof))
     continue
    }
   }
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
   if projectionSigns {
    let provider = try Cells(retaining: definition.partition.source, using: &a)
    let square = try p.multiplying(law, law, using: &a)
    if let proof = try provider.signInvariant(for: square, in: definition.partition, using: &a) {
     try counts.retain(square.depth, &a); try counts.retain(proof.depth, &a)
     certificates.append(.init(polynomial: law, incomingLaw: nil,
      quotient: nil, remainder: nil, assumptions: [], reductions: [],
      axis: axis, constant: nil, projectionInvariant: proof, projectionProvesSquare: true))
     continue
    }
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
 func sourceSignInvariant<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial,
  definition: ExactRealCellDefinition<Base>, p: ExactPolynomialDomain<Field>,
  counts: inout ExactTopologyCounts, _ a: inout A) throws -> ExactRealTopologySignInvariant<Base>? {
  if try p.isZero(law, using: &a) { return nil }
  let original = definition.partition.source.polynomials
  for index in original.indices {
   try a.consumeWork(1)
   let incoming = try p.importing(original[index], using: &a)
   let division = try p.divided(incoming, by: law, using: &a)
   if try !p.isZero(division.remainder, using: &a) { continue }
   guard division.quotient.termCount == 1 else { continue }
   let term = division.quotient.terms[0]
   var constant = true
   for power in term.powers { try a.consumeWork(1); if power != 0 { constant = false } }
   if !constant { continue }
   let sign = try definition.coefficientField.sign(of: term.coefficient, using: &a)
   guard sign != .zero else { continue }
   try counts.retain(incoming.depth, &a); try counts.retain(division.quotient.depth, &a)
   try counts.retain(division.remainder.depth, &a)
   return .init(polynomial: law, incomingLaw: incoming, quotient: division.quotient,
    remainder: division.remainder, assumptions: [], reductions: [], axis: nil,
    constant: nil, sourceLawIndex: index, sourceLawOrientation: sign)
  }
  return nil
 }
}
