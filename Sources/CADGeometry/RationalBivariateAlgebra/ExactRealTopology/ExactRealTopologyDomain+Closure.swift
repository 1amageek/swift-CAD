#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain: ExactRealClosureProducing, ExactRealTopologyQuerying {
 func affine<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, through: Int, factors: [ExactRealTopologyFactor<Base>] = [], _ a: inout A) throws -> Bool {
  let f = try formula(field:definition.coefficientField,free:definition.coordinateCount,quantifiers:[],&a)
  for axis in 0..<through {
   try a.consumeWork(1)
   let step = definition.steps[axis]
   if let section = step.section, try f.factor(section,in:factors,&a) == nil && f.affineLeading(section,&a) == nil { return false }
   if let lower = step.lower, try f.factor(lower,in:factors,&a) == nil && f.affineLeading(lower,&a) == nil { return false }
   if let upper = step.upper, try f.factor(upper,in:factors,&a) == nil && f.affineLeading(upper,&a) == nil { return false }
  }
  return true
 }
 func boundedGraph<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, limits: ExactRealTopologyLimits,
  counts: inout ExactTopologyCounts, _ a: inout A) throws -> ExactRealTopologyRegion<Base>? {
  let n = definition.coordinateCount
  var base = 0
  for step in definition.steps { try a.consumeWork(1); if step.section == nil { base = step.axis + 1 } }
  guard base < n, try affine(definition,through:base,&a) else { return nil }
  for axis in base..<n {
   try a.consumeWork(1)
   guard let section = definition.steps[axis].section else { return nil }
   let law = section.polynomial
   var degree = 0
   for term in law.terms { try a.consumeWork(1); degree = max(degree,term.powers[axis]) }
   guard degree > 0 else { return nil }
   var constantLeading = false
   for term in law.terms {
    try a.consumeWork(1)
    if term.powers[axis] != degree { continue }
    try a.consumeWork(term.powers.count)
    for slot in term.powers.indices where slot != axis { if term.powers[slot] != 0 { return nil } }
    guard try definition.coefficientField.sign(of:term.coefficient,using:&a) != .zero else { throw ExactRealTopologyFailure.invalidDefinition }
    constantLeading = true
   }
   guard constantLeading else { return nil }
  }
  // Weak-base guards occur in the same complete decomposition as the weak graph.
  var f = try formula(field:definition.coefficientField,free:n,quantifiers:[],&a)
  let slots = try map(n,&a); var witness = n
  try f.cell(definition,map:slots,witness:&witness,weak:true,through:base,&a)
  let baseProgram = f.instructions
  try ExactTopologyAccess.storage(baseProgram.count,ExactRealCellInstruction.self,&a)
  try f.cell(definition,map:slots,witness:&witness,weak:true,&a); try f.instruction(.and,&a)
  guard witness == n else { throw ExactRealTopologyFailure.invalidFormula }
  let region = try reduce(f,limits:limits,counts:&counts,&a)
  // Every full child is visited. One section-only solution over every weak-base
  // prefix proves fiber uniqueness; no favorable representative grants it.
  for prefix in region.decisions {
   try a.consumeWork(1)
   if (prefix.cell.axis ?? -1) + 1 != base { continue }
   var baseTruth: Bool? = nil, solutions = 0
   for leaf in region.decisions {
    try a.consumeWork(1)
    if (leaf.cell.axis ?? -1) + 1 != n { continue }
    var ancestor = leaf.cell
    while (ancestor.axis ?? -1) + 1 > base {
     try a.consumeWork(1)
     guard let parent = ancestor.parent else { throw ExactRealTopologyFailure.invalidCoverage }; ancestor = parent
    }
    if ancestor != prefix.cell { continue }
    let b = try truth(baseProgram,signs:leaf.cell.signs,&a)
    if let known = baseTruth { guard b == known else { throw ExactRealTopologyFailure.invalidCoverage } } else { baseTruth = b }
    if leaf.truth {
     guard b else { throw ExactRealTopologyFailure.invalidCoverage }
     if leaf.cell.dimension != prefix.cell.dimension { return nil }
     solutions = try ExactTopologyAccess.add(solutions,1)
    }
   }
   guard let b = baseTruth else { throw ExactRealTopologyFailure.invalidCoverage }
   if b && solutions != 1 { return nil }
   if !b && solutions != 0 { throw ExactRealTopologyFailure.invalidCoverage }
  }
  return region
 }
 func issuedClosure<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: ExactRealCellPartition<Base>,
  strategy: ExactRealClosureStrategy, limits: ExactRealTopologyLimits, counts: inout ExactTopologyCounts, _ a: inout A) throws -> ExactRealClosure<Base> {
  try a.checkpoint(); try counts.retain(partition.depth,&a)
  let provider = try Cells(retaining:partition.source,using:&a)
  let definition = try provider.definition(of:cell,in:partition,using:&a)
  guard definition.coordinateCount == partition.source.variableCount else { throw ExactRealTopologyFailure.invalidDefinition }
  try counts.retain(definition.depth,&a)
  counts.closures = try ExactTopologyAccess.add(counts.closures,1)
  guard counts.closures <= limits.maximumClosures else { throw ExactRealTopologyFailure.closureLimit }
  let factors = strategy == .automatic ? try certifiedFactors(definition,&a) : []
  for certificate in factors { try counts.retain(certificate.factor.depth,&a); try counts.retain(certificate.quotient.depth,&a) }
  let proof: ExactRealClosureProof, region: ExactRealTopologyRegion<Base>
  var applicability: ExactRealTopologyRegion<Base>? = nil
  if strategy == .automatic && cell.dimension == 0 {
   proof = .point; region = try pointRegion(definition,cover:cover(partition,&a),target:cell,included:true,counts:&counts,&a)
  } else if try strategy == .automatic && affine(definition,through:definition.coordinateCount,factors:factors,&a) {
   proof = .affine
   let f = try direct(definition,weak:true,factors:factors,&a)
   if try closedBox(partition.source,&a), let certificate = try invariantAtoms(definition,atoms:f.atoms,instructions:f.instructions,quantifiers:f.quantifiers,counts:&counts,&a) {
    region = try affineRegion(definition,formula:f,certificate:certificate,counts:&counts,&a)
   } else { region = try reduce(f,limits:limits,counts:&counts,&a) }
  } else if strategy == .automatic, let graph = try boundedGraph(definition,limits:limits,counts:&counts,&a) {
   proof = .boundedSectionGraph; region = graph; applicability = graph
  } else if strategy == .automatic, let graph = try polynomialGraph(definition,limits:limits,counts:&counts,&a) {
   proof = .polynomialGraph; region = graph; applicability = graph
  } else {
   proof = .quantified; region = try reduce(neighborhood(definition,&a),limits:limits,counts:&counts,&a)
  }
  try a.checkpoint()
  return .init(definition:definition,factors:factors,proof:proof,region:region,applicability:applicability,depth:counts.depth)
 }
 public func closure<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  strategy: ExactRealClosureStrategy, limits: ExactRealTopologyLimits, using admission: inout A) throws(ExactRealTopologyFailure) -> ExactRealClosure<Base> {
  do {
   var counts = ExactTopologyCounts(depth:partition.depth)
   let result = try issuedClosure(of:cell,in:copy partition,strategy:strategy,limits:limits,counts:&counts,&admission)
   try admission.checkpoint(); return result
  } catch { throw .preserving(error) }
 }
 public func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>, in closure: borrowing ExactRealClosure<Base>,
  limits: ExactRealTopologyLimits, using admission: inout A) throws(ExactRealTopologyFailure) -> Bool {
  do {
   try admission.checkpoint(); try admission.admitDepth(value:closure.depth.value,coefficient:closure.depth.coefficient)
   guard point.coordinates.count == closure.region.coordinateCount else { throw ExactRealTopologyFailure.invalidDefinition }
   let provider = try Cells(retaining:closure.region.partition.source,using:&admission)
   guard let cell = try provider.locatePrefix(point,in:closure.region.partition,limits:.init(maximumRoots:limits.maximumRootsPerStack),using:&admission) else {
    guard closure.region.excludesExterior else { throw ExactRealTopologyFailure.invalidCoverage }
    try admission.checkpoint(); return false
   }
   for index in closure.region.cells.indices {
    try admission.consumeWork(1)
    if cell == closure.region.cells[index] { try admission.checkpoint(); return closure.region.included[index] }
   }
   throw ExactRealTopologyFailure.invalidCoverage
  } catch { throw .preserving(error) }
 }
}
