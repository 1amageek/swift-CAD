#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactTopologyFormula {
 func factor<A: ExactScalarAdmission & ~Copyable>(_ root: ExactRealCellBoundaryRoot<Base>, in factors: [ExactRealTopologyFactor<Base>], _ a: inout A) throws -> ExactRealTopologyFactor<Base>? {
  for certificate in factors {
   try a.consumeWork(1)
   let b = certificate.boundary
   if b.parent == root.parent && b.axis == root.axis && b.rootOrdinal == root.rootOrdinal { return certificate }
  }
  return nil
 }
 mutating func instruction<A: ExactScalarAdmission & ~Copyable>(_ item: ExactRealCellInstruction, _ a: inout A) throws {
  try a.consumeWork(1)
  // Conservative growth/COW admission before native buffer mutation.
  try ExactTopologyAccess.storage(ExactTopologyAccess.add(instructions.count,1),ExactRealCellInstruction.self,&a)
  instructions.append(item)
 }
 mutating func atom<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, _ relation: ExactRealCellSignRelation, _ a: inout A) throws {
  try ExactTopologyAccess.storage(ExactTopologyAccess.add(atoms.count,1),Polynomial.self,&a)
  let index = atoms.count; atoms.append(law)
  try instruction(.sign(polynomial:index,relation:relation),&a)
 }
 func remap<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, _ map: [Int], _ a: inout A) throws -> Polynomial {
  guard map.count == law.variableCount else { throw ExactRealTopologyFailure.invalidFormula }
  try a.admitDepth(value:law.depth.value,coefficient:law.depth.coefficient)
  try ExactTopologyAccess.storage(polynomials.variableCount,Bool.self,&a)
  var used = Array(repeating:false,count:polynomials.variableCount)
  for slot in map {
   try a.consumeWork(1)
   guard slot >= 0, slot < used.count, !used[slot] else { throw ExactRealTopologyFailure.invalidFormula }
   used[slot] = true
  }
  try ExactTopologyAccess.storage(law.termCount,ExactPolynomialTerm<Field.Value>.self,&a)
  var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
  for term in law.terms {
   try ExactTopologyAccess.storage(polynomials.variableCount,Int.self,&a)
   var powers = Array(repeating:0,count:polynomials.variableCount)
   for i in map.indices { try a.consumeWork(1); powers[map[i]] = term.powers[i] }
   terms.append(.init(powers:powers,coefficient:try field.importing(term.coefficient,using:&a)))
  }
  return try polynomials.polynomial(terms:terms,using:&a)
 }
 func affineLeading<A: ExactScalarAdmission & ~Copyable>(_ root: ExactRealCellBoundaryRoot<Base>, _ a: inout A) throws -> ExactSign? {
  var leading: Field.Value? = nil
  for term in root.polynomial.terms {
   var degree = 0
   for power in term.powers { try a.consumeWork(1); degree = try ExactTopologyAccess.add(degree,power) }
   if degree > 1 { return nil }
   if term.powers[root.axis] == 1 { leading = term.coefficient }
  }
  guard let leading else { return nil }
  let sign = try field.sign(of:leading,using:&a)
  guard sign != .zero else { throw ExactRealTopologyFailure.invalidDefinition }
  return sign
 }
 static func relation(_ sign: ExactSign, weak: Bool) -> ExactRealCellSignRelation {
  switch sign {
  case .zero: return .equal
  case .negative: return weak ? .lessOrEqual : .less
  case .positive: return weak ? .greaterOrEqual : .greater
  }
 }
 mutating func signature<A: ExactScalarAdmission & ~Copyable>(_ root: ExactRealCellBoundaryRoot<Base>, map: [Int], weak: Bool, _ a: inout A) throws {
  var law = root.polynomial
  let original = try ExactPolynomialDomain(field:field,variableCount:root.polynomial.variableCount,using:&a)
  // Differentiate through an explicitly imported original-field owner.
  law = try original.importing(law,using:&a)
  for order in root.derivativeSigns.indices {
   try atom(remap(law,map,&a),Self.relation(root.derivativeSigns[order],weak:weak),&a)
   try instruction(.and,&a)
   if order + 1 < root.derivativeSigns.count { law = try original.differentiated(law,in:root.axis,using:&a) }
  }
 }
 mutating func cell<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, map: [Int],
  witness: inout Int, weak: Bool, through: Int? = nil, factors: [ExactRealTopologyFactor<Base>] = [], _ a: inout A) throws {
  let count = through ?? definition.coordinateCount
  guard count >= 0, count <= definition.coordinateCount, map.count == definition.partition.source.variableCount else { throw ExactRealTopologyFailure.invalidFormula }
  try instruction(.literal(true),&a)
  for axis in 0..<count {
   try a.consumeWork(1)
   let step = definition.steps[axis]
   if let section = step.section {
    if let certificate = try factor(section,in:factors,&a) {
     try atom(remap(certificate.factor,map,&a),.equal,&a); try instruction(.and,&a)
    } else if try affineLeading(section,&a) != nil {
     try atom(remap(section.polynomial,map,&a),.equal,&a); try instruction(.and,&a)
    } else { try signature(section,map:map,weak:weak,&a) }
   } else {
    for isLower in [true,false] {
     guard let root = isLower ? step.lower : step.upper else { continue }
     if let certificate = try factor(root,in:factors,&a) {
      let sign: ExactSign = isLower ? certificate.leading : (certificate.leading == .positive ? .negative:.positive)
      try atom(remap(certificate.factor,map,&a),Self.relation(sign,weak:weak),&a); try instruction(.and,&a)
     } else if let leading = try affineLeading(root,&a) {
      let sign: ExactSign = isLower ? leading : (leading == .positive ? .negative : .positive)
      try atom(remap(root.polynomial,map,&a),Self.relation(sign,weak:weak),&a); try instruction(.and,&a)
     } else {
      let slot = witness; witness = try ExactTopologyAccess.add(witness,1)
      guard slot < polynomials.variableCount else { throw ExactRealTopologyFailure.invalidFormula }
      try ExactTopologyAccess.storage(map.count,Int.self,&a)
      var rootMap = map; rootMap[axis] = slot
      try signature(root,map:rootMap,weak:weak,&a)
      let delta = try polynomials.subtracting(polynomials.variable(map[axis],using:&a),polynomials.variable(slot,using:&a),using:&a)
      try atom(delta,Self.relation(isLower ? .positive:.negative,weak:weak),&a); try instruction(.and,&a)
     }
    }
   }
   let box = definition.partition.source.domains[axis]
   for isLower in [true,false] {
    let bound = isLower ? box.lower : box.upper
    if case .finite(let value) = bound {
     let delta = try polynomials.subtracting(polynomials.variable(map[axis],using:&a),polynomials.constant(value,using:&a),using:&a)
     let included = isLower ? box.includesLower : box.includesUpper
     try atom(delta,Self.relation(isLower ? .positive:.negative,weak:weak || included),&a); try instruction(.and,&a)
    }
   }
  }
 }
}
