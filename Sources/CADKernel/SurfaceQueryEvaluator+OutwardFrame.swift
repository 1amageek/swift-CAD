import CADCore
import CADIR
import CADTopology

extension SurfaceQueryEvaluator {
    /// The point of the face nearest `point` (within the face's trim) and the outward normal there.
    public func outwardFrame(
        nearestTo point: Point3D,
        on reference: SurfaceReference,
        in document: some SurfaceQueryModel,
        options: SurfaceProjectionOptions = SurfaceProjectionOptions()
    ) throws -> SurfaceOutwardFrame {
        let projection = try closestPoint(to: point, on: reference, in: document, options: options)
        return try outwardFrame(projection.frame, on: reference, in: document)
    }

    /// The face point at `parameter` and the outward normal there.
    public func outwardFrame(
        at parameter: SurfaceParameterReference,
        in document: some SurfaceQueryModel
    ) throws -> SurfaceOutwardFrame {
        try outwardFrame(frame(at: parameter, in: document), on: parameter.surface, in: document)
    }

    private func outwardFrame(
        _ frame: SurfaceQueryFrame,
        on reference: SurfaceReference,
        in document: some SurfaceQueryModel
    ) throws -> SurfaceOutwardFrame {
        let resolved = try resolve(reference, in: document)
        guard let face = document.brep.faces[resolved.faceID] else {
            throw FeatureEvaluationError.missingInput("Surface query references a missing face.")
        }
        // A reversed face bounds its body on the other side of its surface.
        let outward = face.orientation == .forward ? frame.normal : frame.normal * -1
        return SurfaceOutwardFrame(parameter: frame.reference, point: frame.point, outwardNormal: outward)
    }
}
