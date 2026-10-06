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
    // Lower correspondence/seam/chart-lift callbacks and complete Boolean SSI admission
    // must be closed before the full placed invocation resource contract is complete.
    func make(_ placement: BRepDrawingPlacement, in source: BRepModel,
              maximumSourceEntities: Int, maximumPreparationWork: Int,
              tolerance: ModelingTolerance, remainingSourceDepth: Int = 16,
              maximumSubdivisionDepth: Int = 32, maximumAlgebraicDepth: Int? = nil) throws -> Result {
        if let maximumAlgebraicDepth, !(0...32).contains(maximumAlgebraicDepth) {
            throw failure(.invalidInput, "Original body image algebraic depth is invalid.", tolerance)
        }
        guard remainingSourceDepth > 0, remainingSourceDepth <= 16,
              maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32,
              maximumSourceEntities > 0, maximumPreparationWork > 0,
              let body = source.bodies[placement.bodyID] else {
            throw failure(.invalidInput, "Placed section body or preparation capacities are invalid.", tolerance)
        }
        let usage = BRepDrawingPreparationUsage(maximumWork: maximumPreparationWork,
            maximumEntities: maximumSourceEntities, tolerance: tolerance)
        func consume() throws { try usage.consume() }
        func retain() throws { try usage.retain() }
        var wordAdmission = BRepDrawingWordPreparationAdmission(owner: usage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        let reflected: Bool
        if let word = placement.operationWord {
            if let maximumAlgebraicDepth {
                try word.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &wordAdmission)
            } else { try word.validateOriginal(tolerance: tolerance, usage: &wordAdmission) }
            reflected = word.orientationSign < 0
        } else {
            reflected = try placement.transform.originalDeterminantSign(consumeWork: consume) == .negative
        }
        let preparedWord = try placement.operationWord?.prepared(usage: &wordAdmission)
        var image = BRepModel()
        try retain(); image.bodies[body.id] = body
        for shellID in body.shellIDs {
            try consume()
            if image.shells[shellID] != nil { continue }
            guard let shell = source.shells[shellID] else {
                throw failure(.missingReference, "Placed section original shell is absent.", tolerance)
            }
            try retain(); image.shells[shellID] = shell
            for faceID in shell.faceIDs {
                try consume()
                if image.faces[faceID] != nil { continue }
                guard var face = source.faces[faceID],
                      let surface = source.geometry.surfaces[face.surfaceID] else {
                    throw failure(.missingReference, "Placed section original face law is absent.", tolerance)
                }
                if image.geometry.surfaces[face.surfaceID] == nil {
                    try retain()
                    if let word = placement.operationWord {
                        image.geometry.surfaces[face.surfaceID] = .procedural(.originalAffineWord(try OriginalAffineWordSurface3D(
                            source: surface, operationWord: word, tolerance: tolerance,
                            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &wordAdmission)))
                    } else {
                        image.geometry.surfaces[face.surfaceID] = .affineImage(try OriginalImageSurface3D(
                            source: surface, transform: placement.transform, tolerance: tolerance,
                            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                            consumeWork: { try usage.consume() }))
                    }
                }
                if reflected { face.orientation = face.orientation == .forward ? .reversed : .forward }
                try retain(); image.faces[faceID] = face
                for loopID in face.loops {
                    try consume()
                    if image.loops[loopID] != nil { continue }
                    guard let loop = source.loops[loopID] else {
                        throw failure(.missingReference, "Placed section original trim loop is absent.", tolerance)
                    }
                    // Directed coedges and native UV pcurves retain their original source laws.
                    try retain(); image.loops[loopID] = loop
                    for coedge in loop.coedges {
                        try consume()
                        if image.edges[coedge.edgeID] != nil { continue }
                        guard let edge = source.edges[coedge.edgeID],
                              let curve = source.geometry.curves[edge.curveID] else {
                            throw failure(.missingReference, "Placed section original edge law is absent.", tolerance)
                        }
                        if image.geometry.curves[edge.curveID] == nil {
                            try retain()
                            if let word = placement.operationWord {
                                image.geometry.curves[edge.curveID] = .originalAffineWord(try OriginalAffineWordCurve3D(
                                    source: curve, operationWord: word, tolerance: tolerance,
                                    remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &wordAdmission))
                            } else {
                                image.geometry.curves[edge.curveID] = .affineImage(try AffineImageCurve3D(
                                    source: curve, transform: placement.transform, tolerance: tolerance,
                                    remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                                    consumeWork: { try usage.consume() }))
                            }
                        }
                        try retain(); image.edges[coedge.edgeID] = edge
                        for vertexID in [edge.startVertexID, edge.endVertexID] {
                            try consume()
                            if image.vertices[vertexID] != nil { continue }
                            guard let vertex = source.vertices[vertexID] else {
                                throw failure(.missingReference, "Placed section original vertex is absent.", tolerance)
                            }
                            try retain()
                            let point: Point3D
                            if let preparedWord { point = try preparedWord.applying(to: vertex.point, usage: &wordAdmission) }
                            else { point = placement.transform.applying(to: vertex.point) }
                            try point.validate()
                            image.vertices[vertexID] = Vertex(id: vertexID, point: point)
                        }
                    }
                }
            }
        }
        // This validates the represented endpoint correspondence without replacing retained laws.
        _ = try ValidatedBRepModel(image, tolerance: tolerance, validationLevel: .exact,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: { try usage.consume() }, consumeStorage: { try usage.consume($0) })
        return Result(model: image, consumedWork: usage.consumedWork, retainedEntities: usage.retainedEntities)
    }

    private func failure(_ code: KernelError.Code, _ message: String,
                         _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
