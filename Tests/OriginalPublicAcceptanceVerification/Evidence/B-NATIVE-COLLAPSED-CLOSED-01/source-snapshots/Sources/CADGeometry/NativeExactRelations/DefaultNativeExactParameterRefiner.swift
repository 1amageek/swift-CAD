#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Consumes L4's exact raw-cell pullback without resolving the raw relation again.
public struct DefaultNativeExactParameterRefiner: NativeExactParameterRefining {
    public init() {}
    public func refine<A: ExactScalarAdmission & ~Copyable>(
        _ raw: borrowing ExactParametricRelation<ExactRationalScalarDomain>,
        matching predicate: borrowing ExactRealCellPredicate<ExactRationalScalarDomain>,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,
        using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParameterRefinement {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value: raw.components.depth.value, coefficient: raw.components.depth.coefficient)
            let n = raw.original.predicate.source.variableCount
            guard predicate.source.variableCount == n else { throw NativeExactRelationFailure.invalidDomain }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:Int.self))
            var coordinates: [Int] = []; coordinates.reserveCapacity(n)
            for axis in 0..<n { try admission.consumeWork(1); coordinates.append(axis) }
            let topology = ExactRealTopologyDomain<ExactRationalScalarDomain,ExactRealCellDomain<ExactRationalScalarDomain>>(
                cells:ExactRealCellDomain<ExactRationalScalarDomain>.self)
            let pullback: ExactRealCellPullback<ExactRationalScalarDomain>
            do {
                pullback = try topology.refinePullback(of:raw.selection,onto:predicate,
                    coordinateMap:coordinates,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
            } catch {
                if case .scalar(let cause) = error { throw NativeExactRelationFailure.scalar(cause) }
                throw NativeExactRelationFailure.geometry(error)
            }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:NativeExactParameterRefinement.self))
            let result = NativeExactParameterRefinement(raw:copy raw,pullback:pullback)
            try admission.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }
}
