import HashTreeCollections
import CADCore
import CADGeometry

/// Publishes one parameter-preserving original image under a retained flat word.
struct ShapeAffineWordImageBuilder {
    func transform(_ source: BRepModel, by word: OriginalAffineOperationWord,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> BRepModel {
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0, remainingSourceDepth > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: tolerance, message: "Original word image requires valid caller depth admission.")
        }
        try word.validateOriginal(tolerance: tolerance, usage: &execution)
        let prepared = try word.prepared(usage: &execution)
        var result = source
        for (id, vertex) in source.vertices {
            try execution.consumeWork(1)
            let point = try prepared.applying(to: vertex.point, usage: &execution)
            try point.validate()
            result.vertices[id] = Vertex(id: id, point: point)
        }
        for (id, curve) in source.geometry.curves {
            try execution.consumeWork(1)
            result.geometry.curves[id] = .originalAffineWord(try OriginalAffineWordCurve3D(
                source: curve, operationWord: word, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &execution))
        }
        for (id, surface) in source.geometry.surfaces {
            try execution.consumeWork(1)
            result.geometry.surfaces[id] = .procedural(.originalAffineWord(
                try OriginalAffineWordSurface3D(source: surface, operationWord: word,
                    tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &execution)))
        }
        for (id, face) in source.faces {
            try execution.consumeWork(1)
            guard let support = source.geometry.surfaces[face.surfaceID],
                case .procedural(.originalAffineWord(let target))? = result.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Original word image lacks its face support.")
            }
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard var loop = source.loops[loopID] else {
                    throw TopologyError.missingReference("Original word image lacks its face-local loop.")
                }
                let bytes = loop.coedges.count.multipliedReportingOverflow(by: MemoryLayout<Coedge>.stride)
                guard !bytes.overflow else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                        tolerance: tolerance, message: "Original word loop storage overflows.")
                }
                try execution.retainStorage(bytes:bytes.partialValue)
                for index in loop.coedges.indices {
                    try execution.consumeWork(1)
                    guard let curve = loop.coedges[index].surfaceParameterCurve else { continue }
                    loop.coedges[index].surfaceParameterCurve = .originalAffineWord(
                        try OriginalAffineWordSurfaceParameterCurve(
                            source: SurfaceLiftCurve3D(surface: support, parameterCurve: curve),
                            target: target, tolerance: tolerance,
                            remainingSourceDepth: remainingSourceDepth,
                            maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &execution))
                }
                result.loops[loopID] = loop
            }
            var image = face
            if prepared.orientationSign < 0 {
                image.orientation = face.orientation == .forward ? .reversed : .forward
            }
            result.faces[id] = image
        }
        return result
    }
}
