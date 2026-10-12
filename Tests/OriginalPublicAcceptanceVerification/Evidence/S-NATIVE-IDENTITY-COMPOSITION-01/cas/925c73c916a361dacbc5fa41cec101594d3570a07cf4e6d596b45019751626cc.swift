#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellID<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable, Equatable where Base.Source == Base.Value {
 let owner: ExactRealCellPartitionStorage<Base>
 let index: Int
 public var source: ExactRealCellSource<Base> { owner.source }
 public var axis: Int? { let n=owner.records[index].sample.coordinates.count; return n == 0 ? nil : n-1 }
 public var parent: Self? { let p=owner.records[index].parent; return p < 0 ? nil : .init(owner:owner,index:p) }
 public var kind: ExactRealCellKind {
  let r=owner.records[index]
  if r.parent < 0 { return .origin }
  if r.branch & 1 == 1 { return .section(rootOrdinal:r.branch/2) }
  let ordinal=r.branch/2, count=owner.stacks[owner.records[r.parent].stack].rootSet.roots.count
  return .sector(lowerRootOrdinal:ordinal == 0 ? nil : ordinal-1,upperRootOrdinal:ordinal == count ? nil : ordinal)
 }
 /// Includes auxiliary derivatives; sector derivative signs describe the exact sample.
 public var projectionLaws: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>] { guard let axis else { return [] }; return owner.levels[axis].laws }
 public var projectionSigns: [ExactSign] { owner.records[index].projectionSigns }
 public var depth: ExactScalarDepth { owner.depth }
 public var dimension: Int { owner.records[index].dimension }
 public var signs: [ExactSign] { owner.records[index].signs }
 public static func == (lhs: Self, rhs: Self) -> Bool { lhs.owner === rhs.owner && lhs.index == rhs.index }
}
