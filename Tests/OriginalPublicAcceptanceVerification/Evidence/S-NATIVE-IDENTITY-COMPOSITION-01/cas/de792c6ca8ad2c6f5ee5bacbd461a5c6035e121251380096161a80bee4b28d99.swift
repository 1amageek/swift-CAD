#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
 func polynomialGraph<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, limits: ExactRealTopologyLimits,
  counts: inout ExactTopologyCounts, _ a: inout A) throws -> ExactRealTopologyRegion<Base>? {
  let n = definition.coordinateCount
  let direct = try self.direct(definition,weak:false,&a)
  // A graph normalization removes original coordinate slots only. Root witnesses
  // would require a separate image/properness proof and are deliberately refused.
  if !direct.quantifiers.isEmpty { return nil }
  try ExactTopologyAccess.storage(n,Bool.self,&a)
  var existential = ExactTopologyFormula(field:direct.field,polynomials:direct.polynomials,freeCount:0,quantifiers:Array(repeating:true,count:n))
  existential.atoms = direct.atoms; existential.instructions = direct.instructions
  existential.conjunctionEnd = direct.instructions.count
  let reduced = try signedFactors(eliminateEqualities(existential,&a),&a)
  if reduced.eliminations.isEmpty { return nil }
  for atom in reduced.atoms {
   for term in atom.terms {
    var degree = 0
    for power in term.powers { try a.consumeWork(1); degree = try ExactTopologyAccess.add(degree,power) }
    if degree > 1 { return nil }
   }
  }
  let clauses = try conjuncts(reduced,&a)
  var f = try formula(field:definition.coefficientField,free:n,quantifiers:[],&a)
  try f.instruction(.literal(true),&a)
  var remaining = try map(n,&a)
  for elimination in reduced.eliminations {
   try a.consumeWork(1)
   let law = elimination.originalAtoms[elimination.equality]
   try f.atom(f.remap(law,remaining,&a),.equal,&a); try f.instruction(.and,&a)
   guard elimination.variable >= 0, elimination.variable < remaining.count else { throw ExactRealTopologyFailure.invalidFormula }
   try ExactTopologyAccess.storage(remaining.count-1,Int.self,&a)
   var next: [Int] = []; next.reserveCapacity(remaining.count-1)
   for i in remaining.indices { try a.consumeWork(1); if i != elimination.variable { next.append(remaining[i]) } }
   remaining = next
  }
  guard remaining.count == reduced.polynomials.variableCount else { throw ExactRealTopologyFailure.invalidFormula }
  for (index,relation) in clauses {
   let weak: ExactRealCellSignRelation
   switch relation {
   case .greater: weak = .greaterOrEqual
   case .less: weak = .lessOrEqual
   case .notEqual: return nil
   default: weak = relation
   }
   try f.atom(f.remap(reduced.atoms[index],remaining,&a),weak,&a); try f.instruction(.and,&a)
  }
  f.eliminations = reduced.eliminations; f.reductions = reduced.reductions
  return try reduce(f,limits:limits,counts:&counts,&a)
 }
}
