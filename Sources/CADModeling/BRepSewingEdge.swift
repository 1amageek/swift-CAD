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
    using execution: inout OriginalQueryExecution
  ) throws {
    try CurrentTaskCancellationChecker().checkCancellation()
    try execution.consumeWork(1)
    self.stableID = stableID
    self.curve = curve
    self.startParameter = startParameter
    self.endParameter = endParameter
    self.startPoint = startPoint
    self.endPoint = endPoint
    self.surfaceParameterCurve = surfaceParameterCurve
    self.parentSubshapeIDs = try AdmittedSewingProvenance.canonical(parentSubshapeIDs,
      using: &execution)
    self.startVertexParentSubshapeIDs = try AdmittedSewingProvenance.canonical(startVertexParentSubshapeIDs,
      using: &execution)
    self.endVertexParentSubshapeIDs = try AdmittedSewingProvenance.canonical(endVertexParentSubshapeIDs,
      using: &execution)
  }


  public func validate(
    on surface: Surface3D,
    tolerance: ModelingTolerance
  ) throws {

      var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))

      return try validate(on: surface, tolerance: tolerance, using: &execution)

  }

  public func validate(
    on surface: Surface3D,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
    try tolerance.validate()
    try execution.consumeWork(parentSubshapeIDs.count)
    try execution.consumeWork(startVertexParentSubshapeIDs.count)
    try execution.consumeWork(endVertexParentSubshapeIDs.count)
    guard stableID.isEmpty == false,
      startParameter.isFinite,
      endParameter.isFinite,
      abs(endParameter - startParameter) > max(tolerance.angle, Double.ulpOfOne),
      parentSubshapeIDs.allSatisfy({ $0.isValid }),
      startVertexParentSubshapeIDs.allSatisfy({ $0.isValid }),
      endVertexParentSubshapeIDs.allSatisfy({ $0.isValid })
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Sewing edge identity, trim, endpoints, or provenance is invalid."
      )
    }
    let kind = try BRepEdgeGeometryClassifier().kind(
      curve: curve, from: startParameter, to: endParameter, tolerance: tolerance, using: &execution)
    if startPoint.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance), kind == .open {
      throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
        message: "A sewing boundary may have coincident endpoints only for a proved closed or singular original span.")
    }
    let validatedCurve = try ValidatedCurve3D(
      curve,
      tolerance: tolerance
    , using: &execution)
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
    let exactStart = try validatedCurve.point(at: startParameter, using: &execution)
    let exactEnd = try validatedCurve.point(at: endParameter, using: &execution)
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
    try surfaceParameterCurve.validate(on: surface, tolerance: tolerance, using: &execution)
    let surfaceLift = SurfaceLiftCurve3D(surface: surface, parameterCurve: surfaceParameterCurve)
    let surfaceStart = try surfaceLift.point(atNormalizedFraction: 0, tolerance: tolerance, using: &execution)
    let surfaceEnd = try surfaceLift.point(atNormalizedFraction: 1, tolerance: tolerance, using: &execution)
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
