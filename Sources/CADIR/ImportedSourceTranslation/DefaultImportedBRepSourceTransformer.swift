import HashTreeCollections
import CADCore
import CADGeometry
import CADTopology

/// Retains original spatial and chart laws while transforming an imported source atomically.
public struct DefaultImportedBRepSourceTransformer: ImportedBRepSourceTransforming {
    public init() {}

    public func applying(_ transform: AffineTransform3D, to source: ImportedBRepFeature,
        tolerance: ModelingTolerance) throws -> ImportedBRepFeature {
        var execution = try BRepModel.originalValidationExecution()
        return try applying(transform, to: source, tolerance: tolerance, using: &execution)
    }

    public func applying(_ transform: AffineTransform3D, to source: ImportedBRepFeature,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ImportedBRepFeature {
        try source.validate(tolerance: tolerance, using: &execution)
        let reverses = try transform.originalDeterminantSign(using: &execution) == .negative
        var model = source.model
        try execution.retainStorage(count: model.vertices.count, stride: MemoryLayout<VertexID>.stride)
        let vertexIDs = try model.vertices.keys.sorted { first, second in
            try execution.consumeWork(1); return first < second
        }
        for id in vertexIDs {
            try execution.consumeWork(1)
            guard var vertex = model.vertices[id] else {
                throw TopologyError.missingReference("Original imported affine image vertex is missing.")
            }
            vertex.point = transform.applying(to: vertex.point)
            try vertex.point.validate()
            try execution.retainStorage(count: 1, stride: MemoryLayout<(VertexID, Vertex)>.stride)
            model.vertices[id] = vertex
        }
        try execution.retainStorage(count: model.geometry.curves.count, stride: MemoryLayout<CurveID>.stride)
        let curveIDs = try model.geometry.curves.keys.sorted { first, second in
            try execution.consumeWork(1); return first < second
        }
        for id in curveIDs {
            try execution.consumeWork(1)
            guard let original = source.model.geometry.curves[id] else {
                throw TopologyError.missingReference("Original imported affine image curve is missing.")
            }
            let image = try AffineImageCurve3D(source: original, transform: transform,
                tolerance: tolerance, using: &execution)
            try execution.retainStorage(count: 1, stride: MemoryLayout<(CurveID, Curve3D)>.stride)
            model.geometry.curves[id] = .affineImage(image)
        }
        try execution.retainStorage(count: model.geometry.surfaces.count, stride: MemoryLayout<SurfaceID>.stride)
        let surfaceIDs = try model.geometry.surfaces.keys.sorted { first, second in
            try execution.consumeWork(1); return first < second
        }
        for id in surfaceIDs {
            try execution.consumeWork(1)
            guard let original = source.model.geometry.surfaces[id] else {
                throw TopologyError.missingReference("Original imported affine image surface is missing.")
            }
            let image = try OriginalImageSurface3D(source: original, transform: transform,
                tolerance: tolerance, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
            try execution.retainStorage(count: 1, stride: MemoryLayout<(SurfaceID, Surface3D)>.stride)
            model.geometry.surfaces[id] = .parameterImage(image)
        }
        try execution.retainStorage(count: model.faces.count, stride: MemoryLayout<FaceID>.stride)
        let faceIDs = try model.faces.keys.sorted { first, second in
            try execution.consumeWork(1); return first < second
        }
        for faceID in faceIDs {
            try execution.consumeWork(1)
            guard var face = source.model.faces[faceID],
                let originalSurface = source.model.geometry.surfaces[face.surfaceID],
                let targetSurface = model.geometry.surfaces[face.surfaceID],
                case let .procedural(.originalImage(image)) = targetSurface else {
                throw TopologyError.missingReference("Original imported affine image face support is missing.")
            }
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard var loop = source.model.loops[loopID] else {
                    throw TopologyError.missingReference("Original imported affine image face loop is missing.")
                }
                try execution.retainStorage(count: loop.coedges.count, stride: MemoryLayout<Coedge>.stride)
                for index in loop.coedges.indices {
                    try execution.consumeWork(1)
                    guard let pcurve = loop.coedges[index].surfaceParameterCurve else {
                        throw TopologyError.missingReference("Original imported affine image requires every exact coedge pcurve.")
                    }
                    loop.coedges[index].surfaceParameterCurve = .originalImage(try OriginalImageSurfaceParameterCurve(
                        source: SurfaceLiftCurve3D(surface: originalSurface, parameterCurve: pcurve),
                        targetImage: image, tolerance: tolerance, using: &execution))
                }
                try execution.retainStorage(count: 1, stride: MemoryLayout<(LoopID, Loop)>.stride)
                model.loops[loopID] = loop
            }
            if reverses { face.orientation = face.orientation == .forward ? .reversed : .forward }
            try execution.retainStorage(count: 1, stride: MemoryLayout<(FaceID, Face)>.stride)
            model.faces[faceID] = face
        }
        let transformed = ImportedBRepFeature(model: model, sourceUnits: source.sourceUnits)
        try transformed.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return transformed
    }
}
