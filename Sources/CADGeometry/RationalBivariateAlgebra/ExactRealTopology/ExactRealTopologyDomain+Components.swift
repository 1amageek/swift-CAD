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
   let edgeCount = incidence.attachments.count
   try ExactTopologyAccess.storage(ExactTopologyAccess.multiply(n,4),Int.self,&admission)
   try admission.consumeWork(ExactTopologyAccess.multiply(n,4))
   var forest = Array(0..<n), sizes = Array(repeating:1,count:n)
   var labels = Array(repeating:-1,count:n), rootLabels = Array(repeating:-1,count:n)
   try ExactTopologyAccess.storage(edgeCount,Int.self,&admission)
   try admission.consumeWork(edgeCount)
   var pieceSources = Array(repeating:0,count:edgeCount), seen = 0
   for i in 0..<n { for j in 0..<n {
    try admission.consumeWork(1)
    let pair = incidence.pairs[i*n+j]
    guard pair.source == cells[i], pair.target == cells[j], pair.attachments.lowerBound == seen,
     pair.attachments.upperBound <= edgeCount else { throw ExactRealTopologyFailure.foreignReceipt }
    for index in pair.attachments {
     try admission.consumeWork(1)
     let piece = incidence.attachments[index]
     guard piece.source == cells[i], piece.target == cells[j] else { throw ExactRealTopologyFailure.foreignReceipt }
     pieceSources[index] = i
    }
    seen = pair.attachments.upperBound
    if pair.attachments.isEmpty { continue }
    var x = try representative(i,forest:&forest,&admission), y = try representative(j,forest:&forest,&admission)
    if x == y { continue }
    if sizes[x] < sizes[y] { swap(&x,&y) }
    forest[y] = x; sizes[x] = try ExactTopologyAccess.add(sizes[x],sizes[y])
   } }
   guard seen == edgeCount else { throw ExactRealTopologyFailure.invalidCoverage }
   var componentCount = 0
   for i in 0..<n {
    let root = try representative(i,forest:&forest,&admission)
    if rootLabels[root] < 0 {
     guard componentCount < limits.maximumComponents else { throw ExactRealTopologyFailure.componentLimit }
     rootLabels[root] = componentCount; componentCount = try ExactTopologyAccess.add(componentCount,1)
    }
    labels[i] = rootLabels[root]
   }
   try ExactTopologyAccess.storage(ExactTopologyAccess.multiply(componentCount,2),Int.self,&admission)
   try admission.consumeWork(ExactTopologyAccess.multiply(componentCount,2))
   var memberOffsets = Array(repeating:0,count:componentCount), witnessOffsets = Array(repeating:0,count:componentCount)
   for i in 0..<n { try admission.consumeWork(1); memberOffsets[labels[i]] = try ExactTopologyAccess.add(memberOffsets[labels[i]],1) }
   for source in pieceSources { try admission.consumeWork(1); witnessOffsets[labels[source]] = try ExactTopologyAccess.add(witnessOffsets[labels[source]],1) }
   try ExactTopologyAccess.storage(ExactTopologyAccess.multiply(componentCount,2),Range<Int>.self,&admission)
   var memberRanges: [Range<Int>] = [], witnessRanges: [Range<Int>] = []
   memberRanges.reserveCapacity(componentCount); witnessRanges.reserveCapacity(componentCount)
   var memberEnd = 0, witnessEnd = 0
   for component in 0..<componentCount {
    try admission.consumeWork(1)
    let nextMember = try ExactTopologyAccess.add(memberEnd,memberOffsets[component])
    let nextWitness = try ExactTopologyAccess.add(witnessEnd,witnessOffsets[component])
    memberRanges.append(memberEnd..<nextMember); witnessRanges.append(witnessEnd..<nextWitness)
    memberOffsets[component] = memberEnd; witnessOffsets[component] = witnessEnd
    memberEnd = nextMember; witnessEnd = nextWitness
   }
   guard memberEnd == n, witnessEnd == edgeCount else { throw ExactRealTopologyFailure.invalidCoverage }
   try ExactTopologyAccess.storage(n,ExactRealCellID<Base>.self,&admission)
   try ExactTopologyAccess.storage(edgeCount,Int.self,&admission)
   try admission.consumeWork(ExactTopologyAccess.add(n,edgeCount))
   var members = n == 0 ? [] : Array(repeating:cells[0],count:n)
   var witnesses = Array(repeating:0,count:edgeCount)
   // Stable scatter keeps source member order and original attachment order.
   for i in 0..<n {
    try admission.consumeWork(1)
    let label = labels[i], offset = memberOffsets[label]
    guard memberRanges[label].contains(offset) else { throw ExactRealTopologyFailure.invalidCoverage }
    members[offset] = cells[i]; memberOffsets[label] += 1
   }
   for index in pieceSources.indices {
    try admission.consumeWork(1)
    let label = labels[pieceSources[index]], offset = witnessOffsets[label]
    guard witnessRanges[label].contains(offset) else { throw ExactRealTopologyFailure.invalidCoverage }
    witnesses[offset] = index; witnessOffsets[label] += 1
   }
   try admission.checkpoint()
   return .init(incidence:copy incidence,members:members,memberRanges:memberRanges,witnesses:witnesses,witnessRanges:witnessRanges,depth:incidence.depth)
  } catch { throw .preserving(error) }
 }
}
