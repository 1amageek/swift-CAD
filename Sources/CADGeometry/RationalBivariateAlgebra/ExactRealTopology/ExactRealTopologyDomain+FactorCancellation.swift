#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
 func conjuncts<A: ExactScalarAdmission & ~Copyable>(_ f: ExactTopologyFormula<Base>, _ a: inout A) throws -> [(Int,ExactRealCellSignRelation)] {
  guard let end = f.conjunctionEnd else { throw ExactRealTopologyFailure.invalidFormula }
  try ExactTopologyAccess.storage(end,(Int,ExactRealCellSignRelation).self,&a)
  var atoms: [(Int,ExactRealCellSignRelation)] = []
  for item in f.instructions.prefix(end) {
   try a.consumeWork(1)
   switch item {
   case .sign(let index,let relation): atoms.append((index,relation))
   case .literal(true),.and: break
   default: throw ExactRealTopologyFailure.invalidFormula
   }
  }
  return atoms
 }
 func signedFactors<A: ExactScalarAdmission & ~Copyable>(_ input: ExactTopologyFormula<Base>, _ a: inout A) throws -> ExactTopologyFormula<Base> {
  var f = input
  guard f.conjunctionEnd != nil else { return f }
  let clauses = try conjuncts(f,&a), p = f.polynomials
  for variable in f.freeCount..<p.variableCount {
   var certificate: (Int,ExactSign)? = nil
   for (index,relation) in clauses {
    try a.consumeWork(1)
    let law = f.atoms[index]
    if relation != .greater && relation != .less { continue }
    if law.terms.count != 1 || law.terms[0].powers[variable] != 1 { continue }
    var valid = true
    for slot in law.terms[0].powers.indices { try a.consumeWork(1); if slot != variable && law.terms[0].powers[slot] != 0 { valid = false } }
    if !valid { continue }
    let c = try f.field.sign(of:law.terms[0].coefficient,using:&a)
    if c == .zero { throw ExactRealTopologyFailure.invalidFormula }
    certificate = (index,relation == .greater ? c : (c == .positive ? .negative:.positive)); break
   }
   guard let (certificateIndex,sign) = certificate else { continue }
   let originalAtoms = f.atoms
   var changed = false
   for (index,_) in clauses {
    try a.consumeWork(1)
    if index == certificateIndex { continue }
    let law = f.atoms[index]
    if law.terms.isEmpty { continue }
    var exponent = Int.max
    for term in law.terms { try a.consumeWork(1); exponent = min(exponent,term.powers[variable]) }
    if exponent == 0 { continue }
    try ExactTopologyAccess.storage(law.termCount,ExactPolynomialTerm<Field.Value>.self,&a)
    var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
    for term in law.terms {
     try ExactTopologyAccess.storage(p.variableCount,Int.self,&a); try a.consumeWork(p.variableCount)
     var powers = term.powers; powers[variable] -= exponent
     let coefficient = sign == .negative && exponent & 1 == 1 ? try f.field.negated(term.coefficient,using:&a) : term.coefficient
     terms.append(.init(powers:powers,coefficient:coefficient))
    }
    if !changed { try ExactTopologyAccess.storage(f.atoms.count,Polynomial.self,&a); changed = true }
    f.atoms[index] = try p.polynomial(terms:terms,using:&a)
   }
   if changed {
    try ExactTopologyAccess.storage(ExactTopologyAccess.add(f.reductions.count,1),ExactRealTopologyReduction<Base>.self,&a)
    f.reductions.append(.init(variable:variable,originalAtoms:originalAtoms,originalInstructions:f.instructions,
     derivedAtoms:f.atoms,derivedInstructions:f.instructions))
   }
  }
  return f
 }
}
