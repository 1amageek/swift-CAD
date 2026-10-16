import CADCore
import CADGeometry
import CADTopology

/// Retains one original body's closure under an authored nonsingular affine law.
struct BRepDrawingBodyImage {
    struct Result {
        let model: BRepModel
        let consumedWork: Int
        let retainedEntities: Int
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The public placed-section caller bounds this
    // owner's closure, original image constructors and bounded BRep preparation.
    // Lower correspondence/seam/chart-lift proof coverage and complete Boolean SSI admission
    // must be closed before the full placed invocation resource contract is complete.
    func make(_ placement: BRepDrawingPlacement, in source: BRepModel,
              maximumSourceEntities: Int, maximumPreparationWork: Int,
              tolerance: ModelingTolerance, remainingSourceDepth: Int = 16,
              maximumSubdivisionDepth: Int = 32, maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> Result {
        if let maximumAlgebraicDepth, !(0...32).contains(maximumAlgebraicDepth) {
            throw failure(.invalidInput, "Original body image algebraic depth is invalid.", tolerance)
        }
        guard remainingSourceDepth > 0, remainingSourceDepth <= 16,
              maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32,
              maximumSourceEntities > 0, maximumPreparationWork > 0,
              let body = source.bodies[placement.bodyID] else {
            throw failure(.invalidInput, "Placed section body or preparation capacities are invalid.", tolerance)
        }
        let contribution = try execution.makeContributionHandle(workLimit: maximumPreparationWork)
        return try execution.withContributionScope(contribution) { execution in
        let initialWork = execution.localWork
        var retainedEntities = 0
        func retain() throws {
            guard retainedEntities < maximumSourceEntities else {
                throw failure(.resourceLimitExceeded, "Placed section original entity capacity exhausted.", tolerance)
            }
            retainedEntities += 1
        }
        let reflected: Bool
        if let word = placement.operationWord {
            if let maximumAlgebraicDepth {
                try word.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &execution)
            } else { try word.validateOriginal(tolerance: tolerance, usage: &execution) }
            reflected = word.orientationSign < 0
        } else {
            reflected = try placement.transform.originalDeterminantSign(using: &execution) == .negative
        }
        let preparedWord = try placement.operationWord?.prepared(usage: &execution)
        var image = BRepModel()
        try retain(); try OriginalParameterQueryStorage.set(body, for: body.id, in: &image.bodies, using: &execution)
        for shellID in body.shellIDs {
            try execution.consumeWork(1)
            if image.shells[shellID] != nil { continue }
            guard let shell = source.shells[shellID] else {
                throw failure(.missingReference, "Placed section original shell is absent.", tolerance)
            }
            try retain(); try OriginalParameterQueryStorage.set(shell, for: shellID, in: &image.shells, using: &execution)
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                if image.faces[faceID] != nil { continue }
                guard var face = source.faces[faceID],
                      let surface = source.geometry.surfaces[face.surfaceID] else {
                    throw failure(.missingReference, "Placed section original face law is absent.", tolerance)
                }
                if image.geometry.surfaces[face.surfaceID] == nil {
                    try retain()
                    if let word = placement.operationWord {
                        try OriginalParameterQueryStorage.set(.procedural(.originalAffineWord(try OriginalAffineWordSurface3D(
                            source: surface, operationWord: word, tolerance: tolerance,
                            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution))), for: face.surfaceID, in: &image.geometry.surfaces, using: &execution)
                    } else {
                        try OriginalParameterQueryStorage.set(.affineImage(try OriginalImageSurface3D(
                            source: surface, transform: placement.transform, tolerance: tolerance,
                            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                            using: &execution)), for: face.surfaceID, in: &image.geometry.surfaces, using: &execution)
                    }
                }
                if reflected { face.orientation = face.orientation == .forward ? .reversed : .forward }
                try retain(); try OriginalParameterQueryStorage.set(face, for: faceID, in: &image.faces, using: &execution)
                for loopID in face.loops {
                    try execution.consumeWork(1)
                    if image.loops[loopID] != nil { continue }
                    guard let loop = source.loops[loopID] else {
                        throw failure(.missingReference, "Placed section original trim loop is absent.", tolerance)
                    }
                    // Directed coedges and native UV pcurves retain their original source laws.
                    try retain(); try OriginalParameterQueryStorage.set(loop, for: loopID, in: &image.loops, using: &execution)
                    for coedge in loop.coedges {
                        try execution.consumeWork(1)
                        if image.edges[coedge.edgeID] != nil { continue }
                        guard let edge = source.edges[coedge.edgeID],
                              let curve = source.geometry.curves[edge.curveID] else {
                            throw failure(.missingReference, "Placed section original edge law is absent.", tolerance)
                        }
                        if image.geometry.curves[edge.curveID] == nil {
                            try retain()
                            if let word = placement.operationWord {
                                try OriginalParameterQueryStorage.set(.originalAffineWord(try OriginalAffineWordCurve3D(
                                    source: curve, operationWord: word, tolerance: tolerance,
                                    remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution)), for: edge.curveID, in: &image.geometry.curves, using: &execution)
                            } else {
                                try OriginalParameterQueryStorage.set(.affineImage(try AffineImageCurve3D(
                                    source: curve, transform: placement.transform, tolerance: tolerance,
                                    remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                                    using: &execution)), for: edge.curveID, in: &image.geometry.curves, using: &execution)
                            }
                        }
                        try retain(); try OriginalParameterQueryStorage.set(edge, for: coedge.edgeID, in: &image.edges, using: &execution)
                        for endpoint in 0..<2 {
                            let vertexID = endpoint == 0 ? edge.startVertexID : edge.endVertexID
                            try execution.consumeWork(1)
                            if image.vertices[vertexID] != nil { continue }
                            guard let vertex = source.vertices[vertexID] else {
                                throw failure(.missingReference, "Placed section original vertex is absent.", tolerance)
                            }
                            try retain()
                            let point: Point3D
                            if let preparedWord { point = try preparedWord.applying(to: vertex.point, usage: &execution) }
                            else { point = placement.transform.applying(to: vertex.point) }
                            try point.validate()
                            try OriginalParameterQueryStorage.set(Vertex(id: vertexID, point: point), for: vertexID, in: &image.vertices, using: &execution)
                        }
                    }
                }
            }
        }
        // This validates the represented endpoint correspondence without replacing retained laws.
        _ = try ValidatedBRepModel(image, tolerance: tolerance, validationLevel: .exact,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            using: &execution)
        return Result(model: image, consumedWork: execution.localWork - initialWork, retainedEntities: retainedEntities)
        }
    }

    private func failure(_ code: KernelErrorCode, _ message: String,
                         _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
