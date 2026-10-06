import CADCore
import CADGeometry
import CADIR
import CADTopology

/// One exact oriented boundary edge in a sewing request.
/// The pcurve uses normalized fraction f. Correspondence validation starts from
/// the spatial parameter startParameter + (endParameter - startParameter) * f
/// and may solve an oriented monotone spatial parameter correspondence.
/// Whole-interval correspondence requires validation; matching endpoints alone
/// does not establish it. Endpoint parent IDs own the generated vertex lineage.
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

  package init(
    stableID: String, curve: Curve3D,
    startParameter: Double, endParameter: Double,
    startPoint: Point3D, endPoint: Point3D,
    surfaceParameterCurve: SurfaceParameterCurve,
    parentSubshapeIDs: [SubshapeID] = [],
    startVertexParentSubshapeIDs: [SubshapeID] = [],
    endVertexParentSubshapeIDs: [SubshapeID] = [],
    consumeWork: @Sendable (Int) throws -> Void,
    consumeStorage: (@Sendable (Int) throws -> Void)?
  ) throws {
    try Task.checkCancellation()
    try consumeWork(0)
    self.stableID = stableID
    self.curve = curve
    self.startParameter = startParameter
    self.endParameter = endParameter
    self.startPoint = startPoint
    self.endPoint = endPoint
    self.surfaceParameterCurve = surfaceParameterCurve
    self.parentSubshapeIDs = try AdmittedSewingProvenance.canonical(parentSubshapeIDs,
      consumeWork: consumeWork, consumeStorage: consumeStorage)
    self.startVertexParentSubshapeIDs = try AdmittedSewingProvenance.canonical(startVertexParentSubshapeIDs,
      consumeWork: consumeWork, consumeStorage: consumeStorage)
    self.endVertexParentSubshapeIDs = try AdmittedSewingProvenance.canonical(endVertexParentSubshapeIDs,
      consumeWork: consumeWork, consumeStorage: consumeStorage)
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
      parentSubshapeIDs.allSatisfy(\.isValid),
      startVertexParentSubshapeIDs.allSatisfy(\.isValid),
      endVertexParentSubshapeIDs.allSatisfy(\.isValid)
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Sewing edge identity, trim, endpoints, or provenance is invalid."
      )
    }
    let kind = try BRepEdgeGeometryClassifier().kind(
      curve: curve, from: startParameter, to: endParameter, tolerance: tolerance)
    if startPoint.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance), kind == .open {
      throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
        message: "A sewing boundary may have coincident endpoints only for a proved closed or singular original span.")
    }
    let validatedCurve = try ValidatedCurve3D(
      curve,
      tolerance: tolerance
    )
    guard
      try validatedCurve.parameterDomain.containsSpan(
        from: startParameter,
        to: endParameter,
        tolerance: tolerance
      )
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Sewing edge trim lies outside its exact curve domain."
      )
    }
    let exactStart = try validatedCurve.point(at: startParameter)
    let exactEnd = try validatedCurve.point(at: endParameter)
    // Topological identity is supplied by loop adjacency and shared-span
    // proof. Coordinates only validate that the realized vertex remains
    // inside the caller's declared distance contract.
    guard exactStart.isApproximatelyEqual(to: startPoint, tolerance: tolerance.distance),
      exactEnd.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance)
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Sewing edge endpoints do not match its exact curve trim."
      )
    }
    try surfaceParameterCurve.validate(on: surface, tolerance: tolerance)
    let surfaceLift = SurfaceLiftCurve3D(surface: surface, parameterCurve: surfaceParameterCurve)
    let surfaceStart = try surfaceLift.point(atNormalizedFraction: 0, tolerance: tolerance)
    let surfaceEnd = try surfaceLift.point(atNormalizedFraction: 1, tolerance: tolerance)
    guard surfaceStart.isApproximatelyEqual(to: startPoint, tolerance: tolerance.distance),
      surfaceEnd.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance)
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Sewing edge pcurve endpoints do not match its 3D endpoints."
      )
    }
  }
}
