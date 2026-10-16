import CADCore
import CADGeometry
import CADTopology

/// Composes retained original edge geometry with actual current B-rep ownership.
public struct BRepDrawingProjector: BRepDrawingProjecting {
    private let edgeProjector: any OrthographicEdgeProjecting

    public init(edgeProjector: any OrthographicEdgeProjecting = DefaultOrthographicEdgeProjector()) {
        self.edgeProjector = edgeProjector
    }

    public func projectEdges(in evaluated: EvaluatedDocument, onto frame: OrthographicProjectionFrame,
                             maximumProjectedUses: Int) throws -> BRepDrawingProjection {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try projectEdges(in: evaluated, onto: frame, maximumProjectedUses: maximumProjectedUses, using: &execution)
    }

    public func projectEdges(in evaluated: EvaluatedDocument, onto frame: OrthographicProjectionFrame,
                             maximumProjectedUses: Int, using execution: inout OriginalQueryExecution) throws -> BRepDrawingProjection {
        try execution.checkpoint()
        let tolerance = evaluated.configuration.tolerance
        try execution.consumeWork(1)
        guard maximumProjectedUses > 0 else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                              message: "Geometric drawing projection requires a positive use capacity.")
        }
        try evaluated.document.validate(tolerance: tolerance, independentShapeLimits: .standard, using: &execution)
        try evaluated.brep.validate(tolerance: tolerance, using: &execution)
        let model = evaluated.brep
        var uses: [BRepDrawingProjectedUse] = []
        for bodyID in try OriginalParameterQueryStorage.ordered(model.bodies.keys, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("Drawing body is absent.") }
            for shellID in body.shellIDs {
            try execution.consumeWork(1)
                guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("Drawing shell is absent.") }
                for faceID in shell.faceIDs {
            try execution.consumeWork(1)
                    guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Drawing face is absent.") }
                    for loopID in face.loops {
            try execution.consumeWork(1)
                        guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Drawing loop is absent.") }
                        for coedge in loop.coedges {
                            try execution.consumeWork(1)
                            guard uses.count < maximumProjectedUses else {
                                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                                    tolerance: tolerance, message: "Geometric drawing exhausted the caller projected-use capacity.")
                            }
                            let edge = try edgeProjector.project(edgeID: coedge.edgeID, in: model,
                                orientation: coedge.orientation, onto: frame, tolerance: tolerance, using: &execution)
                            try OriginalParameterQueryStorage.append(BRepDrawingProjectedUse(bodyID: bodyID, shellID: shellID,
                                faceID: faceID, loopID: loopID, coedgeOrientation: coedge.orientation, edge: edge), to: &uses, using: &execution)
                        }
                    }
                }
            }
        }
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: MemoryLayout<BRepDrawingSourceSnapshot>.stride)
        return BRepDrawingProjection(sourceDocument: evaluated.document,
            configuration: evaluated.configuration, frame: frame, uses: uses,
            sourceSnapshot: BRepDrawingSourceSnapshot(evaluated))
    }
}
