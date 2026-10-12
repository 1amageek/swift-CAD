#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
 func closedEquationExcluded<A: ExactScalarAdmission & ~Copyable>(_ source: ExactRealCellID<Base>, target: ExactRealCellID<Base>, _ a: inout A) throws -> Bool {
  let original = source.signs, other = target.signs
  guard original.count == other.count else { throw ExactRealTopologyFailure.invalidCoverage }
  for i in original.indices {
   try a.consumeWork(1)
   if original[i] == .zero && other[i] != .zero { return true }
  }
  return false
 }
 func cover<A: ExactScalarAdmission & ~Copyable>(_ partition: ExactRealCellPartition<Base>, _ a: inout A) throws -> [ExactRealCellID<Base>] {
  try ExactTopologyAccess.storage(partition.cells.count,ExactRealCellID<Base>.self,&a)
  var cells: [ExactRealCellID<Base>] = []; cells.reserveCapacity(partition.cells.count)
  for cell in partition.cells { try a.consumeWork(1); cells.append(cell) }
  return cells
 }
 func closedBox<A: ExactScalarAdmission & ~Copyable>(_ source: ExactRealCellSource<Base>, _ a: inout A) throws -> Bool {
  for domain in source.domains {
   try a.consumeWork(1)
   if case .finite = domain.lower, !domain.includesLower { return false }
   if case .finite = domain.upper, !domain.includesUpper { return false }
  }
  return true
 }
 func pointRegion<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, cover: [ExactRealCellID<Base>],
  target: ExactRealCellID<Base>, included: Bool, counts: inout ExactTopologyCounts, _ a: inout A) throws -> ExactRealTopologyRegion<Base> {
  try ExactTopologyAccess.storage(cover.count,Bool.self,&a)
  var labels = Array(repeating:false,count:cover.count), found = false
  for i in cover.indices { try a.consumeWork(1); if cover[i] == target { found = true; labels[i] = included } }
  guard definition.cell.dimension == 0, found else { throw ExactRealTopologyFailure.invalidCoverage }
  return .init(partition:definition.partition,coordinateCount:definition.coordinateCount,cells:cover,included:labels,
   excludesExterior:true,formulaAtoms:[],signInvariants:[],certifiedTarget:target,reductions:[],eliminations:[],depth:counts.depth,
   decisions:[],quantifiers:[],instructions:[])
 }
 func affineRegion<A: ExactScalarAdmission & ~Copyable>(_ definition: ExactRealCellDefinition<Base>, formula: ExactTopologyFormula<Base>,
  certificate: [ExactRealTopologySignInvariant<Base>], counts: inout ExactTopologyCounts, retainedCover: [ExactRealCellID<Base>]? = nil, _ a: inout A) throws -> ExactRealTopologyRegion<Base> {
  let partition = definition.partition, provider = try Cells(retaining:partition.source,using:&a)
  let cells = try retainedCover ?? cover(partition,&a)
  try ExactTopologyAccess.storage(cells.count,Bool.self,&a)
  var labels: [Bool] = []; labels.reserveCapacity(cells.count)
  for cell in cells {
   // Original equations vanish on the source and on every limit by continuity.
   // A proven nonzero target sign excludes it before any sample-field arithmetic.
   if try closedEquationExcluded(definition.cell,target:cell,&a) { labels.append(false); continue }
   let sample = try provider.sample(of:cell,in:partition,using:&a)
   labels.append(try certifiedTruth(formula.instructions,certificate:certificate,sample:sample,counts:&counts,sourceSigns:cell.signs,target:cell,&a))
  }
  return .init(partition:partition,coordinateCount:definition.coordinateCount,cells:cells,included:labels,
   excludesExterior:true,formulaAtoms:formula.atoms,signInvariants:certificate,certifiedTarget:nil,reductions:[],eliminations:[],depth:counts.depth,
   decisions:[],quantifiers:[],instructions:formula.instructions)
 }
 func certifiedTruth<A: ExactScalarAdmission & ~Copyable>(_ instructions: [ExactRealCellInstruction], certificate: [ExactRealTopologySignInvariant<Base>],
  sample: ExactRealCellSample<Base>, counts: inout ExactTopologyCounts, sourceSigns: [ExactSign]? = nil, target: ExactRealCellID<Base>? = nil, _ a: inout A) throws -> Bool {
  let field = sample.field
  try ExactTopologyAccess.storage(certificate.count,ExactSign.self,&a)
  var signs: [ExactSign] = []; signs.reserveCapacity(certificate.count)
  for proof in certificate {
   try a.consumeWork(1)
   for index in proof.assumptions {
    try a.consumeWork(1)
    guard index >= 0, index < signs.count else { throw ExactRealTopologyFailure.invalidCoverage }
    if signs[index] != .zero { return false }
   }
   if let constant = proof.constant { signs.append(constant); continue }
   if let projection = proof.projectionInvariant {
    guard let target else { throw ExactRealTopologyFailure.invalidCoverage }
    let provider = try Cells(retaining: projection.partition.source, using: &a)
    let projectedSign = try provider.sign(of: projection, at: target, using: &a)
    if !proof.projectionProvesSquare || projectedSign == .zero {
     signs.append(projectedSign); continue
    }
    guard projectedSign == .positive else { throw ExactRealTopologyFailure.invalidCoverage }
    // The certified positive square excludes zeros on this connected cell.
    // Exact sample evaluation now reads a proven constant affine sign.

   }
   if let index = proof.sourceLawIndex {
    guard let sourceSigns, index >= 0, index < sourceSigns.count,
     let orientation = proof.sourceLawOrientation, orientation != .zero else { throw ExactRealTopologyFailure.invalidCoverage }
    let original = sourceSigns[index]
    signs.append(orientation == .positive || original == .zero ? original : original == .positive ? .negative : .positive)
    continue
   }
   var value = try field.integer(0,using:&a)
   for term in proof.polynomial.terms {
    var product = try field.importing(term.coefficient,using:&a)
    for slot in term.powers.indices {
     try a.consumeWork(1)
     if term.powers[slot] != 0 {
      guard term.powers[slot] == 1 else { throw ExactRealTopologyFailure.invalidCoverage }
      product = try field.multiplying(product,sample.coordinates[slot],using:&a)
     }
    }
    value = try field.adding(value,product,using:&a)
   }
   try counts.retain(value.depth,&a); signs.append(try field.sign(of:value,using:&a))
  }
  return try truth(instructions,signs:signs,&a)
 }
}
