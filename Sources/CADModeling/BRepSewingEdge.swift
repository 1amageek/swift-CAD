import CADCore
import CADGeometry
import CADIR

/// One exact oriented boundary edge in a sewing request.
public struct BRepSewingEdge: Sendable {
    public let stableID: String
    public let curve: Curve3D
    public let startParameter: Double
    public let endParameter: Double
    public let startPoint: Point3D
    public let endPoint: Point3D
    public let surfaceParameterCurve: SurfaceParameterCurve
    public let parentSubshapeIDs: [SubshapeID]
    public let startVertexParentSubshapeIDs: [SubshapeID]
    public let endVertexParentSubshapeIDs: [SubshapeID]

    public init(
        stableID: String,
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        startPoint: Point3D,
        endPoint: Point3D,
        surfaceParameterCurve: SurfaceParameterCurve,
        parentSubshapeIDs: [SubshapeID] = [],
        startVertexParentSubshapeIDs: [SubshapeID] = [],
        endVertexParentSubshapeIDs: [SubshapeID] = []
    ) {
        self.stableID = stableID
        self.curve = curve
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.surfaceParameterCurve = surfaceParameterCurve
        self.parentSubshapeIDs = Array(Set(parentSubshapeIDs)).sorted()
        self.startVertexParentSubshapeIDs = Array(Set(startVertexParentSubshapeIDs)).sorted()
        self.endVertexParentSubshapeIDs = Array(Set(endVertexParentSubshapeIDs)).sorted()
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard stableID.isEmpty == false,
              startParameter.isFinite,
              endParameter.isFinite,
              abs(endParameter - startParameter) > max(tolerance.angle, Double.ulpOfOne),
              startPoint.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance) == false,
              parentSubshapeIDs.allSatisfy(\.isValid),
              startVertexParentSubshapeIDs.allSatisfy(\.isValid),
              endVertexParentSubshapeIDs.allSatisfy(\.isValid) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sewing edge identity, trim, endpoints, or provenance is invalid."
            )
        }
        try curve.validate(tolerance: tolerance)
        guard try curve.parameterDomain.containsSpan(
            from: startParameter,
            to: endParameter,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sewing edge trim lies outside its exact curve domain."
            )
        }
        let exactStart = try curve.point(at: startParameter, tolerance: tolerance)
        let exactEnd = try curve.point(at: endParameter, tolerance: tolerance)
        // Endpoints carry canonical junction points snapped onto source
        // boundary geometry, up to eight tolerances from the exact curve.
        guard exactStart.isApproximatelyEqual(to: startPoint, tolerance: tolerance.distance * 8.0),
              exactEnd.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance * 8.0) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Sewing edge endpoints do not match its exact curve trim."
            )
        }
        try surfaceParameterCurve.validate(on: surface, tolerance: tolerance)
        let parameterStart = try surfaceParameterCurve.startParameter(tolerance: tolerance)
        let parameterEnd = try surfaceParameterCurve.endParameter(tolerance: tolerance)
        let surfaceStart = try surface.point(
            u: parameterStart.u,
            v: parameterStart.v,
            tolerance: tolerance
        )
        let surfaceEnd = try surface.point(
            u: parameterEnd.u,
            v: parameterEnd.v,
            tolerance: tolerance
        )
        guard surfaceStart.isApproximatelyEqual(to: startPoint, tolerance: tolerance.distance * 8.0),
              surfaceEnd.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance * 8.0) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Sewing edge pcurve endpoints do not match its 3D endpoints."
            )
        }
    }
}
