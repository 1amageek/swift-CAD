#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
 func eliminateEqualities<A: ExactScalarAdmission & ~Copyable>(_ input: ExactTopologyFormula<Base>, _ a: inout A) throws -> ExactTopologyFormula<Base> {
  var result = input
  while let end = result.conjunctionEnd {
   let n = result.polynomials.variableCount, p = result.polynomials, f = result.field
   var selected: (Int,Int,Field.Value)? = nil
   for variable in (result.freeCount..<n).reversed() {
    try a.consumeWork(1)
    if !result.quantifiers[variable-result.freeCount] { continue }
    // Only the final existential block may be eliminated.
    if result.quantifiers[(variable-result.freeCount)...].contains(false) { continue }
    for instruction in result.instructions.prefix(end) {
     try a.consumeWork(1)
     guard case .sign(let index,.equal) = instruction else { continue }
     var leading: Field.Value? = nil, valid = true
     for term in result.atoms[index].terms {
      try a.consumeWork(term.powers.count)
      if term.powers[variable] == 0 { continue }
      if term.powers[variable] != 1 { valid = false; break }
      for slot in term.powers.indices where slot != variable { if term.powers[slot] != 0 { valid = false } }
      leading = term.coefficient
     }
     if valid, let leading, try f.sign(of:leading,using:&a) != .zero { selected = (variable,index,leading); break }
    }
    if selected != nil { break }
   }
   guard let (variable,equality,leading) = selected else { return result }
   let law = result.atoms[equality]
   let axis = try p.variable(variable,using:&a)
   let remainder = try p.subtracting(law,p.multiplying(p.constant(leading,using:&a),axis,using:&a),using:&a)
   let inverse = try f.dividing(f.integer(-1,using:&a),leading,using:&a)
   let replacement = try p.multiplying(p.constant(inverse,using:&a),remainder,using:&a)
   try ExactTopologyAccess.storage(n,Polynomial.self,&a)
   var replacements: [Polynomial] = []; replacements.reserveCapacity(n)
   for slot in 0..<n { try a.consumeWork(1); replacements.append(slot == variable ? replacement : try p.variable(slot,using:&a)) }
   try ExactTopologyAccess.storage(result.quantifiers.count-1,Bool.self,&a)
   var quantifiers: [Bool] = []; quantifiers.reserveCapacity(result.quantifiers.count-1)
   for index in result.quantifiers.indices { try a.consumeWork(1); if index != variable-result.freeCount { quantifiers.append(result.quantifiers[index]) } }
   var next = try formula(field:f,free:result.freeCount,quantifiers:quantifiers,&a)
   try ExactTopologyAccess.storage(n,Int.self,&a)
   var slotMap = Array(repeating:-1,count:n)
   for slot in 0..<n { try a.consumeWork(1); if slot != variable { slotMap[slot] = slot < variable ? slot:slot-1 } }
   try ExactTopologyAccess.storage(result.atoms.count,Polynomial.self,&a)
   next.atoms.reserveCapacity(result.atoms.count)
   for atom in result.atoms {
    let substituted = try p.substituted(atom,with:replacements,using:&a)
    try ExactTopologyAccess.storage(substituted.termCount,ExactPolynomialTerm<Field.Value>.self,&a)
    var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(substituted.termCount)
    for term in substituted.terms {
     guard term.powers[variable] == 0 else { throw ExactRealTopologyFailure.invalidFormula }
     try ExactTopologyAccess.storage(n-1,Int.self,&a)
     var powers: [Int] = []; powers.reserveCapacity(n-1)
     for slot in 0..<n { try a.consumeWork(1); if slot != variable { powers.append(term.powers[slot]) } }
     terms.append(.init(powers:powers,coefficient:term.coefficient))
    }
    next.atoms.append(try next.polynomials.polynomial(terms:terms,using:&a))
   }
   next.instructions = result.instructions; next.conjunctionEnd = end
   try ExactTopologyAccess.storage(ExactTopologyAccess.add(result.eliminations.count,1),ExactRealTopologyElimination<Base>.self,&a)
   next.reductions = result.reductions
   next.eliminations = result.eliminations
   next.eliminations.append(.init(variable:variable,equality:equality,originalAtoms:result.atoms,originalInstructions:result.instructions,
    replacement:replacement,variableMap:slotMap))
   result = next
  }
  return result
 }
}
