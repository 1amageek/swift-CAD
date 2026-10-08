#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain: ExactRealIncidenceProducing {
 func intersection<A: ExactScalarAdmission & ~Copyable>(_ closure: ExactRealClosure<Base>, target: ExactRealClosure<Base>,
  limits: ExactRealTopologyLimits, counts: inout ExactTopologyCounts, _ a: inout A) throws -> ExactRealTopologyRegion<Base> {
  let original = closure.region, extra = try witnesses(target.definition,factors:target.factors,&a)
  let oldCount = original.partition.source.variableCount
  let suffix = try ExactTopologyAccess.add(original.quantifiers.count,extra)
  try ExactTopologyAccess.storage(suffix,Bool.self,&a)
  var quantifiers = original.quantifiers
  quantifiers.reserveCapacity(suffix)
  for _ in 0..<extra { try a.consumeWork(1); quantifiers.append(true) }
  var f = try formula(field:target.definition.coefficientField,free:original.coordinateCount,quantifiers:quantifiers,&a)
  let slots = try map(oldCount,&a)
  try ExactTopologyAccess.storage(original.instructions.count,ExactRealCellInstruction.self,&a)
  f.instructions = original.instructions
  try ExactTopologyAccess.storage(original.formulaAtoms.count,Polynomial.self,&a)
  f.atoms.reserveCapacity(original.formulaAtoms.count)
  for atom in original.formulaAtoms { try a.consumeWork(1); f.atoms.append(try f.remap(atom,slots,&a)) }
  var witness = oldCount
  try f.cell(target.definition,map:map(target.definition.coordinateCount,&a),witness:&witness,weak:false,factors:target.factors,&a)
  try f.instruction(.and,&a)
  guard witness == f.polynomials.variableCount else { throw ExactRealTopologyFailure.invalidFormula }
  // Intersection is restricted by the strict target, so its original domain
  // may bound a quantifier-free reduction without discarding any attachment.
  let targetDomains = f.quantifiers.isEmpty ? target.definition.partition.source.domains : nil
  return try reduce(f,limits:limits,counts:&counts,domains:targetDomains,&a)
 }
 func appendAttachment<A: ExactScalarAdmission & ~Copyable>(source: ExactRealCellID<Base>, target: ExactRealCellID<Base>,
  closure: ExactRealClosure<Base>, region: ExactRealTopologyRegion<Base>, piece: ExactRealCellID<Base>,
  limits: ExactRealTopologyLimits, counts: inout ExactTopologyCounts, attachments: inout [ExactRealAttachment<Base>], _ a: inout A) throws {
  counts.pieces = try ExactTopologyAccess.add(counts.pieces,1)
  guard counts.pieces <= limits.maximumAttachmentPieces else { throw ExactRealTopologyFailure.attachmentLimit }
  try ExactTopologyAccess.storage(ExactTopologyAccess.add(attachments.count,1),ExactRealAttachment<Base>.self,&a)
  attachments.append(.init(source:source,target:target,closure:closure,region:region,piece:piece))
 }
 public func incidence<A: ExactScalarAdmission & ~Copyable>(of selection: borrowing ExactRealCellSelection<Base>, strategy: ExactRealClosureStrategy,
  limits: ExactRealTopologyLimits, using admission: inout A) throws(ExactRealTopologyFailure) -> ExactRealIncidence<Base> {
  do {
   try admission.checkpoint()
   var counts = ExactTopologyCounts(depth:selection.depth)
   try counts.retain(selection.depth,&admission)
   let partition = selection.partition, cells = selection.cells, n = cells.count
   let provider = try Cells(retaining:partition.source,using:&admission)
   // The retained selection validates source ownership even when it is empty.
   _ = try provider.coefficientField(of:selection.predicate.source,using:&admission)
   if strategy == .automatic, let refined = try affineFactorIncidence(selection, limits: limits, counts: &counts, &admission) {
    try admission.checkpoint(); return refined
   }
   let cover = try self.cover(partition,&admission)
   try ExactTopologyAccess.storage(n,Int.self,&admission)
   var targets: [Int] = []; targets.reserveCapacity(n)
   for cell in cells {
    var ordinal: Int? = nil
    for index in cover.indices { try admission.consumeWork(1); if cover[index] == cell { ordinal = index; break } }
    guard let ordinal else { throw ExactRealTopologyFailure.foreignReceipt }
    targets.append(ordinal)
   }
   try ExactTopologyAccess.storage(n,ExactRealClosure<Base>.self,&admission)
   var closures: [ExactRealClosure<Base>] = []; closures.reserveCapacity(n)
   for cell in cells {
    try admission.consumeWork(1)
    closures.append(try issuedClosure(of:cell,in:partition,strategy:strategy,limits:limits,counts:&counts,retainedCover:cover,&admission))
   }
   try ExactTopologyAccess.storage(n,Bool.self,&admission)
   try ExactTopologyAccess.storage(n,[ExactRealTopologySignInvariant<Base>]?.self,&admission)
   var originalCovers: [Bool] = []; originalCovers.reserveCapacity(n)
   var certificates: [[ExactRealTopologySignInvariant<Base>]?] = []; certificates.reserveCapacity(n)
   for closure in closures {
    try admission.consumeWork(1)
    let region = closure.region
    var same = region.coordinateCount == partition.source.variableCount && region.cells.count == cover.count
    guard region.included.count == region.cells.count else { throw ExactRealTopologyFailure.invalidCoverage }
    if same {
     for index in cover.indices { try admission.consumeWork(1); if region.cells[index] != cover[index] { same = false; break } }
    }
    originalCovers.append(same)
    // Complete issued labels already prove whole-cell truth on this exact cover.
    certificates.append(same ? nil : try invariantAtoms(closure.definition,atoms:region.formulaAtoms,instructions:region.instructions,quantifiers:region.quantifiers,counts:&counts,&admission))
   }
   try ExactTopologyAccess.storage(cover.count,Bool.self,&admission)
   try admission.consumeWork(cover.count)
   let excluded = Array(repeating:false,count:cover.count)
   try ExactTopologyAccess.storage(n,[Bool]?.self,&admission)
   try admission.consumeWork(n)
   var targetMasks = Array<[Bool]?>(repeating:nil,count:n)
   let pairCount = try ExactTopologyAccess.multiply(n,n)
   try ExactTopologyAccess.storage(pairCount,ExactRealIncidencePair<Base>.self,&admission)
   var pairs: [ExactRealIncidencePair<Base>] = []; pairs.reserveCapacity(pairCount)
   var attachments: [ExactRealAttachment<Base>] = []
   for i in 0..<n { for j in 0..<n {
    try admission.consumeWork(1)
    let start = attachments.count
    let region: ExactRealTopologyRegion<Base>?
    if i == j { region = nil }
    else {
     let result: ExactRealTopologyRegion<Base>
     let wholeTarget: Bool?
     if originalCovers[i] {
      wholeTarget = closures[i].region.included[targets[j]]
     } else if let certificate = certificates[i] {
      let sample = try provider.sample(of:cells[j],in:partition,using:&admission)
      wholeTarget = try certifiedTruth(closures[i].region.instructions,certificate:certificate,sample:sample,counts:&counts,&admission)
      try counts.retain(sample.depth,&admission)
     } else { wholeTarget = nil }
     if let included = wholeTarget {
      let labels: [Bool]
      if included {
       if targetMasks[j] == nil {
        // The first mutation makes one admitted COW copy; published masks are immutable.
        try ExactTopologyAccess.storage(cover.count,Bool.self,&admission)
        try admission.consumeWork(cover.count)
        var mask = excluded; mask[targets[j]] = true; targetMasks[j] = mask
       }
       labels = targetMasks[j]!
      } else { labels = excluded }
      let original = closures[i].region
      result = .init(partition:partition,coordinateCount:partition.source.variableCount,cells:cover,included:labels,
       excludesExterior:true,formulaAtoms:original.formulaAtoms,signInvariants:certificates[i] ?? original.signInvariants,
       certifiedTarget:cells[j],reductions:original.reductions,eliminations:original.eliminations,depth:counts.depth,
       decisions:[],quantifiers:[],instructions:original.instructions)
      if included {
       try appendAttachment(source:cells[i],target:cells[j],closure:closures[i],region:result,piece:cells[j],
        limits:limits,counts:&counts,attachments:&attachments,&admission)
      }
     } else {
      result = try intersection(closures[i],target:closures[j],limits:limits,counts:&counts,&admission)
      for index in result.cells.indices {
       try admission.consumeWork(1)
       if result.included[index] {
        try appendAttachment(source:cells[i],target:cells[j],closure:closures[i],region:result,piece:result.cells[index],
         limits:limits,counts:&counts,attachments:&attachments,&admission)
       }
      }
     }
     region = result
    }
    pairs.append(.init(source:cells[i],target:cells[j],region:region,attachments:start..<attachments.count))
   } }
   guard pairs.count == pairCount, closures.count == n else { throw ExactRealTopologyFailure.invalidCoverage }
   try admission.checkpoint()
   return .init(selection:copy selection,closures:closures,pairs:pairs,attachments:attachments,depth:counts.depth)
  } catch { throw .preserving(error) }
 }
}
