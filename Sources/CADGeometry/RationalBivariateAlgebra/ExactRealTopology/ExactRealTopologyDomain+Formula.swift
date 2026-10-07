#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
 func formula<A: ExactScalarAdmission & ~Copyable>(field: Field, free: Int, quantifiers: [Bool], _ a: inout A) throws -> ExactTopologyFormula<Base> {
  let n = try ExactTopologyAccess.add(free,quantifiers.count)
  let p = try ExactPolynomialDomain(field:field,variableCount:n,using:&a)
  return .init(field:field,polynomials:p,freeCount:free,quantifiers:quantifiers)
 }
 func map<A: ExactScalarAdmission & ~Copyable>(_ count: Int, offset: Int = 0, _ a: inout A) throws -> [Int] {
  try ExactTopologyAccess.storage(count,Int.self,&a); try a.consumeWork(count)
  let end = try ExactTopologyAccess.add(offset,count)
  return Array(offset..<end)
 }
 func witnesses<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, factors: [ExactRealTopologyFactor<Base>] = [], _ a: inout A) throws -> Int {
  let f = try formula(field:definition.coefficientField,free:definition.partition.source.variableCount,quantifiers:[],&a)
  var count = 0
  for step in definition.steps {
   try a.consumeWork(1)
   if step.section != nil { continue }
   if let lower = step.lower, try f.factor(lower,in:factors,&a) == nil && f.affineLeading(lower,&a) == nil { count = try ExactTopologyAccess.add(count,1) }
   if let upper = step.upper, try f.factor(upper,in:factors,&a) == nil && f.affineLeading(upper,&a) == nil { count = try ExactTopologyAccess.add(count,1) }
  }
  return count
 }
 func direct<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, weak: Bool, factors: [ExactRealTopologyFactor<Base>] = [], _ a: inout A) throws -> ExactTopologyFormula<Base> {
  let n = definition.coordinateCount, count = try witnesses(definition,factors:factors,&a)
  try ExactTopologyAccess.storage(count,Bool.self,&a)
  var f = try formula(field:definition.coefficientField,free:n,quantifiers:Array(repeating:true,count:count),&a)
  var witness = n
  try f.cell(definition,map:map(definition.partition.source.variableCount,&a),witness:&witness,weak:weak,factors:factors,&a)
  guard witness == f.polynomials.variableCount else { throw ExactRealTopologyFailure.invalidFormula }
  return f
 }
 func neighborhood<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, _ a: inout A) throws -> ExactTopologyFormula<Base> {
  let n = definition.coordinateCount, count = try witnesses(definition,&a)
  let suffix = try ExactTopologyAccess.add(ExactTopologyAccess.add(n,1),count)
  try ExactTopologyAccess.storage(suffix,Bool.self,&a)
  var quantifiers = Array(repeating:true,count:suffix); quantifiers[0] = false
  var f = try formula(field:definition.coefficientField,free:n,quantifiers:quantifiers,&a)
  let qOffset = try ExactTopologyAccess.add(n,1)
  var witness = try ExactTopologyAccess.add(qOffset,n)
  try f.cell(definition,map:map(n,offset:qOffset,&a),witness:&witness,weak:false,&a)
  let epsilon = try f.polynomials.variable(n,using:&a)
  for axis in 0..<n {
   let delta = try f.polynomials.subtracting(f.polynomials.variable(axis,using:&a),f.polynomials.variable(qOffset + axis,using:&a),using:&a)
   try f.atom(f.polynomials.adding(delta,epsilon,using:&a),.greater,&a); try f.instruction(.and,&a)
   try f.atom(f.polynomials.subtracting(epsilon,delta,using:&a),.greater,&a); try f.instruction(.and,&a)
  }
  f.conjunctionEnd = f.instructions.count
  try f.atom(epsilon,.lessOrEqual,&a); try f.instruction(.or,&a)
  guard witness == f.polynomials.variableCount else { throw ExactRealTopologyFailure.invalidFormula }
  return try eliminateEqualities(f,&a)
 }
}
