import HashTreeCollections
import CADCore
import CADGeometry

/// Publishes one parameter-preserving original image under a retained flat word.
struct ShapeAffineWordImageBuilder {
    func transform(_ source: BRepModel, by word: OriginalAffineOperationWord,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> BRepModel {
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0, remainingSourceDepth > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: tolerance, message: "Original word image requires valid caller depth admission.")
        }
        var usage = ShapeAffineWordAdmission(maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        try word.validateOriginal(tolerance: tolerance, usage: &usage)
        let prepared = try word.prepared(usage: &usage)
        var result = source
        for (id, vertex) in source.vertices {
            try usage.visitExactCell(depth: 0)
            let point = try prepared.applying(to: vertex.point, usage: &usage)
            try point.validate()
            result.vertices[id] = Vertex(id: id, point: point)
        }
        for (id, curve) in source.geometry.curves {
            try usage.visitExactCell(depth: 0)
            result.geometry.curves[id] = .originalAffineWord(try OriginalAffineWordCurve3D(
                source: curve, operationWord: word, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage))
        }
        for (id, surface) in source.geometry.surfaces {
            try usage.visitExactCell(depth: 0)
            result.geometry.surfaces[id] = .procedural(.originalAffineWord(
                try OriginalAffineWordSurface3D(source: surface, operationWord: word,
                    tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)))
        }
        for (id, face) in source.faces {
            try usage.visitExactCell(depth: 0)
            guard let support = source.geometry.surfaces[face.surfaceID],
                case .procedural(.originalAffineWord(let target))? = result.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Original word image lacks its face support.")
            }
            for loopID in face.loops {
                try usage.visitExactCell(depth: 0)
                guard var loop = source.loops[loopID] else {
                    throw TopologyError.missingReference("Original word image lacks its face-local loop.")
                }
                let bytes = loop.coedges.count.multipliedReportingOverflow(by: MemoryLayout<Coedge>.stride)
                guard !bytes.overflow else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                        tolerance: tolerance, message: "Original word loop storage overflows.")
                }
                try usage.retainBytes(bytes.partialValue)
                for index in loop.coedges.indices {
                    try usage.visitExactCell(depth: 0)
                    guard let curve = loop.coedges[index].surfaceParameterCurve else { continue }
                    loop.coedges[index].surfaceParameterCurve = .originalAffineWord(
                        try OriginalAffineWordSurfaceParameterCurve(
                            source: SurfaceLiftCurve3D(surface: support, parameterCurve: curve),
                            target: target, tolerance: tolerance,
                            remainingSourceDepth: remainingSourceDepth,
                            maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage))
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
