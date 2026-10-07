#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
 func truth<A: ExactScalarAdmission & ~Copyable>(_ instructions: [ExactRealCellInstruction], signs: [ExactSign], _ a: inout A) throws -> Bool {
  try ExactTopologyAccess.storage(instructions.count,Bool.self,&a)
  var stack: [Bool] = []; stack.reserveCapacity(instructions.count)
  for item in instructions {
   try a.consumeWork(1)
   switch item {
   case .literal(let value): stack.append(value)
   case .sign(let index, let relation):
    guard index >= 0, index < signs.count else { throw ExactRealTopologyFailure.invalidFormula }
    stack.append(ExactTopologyAccess.accepts(signs[index],relation))
   case .not:
    guard let value = stack.popLast() else { throw ExactRealTopologyFailure.invalidFormula }; stack.append(!value)
   case .and,.or:
    guard let right = stack.popLast(), let left = stack.popLast() else { throw ExactRealTopologyFailure.invalidFormula }
    switch item { case .and: stack.append(left && right); default: stack.append(left || right) }
   }
  }
  guard stack.count == 1 else { throw ExactRealTopologyFailure.invalidFormula }; return stack[0]
 }
 func reduce<A: ExactScalarAdmission & ~Copyable>(_ formula: ExactTopologyFormula<Base>, limits: ExactRealTopologyLimits,
  counts: inout ExactTopologyCounts, _ a: inout A) throws -> ExactRealTopologyRegion<Base> {
  for atom in formula.atoms { try a.consumeWork(1); try counts.retain(atom.depth,&a) }
  for proof in formula.eliminations {
   try counts.retain(proof.replacement.depth,&a)
   for atom in proof.originalAtoms { try a.consumeWork(1); try counts.retain(atom.depth,&a) }
  }
  for proof in formula.reductions {
   for atom in proof.originalAtoms { try a.consumeWork(1); try counts.retain(atom.depth,&a) }
   for atom in proof.derivedAtoms { try a.consumeWork(1); try counts.retain(atom.depth,&a) }
  }
  let n = formula.polynomials.variableCount
  guard n == (try ExactTopologyAccess.add(formula.freeCount,formula.quantifiers.count)) else { throw ExactRealTopologyFailure.invalidFormula }
  let cells = try Cells(field:formula.field,variableCount:n,using:&a)
  try ExactTopologyAccess.storage(formula.atoms.count,Polynomial.self,&a)
  var atoms: [Polynomial] = []; atoms.reserveCapacity(formula.atoms.count)
  for atom in formula.atoms { try a.consumeWork(1); atoms.append(try cells.polynomials.importing(atom,using:&a)) }
  let roots = try ExactRealRootDomain(field:formula.field,using:&a)
  let line = try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
  try ExactTopologyAccess.storage(n,ExactRealRootInterval<Field.Value>.self,&a)
  let source = try cells.bind(polynomials:atoms,domains:Array(repeating:line,count:n),using:&a)
  guard counts.generated <= limits.maximumGeneratedCells else { throw ExactRealTopologyFailure.generatedCellLimit }
  let remaining = limits.maximumGeneratedCells - counts.generated
  let partition: ExactRealCellPartition<Base>
  do { partition = try cells.decompose(source,limits:.init(maximumStoredCells:remaining,maximumRootsPerStack:limits.maximumRootsPerStack),using:&a) }
  catch ExactRealCellFailure.cellLimit { throw ExactRealTopologyFailure.generatedCellLimit }
  counts.generated = try ExactTopologyAccess.add(counts.generated,partition.storedCellCount)
  try counts.retain(partition.depth,&a)
  guard let root = try cells.root(in:partition,using:&a) else { throw ExactRealTopologyFailure.invalidCoverage }
  try ExactTopologyAccess.storage(partition.storedCellCount,ExactTopologyDecision<Base>.self,&a)
  var nodes: [ExactTopologyDecision<Base>] = []; nodes.reserveCapacity(partition.storedCellCount)
  nodes.append(.init(cell:root,children:0..<0,truth:false))
  var cursor = 0
  while cursor < nodes.count {
   try a.consumeWork(1)
   let children = try cells.children(of:nodes[cursor].cell,in:partition,using:&a)
   let start = nodes.count
   for child in children { try a.consumeWork(1); nodes.append(.init(cell:child,children:0..<0,truth:false)) }
   let old = nodes[cursor]
   nodes[cursor] = .init(cell:old.cell,children:start..<nodes.count,truth:false)
   cursor += 1
  }
  guard nodes.count == partition.storedCellCount else { throw ExactRealTopologyFailure.invalidCoverage }
  for index in nodes.indices.reversed() {
   try a.consumeWork(1)
   let count = (nodes[index].cell.axis ?? -1) + 1
   if count == n {
    nodes[index].truth = try truth(formula.instructions,signs:nodes[index].cell.signs,&a)
   } else if count >= formula.freeCount {
    let existential = formula.quantifiers[count - formula.freeCount]
    guard !nodes[index].children.isEmpty else { throw ExactRealTopologyFailure.invalidCoverage }
    var value = !existential
    for child in nodes[index].children {
     try a.consumeWork(1)
     value = existential ? (value || nodes[child].truth) : (value && nodes[child].truth)
    }
    nodes[index].truth = value
   }
  }
  try ExactTopologyAccess.storage(nodes.count,ExactRealCellID<Base>.self,&a)
  try ExactTopologyAccess.storage(nodes.count,Bool.self,&a)
  var regions: [ExactRealCellID<Base>] = [], included: [Bool] = []
  regions.reserveCapacity(nodes.count); included.reserveCapacity(nodes.count)
  for node in nodes {
   try a.consumeWork(1)
   if (node.cell.axis ?? -1) + 1 == formula.freeCount { regions.append(node.cell); included.append(node.truth) }
  }
  guard !regions.isEmpty else { throw ExactRealTopologyFailure.invalidCoverage }
  return .init(partition:partition,coordinateCount:formula.freeCount,cells:regions,included:included,excludesExterior:false,formulaAtoms:atoms,signInvariants:[],certifiedTarget:nil,reductions:formula.reductions,eliminations:formula.eliminations,depth:counts.depth,
   decisions:nodes,quantifiers:formula.quantifiers,instructions:formula.instructions)
 }
}
