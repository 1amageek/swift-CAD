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
  return try reduce(f,limits:limits,counts:&counts,&a)
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
   try ExactTopologyAccess.storage(n,ExactRealClosure<Base>.self,&admission)
   var closures: [ExactRealClosure<Base>] = []; closures.reserveCapacity(n)
   for cell in cells {
    try admission.consumeWork(1)
    closures.append(try issuedClosure(of:cell,in:partition,strategy:strategy,limits:limits,counts:&counts,&admission))
   }
   try ExactTopologyAccess.storage(n,[ExactRealTopologySignInvariant<Base>]?.self,&admission)
   var certificates: [[ExactRealTopologySignInvariant<Base>]?] = []; certificates.reserveCapacity(n)
   for closure in closures { certificates.append(try invariantAtoms(closure.definition,atoms:closure.region.formulaAtoms,instructions:closure.region.instructions,quantifiers:closure.region.quantifiers,counts:&counts,&admission)) }
   try ExactTopologyAccess.storage(partition.cells.count,ExactRealCellID<Base>.self,&admission)
   var cover: [ExactRealCellID<Base>] = []; cover.reserveCapacity(partition.cells.count)
   for cell in partition.cells { try admission.consumeWork(1); cover.append(cell) }
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
     if closures[i].proof == .point {
      result = try pointRegion(closures[i].definition,cover:cover,target:cells[j],included:false,counts:&counts,&admission)
     } else if let certificate = certificates[i] {
      result = try reusedRegion(closures[i],target:closures[j],certificate:certificate,cover:cover,counts:&counts,&admission)
     } else { result = try intersection(closures[i],target:closures[j],limits:limits,counts:&counts,&admission) }
     region = result
     for index in result.cells.indices {
      try admission.consumeWork(1)
      if !result.included[index] { continue }
      counts.pieces = try ExactTopologyAccess.add(counts.pieces,1)
      guard counts.pieces <= limits.maximumAttachmentPieces else { throw ExactRealTopologyFailure.attachmentLimit }
      try ExactTopologyAccess.storage(ExactTopologyAccess.add(attachments.count,1),ExactRealAttachment<Base>.self,&admission)
      attachments.append(.init(source:cells[i],target:cells[j],closure:closures[i],region:result,piece:result.cells[index]))
     }
    }
    pairs.append(.init(source:cells[i],target:cells[j],region:region,attachments:start..<attachments.count))
   } }
   guard pairs.count == pairCount, closures.count == n else { throw ExactRealTopologyFailure.invalidCoverage }
   try admission.checkpoint()
   return .init(selection:copy selection,closures:closures,pairs:pairs,attachments:attachments,depth:counts.depth)
  } catch { throw .preserving(error) }
 }
}
