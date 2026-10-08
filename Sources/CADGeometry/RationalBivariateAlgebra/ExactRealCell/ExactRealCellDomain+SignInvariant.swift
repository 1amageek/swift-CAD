#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain {
 public func signInvariant<A: ExactScalarAdmission & ~Copyable>(for polynomial: borrowing Polynomial,
  in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A
 ) throws(ExactRealCellFailure) -> ExactRealCellSignInvariant<Base>? {
  let partition = copy partition, polynomial = copy polynomial
  return try ExactCellAccess.run(&admission, inherited: partition.depth) { a in
   try require(partition.source, &a)
   try ExactCellAccess.admit(polynomial.depth, &a)
   let requested = try polynomials.importing(polynomial, using: &a)
   if try polynomials.isZero(requested, using: &a) { return nil }
   // Auxiliary derivative signs on sectors are sample values, not whole-cell invariants.
   for axis in partition.owner.levels.indices {
    let level = partition.owner.levels[axis]
    guard level.axis == axis, level.cutLawCount >= 0, level.cutLawCount <= level.laws.count else {
     throw ExactRealCellFailure.invalidCoverage
    }
    for index in 0..<level.cutLawCount {
     try a.consumeWork(1)
     let law = level.laws[index]
     let division = try polynomials.divided(requested, by: law, using: &a)
     if try !polynomials.isZero(division.remainder, using: &a) { continue }
     guard division.quotient.termCount == 1 else { continue }
     let term = division.quotient.terms[0]
     var constant = true
     for power in term.powers { try a.consumeWork(1); if power != 0 { constant = false } }
     if !constant { continue }
     let orientation = try context.field.sign(of: term.coefficient, using: &a)
     if orientation == .zero { continue }
     guard try polynomials.equals(requested,
      polynomials.multiplying(division.quotient, law, using: &a), using: &a) else {
      throw ExactRealCellFailure.invalidCoverage
     }
     try ExactCellAccess.admit(law.depth, &a)
     try ExactCellAccess.admit(division.quotient.depth, &a)
     try ExactCellAccess.admit(division.remainder.depth, &a)
     try ExactCellAccess.storage(1, ExactRealCellSignInvariant<Base>.self, &a)
     return .init(partition: partition, polynomial: polynomial, projectionLaw: law,
      quotient: division.quotient, remainder: division.remainder, axis: axis, lawIndex: index,
      orientation: orientation, depth: a.depth)
    }
   }
   return nil
  }
 }

 public func sign<A: ExactScalarAdmission & ~Copyable>(of invariant: borrowing ExactRealCellSignInvariant<Base>,
  at cell: ExactRealCellID<Base>, using admission: inout A
 ) throws(ExactRealCellFailure) -> ExactSign {
  let invariant = copy invariant
  return try ExactCellAccess.run(&admission, inherited: invariant.depth) { a in
   let partition = invariant.partition
   try validate(cell, partition: partition, &a)
   guard partition.owner.levels.indices.contains(invariant.axis), invariant.orientation != .zero else {
    throw ExactRealCellFailure.invalidCoverage
   }
   let level = partition.owner.levels[invariant.axis]
   guard invariant.lawIndex >= 0, invariant.lawIndex < level.cutLawCount,
    level.laws.indices.contains(invariant.lawIndex) else { throw ExactRealCellFailure.invalidCoverage }
   guard let attained = cell.axis, attained >= invariant.axis else { throw ExactRealCellFailure.invalidCell }
   var ancestor = cell
   while let axis = ancestor.axis, axis > invariant.axis {
    try a.consumeWork(1)
    guard let parent = ancestor.parent else { throw ExactRealCellFailure.invalidCoverage }
    ancestor = parent
   }
   guard ancestor.axis == invariant.axis,
    ancestor.projectionSigns.indices.contains(invariant.lawIndex) else { throw ExactRealCellFailure.invalidCoverage }
   try a.consumeWork(1)
   let sign = ancestor.projectionSigns[invariant.lawIndex]
   if invariant.orientation == .positive { return sign }
   switch sign { case .negative: return .positive; case .zero: return .zero; case .positive: return .negative }
  }
 }
}
