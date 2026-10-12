#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
 func certifiedFactors<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, _ a: inout A) throws -> [ExactRealTopologyFactor<Base>] {
  let provider = try Cells(retaining:definition.partition.source,using:&a)
  let f = definition.coefficientField, n = definition.coordinateCount
  var result: [ExactRealTopologyFactor<Base>] = []
  let helper = try formula(field:f,free:n,quantifiers:[],&a)
  for step in definition.steps {
   for position in 0..<3 {
    try a.consumeWork(1)
    let root = position == 0 ? step.section : position == 1 ? step.lower:step.upper
    guard let root, try helper.affineLeading(root,&a) == nil else { continue }
    var found = false
    let p = try ExactPolynomialDomain(retaining:root.polynomial,using:&a)
    for lower in -1..<root.axis {
     if found { break }
     for plus in [false,true] {
      try a.consumeWork(1)
      if lower == -1 && plus { continue }
      let axis = try p.variable(root.axis,using:&a)
      let candidate: Polynomial
      if lower == -1 { candidate = axis }
      else {
       let other = try p.variable(lower,using:&a)
       candidate = plus ? try p.adding(axis,other,using:&a) : try p.subtracting(axis,other,using:&a)
      }
      let division = try p.divided(root.polynomial,by:candidate,using:&a)
      if try !p.isZero(division.remainder,using:&a) { continue }
      let prefix = try provider.sample(of:root.parent,in:definition.partition,using:&a)
      let sampleField = prefix.field
      try ExactTopologyAccess.storage(n,Field.Value.self,&a)
      var coordinates = prefix.coordinates
      coordinates.reserveCapacity(n)
      let value = lower == -1 ? try sampleField.integer(0,using:&a) : plus ? try sampleField.negated(prefix.coordinates[lower],using:&a) : prefix.coordinates[lower]
      coordinates.append(value)
      while coordinates.count < n { try a.consumeWork(1); coordinates.append(try sampleField.integer(0,using:&a)) }
      let q = try ExactPolynomialDomain(field:sampleField,variableCount:n,using:&a)
      var derivative = root.polynomial, valid = true
      for order in root.derivativeSigns.indices {
       let polynomial = try q.importing(derivative,using:&a)
       let evaluation = try q.evaluated(polynomial,at:coordinates,using:&a)
       if try sampleField.sign(of:evaluation.value,using:&a) != root.derivativeSigns[order] { valid = false; break }
       if order+1 < root.derivativeSigns.count { derivative = try p.differentiated(derivative,in:root.axis,using:&a) }
      }
      if !valid { continue }
      try ExactTopologyAccess.storage(ExactTopologyAccess.add(result.count,1),ExactRealTopologyFactor<Base>.self,&a)
      result.append(.init(boundary:root,factor:candidate,quotient:division.quotient,leading:.positive)); found = true; break
     }
    }
   }
  }
  return result
 }
}
