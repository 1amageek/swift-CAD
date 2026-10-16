import CADCore
import CADIR
import CADModeling
import CADTopology
import CADGeometry

/// What surface queries read: a B-rep and how stable subshape references resolve in it. An
/// evaluated document answers them after evaluation, and an evaluation context during it, so a
/// feature can query the faces of the model it is evaluated in (Wrap's UVN charts).
public protocol SurfaceQueryModel: Sendable {
    var brep: BRepModel { get }
    func topologyReference(for reference: StableSubshapeReference) throws -> TopologyReference
    func originalTopologyReference(for reference: StableSubshapeReference,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution) throws -> TopologyReference
}

extension EvaluatedDocument: SurfaceQueryModel {}

extension EvaluationContext: SurfaceQueryModel {
    public func topologyReference(for reference: StableSubshapeReference) throws -> TopologyReference {
        try StableSubshapeResolver().topologyReference(
            for: reference,
            model: brep,
            subshapes: subshapes,
            lineage: lineage,
            tolerance: tolerance
        )
    }
}


extension SurfaceQueryModel {
    // FIXME(INCOMPLETE_IMPLEMENTATION): External custom models using bounded measurement preparation
    // need an actual same-ledger original topology resolver. Legacy lookup does not prove its work/bytes;
    // this default must not succeed until that provider composes the caller callbacks.
    public func originalTopologyReference(for reference: StableSubshapeReference,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution) throws -> TopologyReference {
        throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
            message: "Custom surface query models must supply original same-ledger topology resolution.")
    }
}

extension EvaluatedDocument {
    public func originalTopologyReference(for reference: StableSubshapeReference,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution) throws -> TopologyReference {
        try StableSubshapeResolver().topologyReference(for: reference, model: brep,
            subshapes: subshapes, lineage: lineage, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }
}

extension EvaluationContext {
    public func originalTopologyReference(for reference: StableSubshapeReference,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution) throws -> TopologyReference {
        try StableSubshapeResolver().topologyReference(for: reference, model: brep,
            subshapes: subshapes, lineage: lineage, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }
}
