#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain: ExactRealComponentsProducing {
 func representative<A: ExactScalarAdmission & ~Copyable>(_ input: Int, forest: inout [Int], _ a: inout A) throws -> Int {
  var current = input
  while true {
   try a.consumeWork(1)
   let next = forest[current]
   if next == current { break }; current = next
  }
  var path = input
  while path != current {
   try a.consumeWork(1)
   let next = forest[path]; forest[path] = current; path = next
  }
  return current
 }
 public func components<A: ExactScalarAdmission & ~Copyable>(of incidence: borrowing ExactRealIncidence<Base>, limits: ExactRealTopologyLimits,
  using admission: inout A) throws(ExactRealTopologyFailure) -> ExactRealComponents<Base> {
  do {
   try admission.checkpoint(); try admission.admitDepth(value:incidence.depth.value,coefficient:incidence.depth.coefficient)
   let cells = incidence.selection.cells, n = cells.count
   guard incidence.closures.count == n, incidence.pairs.count == (try ExactTopologyAccess.multiply(n,n)) else { throw ExactRealTopologyFailure.invalidCoverage }
   try ExactTopologyAccess.storage(ExactTopologyAccess.multiply(n,4),Int.self,&admission)
   var forest = Array(0..<n), sizes = Array(repeating:1,count:n), labels = Array(repeating:-1,count:n), roots: [Int] = []
   roots.reserveCapacity(n)
   for i in 0..<n { for j in 0..<n {
    try admission.consumeWork(1)
    let pair = incidence.pairs[i*n+j]
    guard pair.source == cells[i], pair.target == cells[j] else { throw ExactRealTopologyFailure.foreignReceipt }
    if pair.attachments.isEmpty { continue }
    var x = try representative(i,forest:&forest,&admission), y = try representative(j,forest:&forest,&admission)
    if x == y { continue }
    if sizes[x] < sizes[y] { swap(&x,&y) }
    forest[y] = x; sizes[x] = try ExactTopologyAccess.add(sizes[x],sizes[y])
   } }
   for i in 0..<n {
    let root = try representative(i,forest:&forest,&admission)
    var label: Int? = nil
    for index in roots.indices { try admission.consumeWork(1); if roots[index] == root { label = index; break } }
    if label == nil {
     guard roots.count < limits.maximumComponents else { throw ExactRealTopologyFailure.componentLimit }
     label = roots.count; roots.append(root)
    }
    labels[i] = label!
   }
   try ExactTopologyAccess.storage(n,ExactRealCellID<Base>.self,&admission)
   try ExactTopologyAccess.storage(ExactTopologyAccess.multiply(roots.count,2),Range<Int>.self,&admission)
   try ExactTopologyAccess.storage(incidence.attachments.count,Int.self,&admission)
   var members: [ExactRealCellID<Base>] = [], memberRanges: [Range<Int>] = [], witnesses: [Int] = [], witnessRanges: [Range<Int>] = []
   members.reserveCapacity(n); memberRanges.reserveCapacity(roots.count)
   witnesses.reserveCapacity(incidence.attachments.count); witnessRanges.reserveCapacity(roots.count)
   for component in roots.indices {
    let memberStart = members.count, witnessStart = witnesses.count
    for i in 0..<n { try admission.consumeWork(1); if labels[i] == component { members.append(cells[i]) } }
    for i in 0..<n { for j in 0..<n {
     try admission.consumeWork(1)
     let pair = incidence.pairs[i*n+j]
     if labels[i] != component { continue }
     for index in pair.attachments {
      try admission.consumeWork(1)
      guard labels[j] == component, index < incidence.attachments.count else { throw ExactRealTopologyFailure.invalidCoverage }
      let piece = incidence.attachments[index]
      guard piece.source == cells[i], piece.target == cells[j] else { throw ExactRealTopologyFailure.foreignReceipt }
      witnesses.append(index)
     }
    } }
    memberRanges.append(memberStart..<members.count); witnessRanges.append(witnessStart..<witnesses.count)
   }
   guard members.count == n, witnesses.count == incidence.attachments.count else { throw ExactRealTopologyFailure.invalidCoverage }
   try admission.checkpoint()
   return .init(incidence:copy incidence,members:members,memberRanges:memberRanges,witnesses:witnesses,witnessRanges:witnessRanges,depth:incidence.depth)
  } catch { throw .preserving(error) }
 }
}
