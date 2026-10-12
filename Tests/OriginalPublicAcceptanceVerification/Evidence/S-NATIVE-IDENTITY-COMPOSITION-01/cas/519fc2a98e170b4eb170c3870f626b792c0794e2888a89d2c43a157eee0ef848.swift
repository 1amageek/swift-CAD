#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain {
    public func projectionEvidence<A: ExactScalarAdmission & ~Copyable>(forAxis axis: Int,
        in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A
    ) throws(ExactRealCellFailure) -> ExactRealCellProjectionEvidence<Base> {
        let partition = copy partition
        return try ExactCellAccess.run(&admission, inherited: partition.depth) { a in
            try require(partition.source, &a)
            guard partition.owner.levels.indices.contains(axis) else { throw ExactRealCellFailure.invalidVariable }
            return .init(owner: partition.owner, axis: axis)
        }
    }
    public func stackEvidence<A: ExactScalarAdmission & ~Copyable>(over parent: ExactRealCellID<Base>,
        in partition: borrowing ExactRealCellPartition<Base>, using admission: inout A
    ) throws(ExactRealCellFailure) -> ExactRealCellStackEvidence<Base> {
        let partition = copy partition
        return try ExactCellAccess.run(&admission, inherited: partition.depth) { a in
            try validate(parent, partition: partition, &a)
            let index = partition.owner.records[parent.index].stack
            guard partition.owner.stacks.indices.contains(index), partition.owner.stacks[index].parent == parent.index else {
                throw ExactRealCellFailure.invalidCell
            }
            return .init(parent: parent, stackIndex: index)
        }
    }
}
