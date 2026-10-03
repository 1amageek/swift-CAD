import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Where an Isoparam line through a point of a face lies: the point's parameter along the line's
/// direction as a fraction of the face's extent, the fraction `IsoparamFeature` takes.
public struct IsoparamPlacementQuery: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The fraction, in (0, 1), of the face's extent along `direction` at the face point nearest
    /// `point`; refused when that point lies on the face's border, where no line can be imprinted.
    public func fraction(
        at point: Point3D,
        on face: SurfaceReference,
        direction: SurfaceParameterDirection,
        in document: EvaluatedDocument
    ) throws -> Double {
        let projection = try SurfaceQueryEvaluator(tolerance: tolerance).closestPoint(to: point, on: face, in: document)
        guard case let .face(faceID) = try document.topologyReference(for: face.subshape) else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "An Isoparam line lies on a face.")
        }
        let bounds = try BRepFaceCurveClipper.parameterBounds(
            of: faceID, model: document.brep, sourceSubshapes: document.subshapes.entries, tolerance: tolerance
        )
        let (range, value) = direction == .u
            ? (bounds.u, projection.parameterReference.u)
            : (bounds.v, projection.parameterReference.v)
        let width = range.upperBound - range.lowerBound
        guard width > 0 else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "The face has no extent along the line's direction.")
        }
        let fraction = (value - range.lowerBound) / width
        guard fraction > 0, fraction < 1 else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance,
                              message: "An Isoparam line through the face's border imprints nothing.")
        }
        return fraction
    }
}
