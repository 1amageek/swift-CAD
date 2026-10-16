import CADCore
import CADGeometry

public protocol OriginalPlanarContourContactPreparing: Sendable {
    func prepare(contours: [OriginalPlanarContour], on plane: Plane3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> PreparedOriginalPlanarContourContacts
}
