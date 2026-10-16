#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain: ExactRealCellSelecting {
 func truth<A: ExactScalarAdmission & ~Copyable>(_ predicate: ExactRealCellPredicate<Base>, signs: [ExactSign], _ a: inout A) throws -> Bool {
  try ExactCellAccess.admit(predicate.depth,&a)
  try ExactCellAccess.storage(predicate.instructions.count,Bool.self,&a)
  var stack: [Bool] = []; stack.reserveCapacity(predicate.instructions.count)
  for instruction in predicate.instructions {
   try a.consumeWork(1)
   switch instruction {
   case .literal(let value): stack.append(value)
   case .sign(let index,let relation):
    guard index >= 0,index < signs.count else { throw ExactRealCellFailure.invalidPredicate }; stack.append(relation.accepts(signs[index]))
   case .not:
    guard let value=stack.popLast() else { throw ExactRealCellFailure.invalidPredicate }; stack.append(!value)
   case .and,.or:
    guard let right=stack.popLast(),let left=stack.popLast() else { throw ExactRealCellFailure.invalidPredicate }
    if case .and = instruction { stack.append(left && right) } else { stack.append(left || right) }
   }
  }
  guard stack.count == 1 else { throw ExactRealCellFailure.invalidPredicate }; return stack[0]
 }
 public func select<A: ExactScalarAdmission & ~Copyable>(_ partition: borrowing ExactRealCellPartition<Base>,
  matching predicate: borrowing ExactRealCellPredicate<Base>, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellSelection<Base> {
  let partition=copy partition,predicate=copy predicate
  return try ExactCellAccess.run(&admission,inherited:partition.depth) { a in
   try require(partition.source,&a)
   guard predicate.source.owner === partition.source.owner else { throw ExactRealCellFailure.incompatibleDomain }
   try ExactCellAccess.admit(predicate.depth,&a)
   var selected: [Int] = []
   for index in partition.owner.leaves {
    if try truth(predicate,signs:partition.owner.records[index].signs,&a) {
     try ExactCellAccess.storage(1,Int.self,&a); selected.append(index)
    }
   }; return .init(partition:partition,predicate:predicate,selected:selected,depth:(try a.depth))
  }
 }
}
