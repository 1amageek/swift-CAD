import CADCore
import CADGeometry

public protocol OriginalPlanarContourContactPreparing: Sendable {
    func prepare(contours: [OriginalPlanarContour], on plane: Plane3D,
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void)
        throws -> PreparedOriginalPlanarContourContacts
}
