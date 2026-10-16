#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain: ExactRealCellDescribing, ExactRealCellTraversing {
 public func coefficientField<A: ExactScalarAdmission & ~Copyable>(of source: borrowing ExactRealCellSource<Base>, using admission: inout A) throws(ExactRealCellFailure) -> Field {
  let source = copy source
  return try ExactCellAccess.run(&admission, inherited: source.depth) { a in
   try require(source, &a); return context.field
  }
 }
 public func root<A: ExactScalarAdmission & ~Copyable>(in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellID<Base>? {
  let partition = copy partition
  return try ExactCellAccess.run(&admission, inherited: partition.depth) { a in
   try require(partition.source, &a)
   if partition.owner.records.isEmpty {
    try a.consumeWork(partition.source.domains.count)
    guard partition.source.domains.contains(where: { $0.isEmpty }) else { throw ExactRealCellFailure.invalidCoverage }
    return nil
   }
   guard partition.owner.records[0].parent == -1 else { throw ExactRealCellFailure.invalidCoverage }
   return .init(owner: partition.owner, index: 0)
  }
 }
 public func children<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellView<Base> {
  let partition = copy partition
  return try ExactCellAccess.run(&admission, inherited: partition.depth) { a in
   try validate(cell, partition: partition, &a)
   let record = partition.owner.records[cell.index]
   if record.sample.coordinates.count == partition.source.variableCount { return .init(owner: partition.owner, indices: []) }
   guard record.stack >= 0, record.stack < partition.owner.stacks.count else { throw ExactRealCellFailure.invalidCoverage }
   let stack = partition.owner.stacks[record.stack]
   guard stack.parent == cell.index else { throw ExactRealCellFailure.invalidCoverage }
   try ExactCellAccess.storage(stack.children.count, Int.self, &a)
   var indices: [Int] = []; indices.reserveCapacity(stack.children.count)
   for index in stack.children {
    try a.consumeWork(1)
    if index >= 0 {
     guard index < partition.owner.records.count, partition.owner.records[index].parent == cell.index else { throw ExactRealCellFailure.invalidCoverage }
     indices.append(index)
    }
   }
   guard !indices.isEmpty else { throw ExactRealCellFailure.invalidCoverage }
   return .init(owner: partition.owner, indices: indices)
  }
 }
 func boundary<A: ExactScalarAdmission & ~Copyable>(parent: ExactRealCellID<Base>, axis: Int, ordinal: Int, _ a: inout A) throws -> ExactRealCellBoundaryRoot<Base> {
  let owner = parent.owner, stack = owner.stacks[owner.records[parent.index].stack], level = owner.levels[axis]
  guard ordinal >= 0, ordinal < stack.rootSet.roots.count else { throw ExactRealCellFailure.invalidCoverage }
  let root = stack.rootSet.roots[ordinal]
  let r = try ExactRealRootDomain(retaining: root.source, using: &a)
  let prefix = owner.records[parent.index].sample
  var incoming: Int? = nil, support: Int? = nil
  // Exact common-root tests bind incoming identity before considering derivative support.
  for index in stack.activeLawIndices {
   try a.consumeWork(1)
   let law = try r.bind(r.polynomials.importing(stack.specialized[index].original, using: &a), using: &a)
   if try r.sign(of: law, at: root, using: &a) == .zero { incoming = index; break }
  }
  guard let incoming else { throw ExactRealCellFailure.invalidCoverage }
  for index in level.laws.indices {
   try a.consumeWork(1)
   let law = level.laws[index]
   var affine = true, leading = false
   for term in law.terms {
    try a.consumeWork(term.powers.count)
    var degree = 0
    for power in term.powers { degree = try ExactCellAccess.add(degree, power) }
    if degree > 1 { affine = false; break }
    if term.powers[axis] == 1 { leading = true }
   }
   if !affine || !leading { continue }
   let specialized = try r.bind(specialize(law, prefix: prefix, axis: axis, into: r.polynomials, &a), using: &a)
   if try r.sign(of: specialized, at: root, using: &a) == .zero { support = index; break }
  }
  guard stack.rootMultiplicities.indices.contains(incoming),
   stack.rootMultiplicities[incoming].indices.contains(ordinal) else { throw ExactRealCellFailure.invalidCoverage }
  let incomingMultiplicity = stack.rootMultiplicities[incoming][ordinal]
  guard incomingMultiplicity > 0,
   let incomingDegree = try polynomials.degree(of: level.laws[incoming], in: axis, using: &a) else {
   throw ExactRealCellFailure.invalidCoverage
  }
  try ExactCellAccess.storage(ExactCellAccess.add(incomingDegree, 1), ExactSign.self, &a)
  var incomingSigns: [ExactSign] = [], incomingDerivative = level.laws[incoming]
  incomingSigns.reserveCapacity(incomingDegree + 1)
  for order in 0...incomingDegree {
   let specialized = try r.bind(specialize(incomingDerivative, prefix: prefix, axis: axis, into: r.polynomials, &a), using: &a)
   incomingSigns.append(try r.sign(of: specialized, at: root, using: &a))
   if order < incomingDegree { incomingDerivative = try polynomials.differentiated(incomingDerivative, in: axis, using: &a) }
  }
  guard incomingSigns.first == .zero,
   incomingSigns.firstIndex(where: { $0 != .zero }) == incomingMultiplicity else { throw ExactRealCellFailure.invalidCoverage }
  let polynomial = level.laws[support ?? incoming]
  guard let degree = try polynomials.degree(of: polynomial, in: axis, using: &a), degree > 0 else { throw ExactRealCellFailure.invalidCoverage }
  try ExactCellAccess.storage(ExactCellAccess.add(degree, 1), ExactSign.self, &a)
  var signs: [ExactSign] = []; signs.reserveCapacity(degree + 1)
  var derivative = polynomial
  for order in 0...degree {
   try a.consumeWork(1)
   let specialized = try r.bind(specialize(derivative, prefix: prefix, axis: axis, into: r.polynomials, &a), using: &a)
   signs.append(try r.sign(of: specialized, at: root, using: &a))
   if order < degree { derivative = try polynomials.differentiated(derivative, in: axis, using: &a) }
  }
  guard signs.first == .zero else { throw ExactRealCellFailure.invalidCoverage }
  return .init(parent: parent, axis: axis, rootOrdinal: ordinal, incomingLawIndex: incoming,
   incomingLaw: level.laws[incoming], incomingMultiplicity: incomingMultiplicity, incomingDerivativeSigns: incomingSigns, polynomial: polynomial, derivativeSigns: signs, depth: (try a.depth))
 }
 public func definition<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellDefinition<Base> {
  let partition = copy partition
  return try ExactCellAccess.run(&admission, inherited: partition.depth) { a in
   try validate(cell, partition: partition, &a)
   let count = partition.owner.records[cell.index].sample.coordinates.count
   try ExactCellAccess.storage(count, ExactRealCellID<Base>.self, &a)
   var path: [ExactRealCellID<Base>] = []; path.reserveCapacity(count)
   var current = cell
   while let parent = current.parent { try a.consumeWork(1); path.append(current); current = parent }
   guard path.count == count, current.index == 0 else { throw ExactRealCellFailure.invalidCoverage }
   try ExactCellAccess.storage(count, ExactRealCellDefinitionStep<Base>.self, &a)
   var steps: [ExactRealCellDefinitionStep<Base>] = []; steps.reserveCapacity(count)
   for id in path.reversed() {
    try a.consumeWork(1)
    guard let parent = id.parent, let axis = id.axis else { throw ExactRealCellFailure.invalidCoverage }
    var section: ExactRealCellBoundaryRoot<Base>?, lower: ExactRealCellBoundaryRoot<Base>?, upper: ExactRealCellBoundaryRoot<Base>?
    switch id.kind {
    case .origin: throw ExactRealCellFailure.invalidCoverage
    case .section(let ordinal): section = try boundary(parent: parent, axis: axis, ordinal: ordinal, &a)
    case .sector(let l, let u):
     if let l { lower = try boundary(parent: parent, axis: axis, ordinal: l, &a) }
     if let u { upper = try boundary(parent: parent, axis: axis, ordinal: u, &a) }
    }
    steps.append(.init(parent: parent, cell: id, axis: axis, section: section, lower: lower, upper: upper))
   }
   return .init(partition: partition, cell: cell, coefficientField: context.field, steps: steps, depth: (try a.depth))
  }
 }
}
