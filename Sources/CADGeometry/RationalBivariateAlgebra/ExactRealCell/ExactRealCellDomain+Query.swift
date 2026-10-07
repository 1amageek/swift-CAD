#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain: ExactRealCellQuerying {
 func validate(_ cell: ExactRealCellID<Base>, partition: ExactRealCellPartition<Base>, _ a: inout ExactCellBorrowedAdmission) throws {
  try require(partition.source,&a); try ExactCellAccess.admit(partition.depth,&a)
  guard cell.owner === partition.owner,cell.index >= 0,cell.index < partition.owner.records.count else { throw ExactRealCellFailure.invalidCell }
 }
 public func sample<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellSample<Base> {
  let partition=copy partition
  return try ExactCellAccess.run(&admission,inherited:partition.depth) { a in
   try validate(cell,partition:partition,&a)
   let result=partition.owner.records[cell.index].sample; try ExactCellAccess.admit(result.depth,&a); return result
  }
 }
 public func condition<A: ExactScalarAdmission & ~Copyable>(of cell: ExactRealCellID<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellCondition<Base> {
  let partition=copy partition
  return try ExactCellAccess.run(&admission,inherited:partition.depth) { a in
   try validate(cell,partition:partition,&a)
   let count=partition.owner.records[cell.index].sample.coordinates.count
   try ExactCellAccess.storage(count,Int.self,&a)
   var branches=Array(repeating:0,count:count),index=cell.index
   for axis in branches.indices.reversed() {
    try a.consumeWork(1); branches[axis]=partition.owner.records[index].branch; index=partition.owner.records[index].parent
   }
   guard index == 0 else { throw ExactRealCellFailure.invalidCoverage }
   return .init(cell:cell,branches:branches,depth:a.depth)
  }
 }
 public func point<A: ExactScalarAdmission & ~Copyable>(field: Field, coordinates: [Field.Value],
  using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellSample<Base> {
  try ExactCellAccess.run(&admission,inherited:context.depth) { a in
   guard coordinates.count == polynomials.variableCount else { throw ExactRealCellFailure.invalidVariable }
   _ = try field.importing(context.field.integer(1,using:&a),using:&a)
   for value in coordinates { _ = try field.sign(of:value,using:&a) }
   return .init(field:field,coordinates:coordinates,depth:a.depth)
  }
 }
 public func locate<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>, in partition: borrowing ExactRealCellPartition<Base>,
  limits: ExactRealRootLimits, using admission: inout A) throws(ExactRealCellFailure) -> ExactRealCellID<Base>? {
  let point=copy point,partition=copy partition
  return try ExactCellAccess.run(&admission,inherited:partition.depth) { try located(point,partition:partition,limits:limits,&$0) }
 }
 func located(_ point: ExactRealCellSample<Base>, partition: ExactRealCellPartition<Base>, limits: ExactRealRootLimits,
  _ a: inout ExactCellBorrowedAdmission) throws -> ExactRealCellID<Base>? {
  try require(partition.source,&a); try ExactCellAccess.admit(partition.depth,&a); try ExactCellAccess.admit(point.depth,&a)
  let field=point.field,source=partition.source
  _ = try field.importing(context.field.integer(1,using:&a),using:&a)
  guard point.coordinates.count == source.variableCount else { throw ExactRealCellFailure.invalidVariable }
  for value in point.coordinates { _ = try field.sign(of:value,using:&a) }
  for axis in source.domains.indices {
   if try !inside(point.coordinates[axis],field:field,domain:source.domains[axis],&a) { return nil }
  }
  guard !partition.owner.records.isEmpty else { throw ExactRealCellFailure.invalidCoverage }
  var index=0
  for axis in 0..<source.variableCount {
   try a.consumeWork(1)
   let offset=partition.owner.records[index].stack
   guard offset >= 0,offset < partition.owner.stacks.count else { throw ExactRealCellFailure.invalidCoverage }
   let stack=partition.owner.stacks[offset],level=partition.owner.levels[axis]
   guard stack.parent == index,stack.axis == axis else { throw ExactRealCellFailure.invalidCoverage }
   try ExactCellAccess.storage(axis,Field.Value.self,&a)
   let prefix=ExactRealCellSample(field:field,coordinates:Array(point.coordinates.prefix(axis)),depth:point.depth)
   let r=try ExactRealRootDomain(field:field,using:&a),p=r.polynomials
   var product=try p.constant(field.integer(1,using:&a),using:&a)
   for lawIndex in level.laws.indices {
    for degree in level.coefficients[lawIndex].indices {
     let sign=try field.sign(of:evaluate(level.coefficients[lawIndex][degree],at:prefix,&a),using:&a)
     guard sign == stack.coefficientSigns[lawIndex][degree] else { throw ExactRealCellFailure.invalidCoverage }
    }
   }
   for lawIndex in stack.activeLawIndices {
    let law=try specialize(level.laws[lawIndex],prefix:prefix,axis:axis,into:p,&a)
    product=try p.multiplying(product,law,using:&a)
   }
   let all=try r.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
   let set=try r.isolate(r.bind(product,using:&a),in:all,limits:limits,using:&a)
   guard set.roots.count == stack.rootSet.roots.count else { throw ExactRealCellFailure.invalidCoverage }
   let delta=try r.bind(p.subtracting(p.variable(0,using:&a),p.constant(point.coordinates[axis],using:&a),using:&a),using:&a)
   var branch=try ExactCellAccess.multiply(set.roots.count,2)
   for root in set.roots {
    let sign=try r.sign(of:delta,at:root,using:&a)
    if sign == .zero { branch=try ExactCellAccess.add(ExactCellAccess.multiply(root.ordinal,2),1); break }
    if sign == .positive { branch=try ExactCellAccess.multiply(root.ordinal,2); break }
   }
   guard branch < stack.children.count,stack.children[branch] >= 0 else { throw ExactRealCellFailure.invalidCoverage }
   index=stack.children[branch]
  }
  return .init(owner:partition.owner,index:index)
 }
 public func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>, in condition: borrowing ExactRealCellCondition<Base>,
  limits: ExactRealRootLimits, using admission: inout A) throws(ExactRealCellFailure) -> Bool {
  let point=copy point,condition=copy condition
  return try ExactCellAccess.run(&admission,inherited:condition.depth) { a in
   guard let full=try located(point,partition:.init(owner:condition.cell.owner),limits:limits,&a) else { return false }
   let owner=condition.cell.owner, targetCount=owner.records[condition.cell.index].sample.coordinates.count
   var index=full.index
   while owner.records[index].sample.coordinates.count > targetCount {
    try a.consumeWork(1); index=owner.records[index].parent
    guard index >= 0 else { throw ExactRealCellFailure.invalidCoverage }
   }
   return index == condition.cell.index
  }
 }
}
