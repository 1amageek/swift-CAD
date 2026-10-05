import CADCore
import CADGeometry
import CADTopology

/// Retains original spatial and chart laws while transforming an imported source atomically.
public struct DefaultImportedBRepSourceTransformer: ImportedBRepSourceTransforming {
    public init() {}

    public func applying(_ transform: AffineTransform3D, to source: ImportedBRepFeature,
        tolerance: ModelingTolerance) throws -> ImportedBRepFeature {
        try source.validate(tolerance: tolerance)
        let reverses = try transform.originalDeterminantSign(consumeWork: {
            try Task.checkCancellation()
        }) == .negative
        var model = source.model
        for id in model.vertices.keys.sorted() {
            try Task.checkCancellation()
            guard var vertex = model.vertices[id] else {
                throw TopologyError.missingReference("Original imported affine image vertex is missing.")
            }
            vertex.point = transform.applying(to: vertex.point)
            try vertex.point.validate()
            model.vertices[id] = vertex
        }
        for id in model.geometry.curves.keys.sorted() {
            try Task.checkCancellation()
            guard let original = source.model.geometry.curves[id] else {
                throw TopologyError.missingReference("Original imported affine image curve is missing.")
            }
            model.geometry.curves[id] = .affineImage(try AffineImageCurve3D(
                source: original, transform: transform, tolerance: tolerance))
        }
        for id in model.geometry.surfaces.keys.sorted() {
            try Task.checkCancellation()
            guard let original = source.model.geometry.surfaces[id] else {
                throw TopologyError.missingReference("Original imported affine image surface is missing.")
            }
            model.geometry.surfaces[id] = .parameterImage(try OriginalImageSurface3D(
                source: original, transform: transform, tolerance: tolerance))
        }
        for faceID in model.faces.keys.sorted() {
            try Task.checkCancellation()
            guard var face = source.model.faces[faceID],
                let originalSurface = source.model.geometry.surfaces[face.surfaceID],
                let targetSurface = model.geometry.surfaces[face.surfaceID],
                case let .procedural(.originalImage(image)) = targetSurface else {
                throw TopologyError.missingReference("Original imported affine image face support is missing.")
            }
            for loopID in face.loops {
                guard var loop = source.model.loops[loopID] else {
                    throw TopologyError.missingReference("Original imported affine image face loop is missing.")
                }
                for index in loop.coedges.indices {
                    try Task.checkCancellation()
                    guard let pcurve = loop.coedges[index].surfaceParameterCurve else {
                        throw TopologyError.missingReference("Original imported affine image requires every exact coedge pcurve.")
                    }
                    loop.coedges[index].surfaceParameterCurve = .originalImage(try OriginalImageSurfaceParameterCurve(
                        source: SurfaceLiftCurve3D(surface: originalSurface, parameterCurve: pcurve),
                        targetImage: image, tolerance: tolerance))
                }
                model.loops[loopID] = loop
            }
            if reverses { face.orientation = face.orientation == .forward ? .reversed : .forward }
            model.faces[faceID] = face
        }
        let transformed = ImportedBRepFeature(model: model, sourceUnits: source.sourceUnits)
        try transformed.validate(tolerance: tolerance)
        try Task.checkCancellation()
        return transformed
    }
}
