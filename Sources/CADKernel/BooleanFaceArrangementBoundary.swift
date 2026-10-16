import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Foundation

struct BooleanFaceArrangementBoundary: Sendable {
  enum SurfaceSide: Sendable {
    case first
    case second
  }

  let reference: BooleanFaceSplitComponentReference
  let segmentOrdinal: Int
  let faceID: FaceID
  let edge: BRepSewingEdge
  let forwardLeftAction: BooleanRegionSelectionAction
  let forwardRightAction: BooleanRegionSelectionAction
  // A component must partition both faces of its pair or neither, so a
  // kept-kept face is forced to split when its twin face partitions.
  var forcedPartitioning: Bool = false

  var isPartitioning: Bool {
    forcedPartitioning || forwardLeftAction != forwardRightAction
  }

  static func make(
    reference: BooleanFaceSplitComponentReference,
    geometry: BooleanFaceSplitComponentGeometry,
    face: Face,
    surfaceSide: SurfaceSide,
    regionSelectionGraph: BooleanRegionSelectionGraph,
    parentSubshapeIDs: [SubshapeID],
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> [BooleanFaceArrangementBoundary] {
        try execution.consumeWork(1)
    try tolerance.validate()
    if case .tangent = geometry { return [] }
    if case .coincident = geometry {
      throw KernelError(
        phase: .topology,
        code: .unsupportedCapability,
        tolerance: tolerance,
        message: "Coincident Boolean faces require explicit coincident-region ownership resolution."
      )
    }
    let actions = try resolvedActions(
      reference: reference,
      face: face,
      regionSelectionGraph: regionSelectionGraph,
      tolerance: tolerance
    , using: &execution)
    let edges = try edges(reference: reference, geometry: geometry, faceID: face.id,
      surfaceSide: surfaceSide, parentSubshapeIDs: parentSubshapeIDs, tolerance: tolerance, using: &execution)
    return try OriginalParameterQueryStorage.map(edges.enumerated(), using: &execution) { entry, execution in
      let (segmentOrdinal, edge) = entry
      return BooleanFaceArrangementBoundary(
        reference: reference,
        segmentOrdinal: segmentOrdinal,
        faceID: face.id,
        edge: edge,
        forwardLeftAction: face.orientation == .forward
          ? actions.positive
          : actions.negative,
        forwardRightAction: face.orientation == .forward
          ? actions.negative
          : actions.positive
      )
    }
  }

  /// Exact intersection edges, shared by solid Boolean and sheet half-space arrangements.
  static func edges(
    reference: BooleanFaceSplitComponentReference,
    geometry: BooleanFaceSplitComponentGeometry,
    faceID: FaceID,
    surfaceSide: SurfaceSide,
    parentSubshapeIDs: [SubshapeID],
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> [BRepSewingEdge] {
        try execution.consumeWork(1)
    let edges: [BRepSewingEdge]
    switch geometry {
    case .transverseSegment(let start, let end):
      edges = [
        try lineEdge(
          start: start,
          end: end,
          surfaceSide: surfaceSide,
          stableID: stableID(reference, faceID: faceID, segmentOrdinal: 0),
          parentSubshapeIDs: parentSubshapeIDs,
          tolerance: tolerance
        , using: &execution)
      ]
    case .trimmedCurve(let chain):
      try execution.retainKernelValues(count: chain.segments.count, stride: MemoryLayout<(Int, BooleanTrimmedFaceIntersection)>.stride)
      edges = try OriginalParameterQueryStorage.map(Array(chain.segments.enumerated()), using: &execution) { entry, execution in
        let (segmentOrdinal, intersection) = entry
        return try trimmedIntersectionEdge(
          intersection,
          surfaceSide: surfaceSide,
          stableID: stableID(
            reference,
            faceID: faceID,
            segmentOrdinal: segmentOrdinal
          ),
          parentSubshapeIDs: parentSubshapeIDs,
          tolerance: tolerance
        , using: &execution)
      }
    case .closedCurve(let intersection):
      edges = try closedIntersectionEdges(
        intersection,
        surfaceSide: surfaceSide,
        reference: reference,
        faceID: faceID,
        parentSubshapeIDs: parentSubshapeIDs,
        tolerance: tolerance
      , using: &execution)
    case .tangent, .coincident:
      return []
    }
    return edges
  }

  private static func resolvedActions(
    reference: BooleanFaceSplitComponentReference,
    face: Face,
    regionSelectionGraph: BooleanRegionSelectionGraph,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> (negative: BooleanRegionSelectionAction, positive: BooleanRegionSelectionAction) {
        try execution.consumeWork(1)
    var decisions: [BooleanRegionSelectionGraph.Decision] = []
    for decision in regionSelectionGraph.decisions {
      try execution.consumeWork(1)
      if decision.sample.facePair == reference.facePair && decision.sample.componentID == reference.componentID && decision.sample.sourceFaceID == face.id {
        try OriginalParameterQueryStorage.append(decision, to: &decisions, using: &execution)
      }
    }
    guard decisions.count == 2,
      Set(decisions.map(\.sample.side)) == Set([.negative, .positive]),
      decisions.allSatisfy({ $0.action != .partitionBoundary }),
      let negativeAction = decisions.first(where: {
        $0.sample.side == .negative
      })?.action,
      let positiveAction = decisions.first(where: {
        $0.sample.side == .positive
      })?.action
    else {
      throw KernelError(
        phase: .classification,
        code: .classificationFailure,
        tolerance: tolerance,
        message:
          "Each Boolean arrangement boundary requires resolved decisions on both face regions."
      )
    }
    return (negativeAction, positiveAction)
  }

  private static func lineEdge(
    start: BooleanUVPoint,
    end: BooleanUVPoint,
    surfaceSide: SurfaceSide,
    stableID: String,
    parentSubshapeIDs: [SubshapeID],
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> BRepSewingEdge {
        try execution.consumeWork(1)
    let offset = end.point - start.point
    let length = offset.length
    let direction = try offset.normalized(tolerance: tolerance.distance)
    let startParameter = surfaceParameter(start, side: surfaceSide)
    let endParameter = surfaceParameter(end, side: surfaceSide)
    let parameterDirection = Point2D(
      x: (endParameter.u - startParameter.u) / length,
      y: (endParameter.v - startParameter.v) / length
    )
    guard hypot(parameterDirection.x, parameterDirection.y) > tolerance.distance else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "A transverse Boolean segment is degenerate in face parameter space."
      )
    }
    return BRepSewingEdge(
      stableID: stableID,
      curve: .line(Line3D(origin: start.point, direction: direction)),
      startParameter: 0.0,
      endParameter: length,
      startPoint: start.point,
      endPoint: end.point,
      surfaceParameterCurve: .affine(
        origin: Point2D(x: startParameter.u, y: startParameter.v),
        direction: parameterDirection,
        startParameter: 0.0,
        endParameter: length
      ),
      parentSubshapeIDs: parentSubshapeIDs
    )
  }

  private static func trimmedIntersectionEdge(
    _ intersection: BooleanTrimmedFaceIntersection,
    surfaceSide: SurfaceSide,
    stableID: String,
    parentSubshapeIDs: [SubshapeID],
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> BRepSewingEdge {
        try execution.consumeWork(1)
    let pcurve = surfaceParameterCurve(
      intersection.intersection,
      side: surfaceSide
    )
    let curveDomain = intersection.intersection.curve.parameterDomain
    // A segment of a closed intersection curve can cross the periodic
    // seam, arriving with an end parameter below its start; lifting the
    // end by one period expresses the same span monotonically.
    var endParameter = intersection.endParameter
    if case .periodic(let period) = curveDomain,
      endParameter <= intersection.startParameter
    {
      endParameter += period
    }
    return BRepSewingEdge(
      stableID: stableID,
      curve: intersection.intersection.curve,
      startParameter: intersection.startParameter,
      endParameter: endParameter,
      startPoint: intersection.start.point,
      endPoint: intersection.end.point,
      surfaceParameterCurve: try pcurve.trimmed(
        from: intersection.startParameter,
        to: endParameter,
        curveDomain: curveDomain,
        tolerance: tolerance
      , using: &execution),
      parentSubshapeIDs: parentSubshapeIDs
    )
  }

  private static func closedIntersectionEdges(
    _ intersection: BooleanClosedFaceIntersection,
    surfaceSide: SurfaceSide,
    reference: BooleanFaceSplitComponentReference,
    faceID: FaceID,
    parentSubshapeIDs: [SubshapeID],
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> [BRepSewingEdge] {
        try execution.consumeWork(1)
    let bounds = try parameterBounds(
      intersection.intersection.curve.parameterDomain,
      tolerance: tolerance
    , using: &execution)
    let midpoint = bounds.lower + (bounds.upper - bounds.lower) * 0.5
    let curve = intersection.intersection.curve
    let pcurve = surfaceParameterCurve(intersection.intersection, side: surfaceSide)
    let firstPoint = try curve.pointAssumingValid(
      at: bounds.lower,
      tolerance: tolerance
    , using: &execution)
    let midpointPoint = try curve.pointAssumingValid(
      at: midpoint,
      tolerance: tolerance
    , using: &execution)
    let evaluatedEndPoint = try curve.pointAssumingValid(
      at: bounds.upper,
      tolerance: tolerance
    , using: &execution)
    let endPoint =
      intersection.intersection.truth
        .certifiedComponentClosure == true
      ? firstPoint
      : evaluatedEndPoint
    let segments = [
      (bounds.lower, midpoint, firstPoint, midpointPoint),
      (midpoint, bounds.upper, midpointPoint, endPoint),
    ]
    try execution.retainKernelValues(count: segments.count, stride: MemoryLayout<(Int, (Double, Double, Point3D, Point3D))>.stride)
    return try OriginalParameterQueryStorage.map(Array(segments.enumerated()), using: &execution) { entry, execution in
      let (segmentOrdinal, segment) = entry
      return BRepSewingEdge(
        stableID: stableID(
          reference,
          faceID: faceID,
          segmentOrdinal: segmentOrdinal
        ),
        curve: curve,
        startParameter: segment.0,
        endParameter: segment.1,
        startPoint: segment.2,
        endPoint: segment.3,
        surfaceParameterCurve: try pcurve.trimmed(
          from: segment.0,
          to: segment.1,
          curveDomain: curve.parameterDomain,
          tolerance: tolerance
        , using: &execution),
        parentSubshapeIDs: parentSubshapeIDs
      )
    }
  }

  private static func surfaceParameterCurve(
    _ intersection: SurfaceSurfaceIntersectionCurve,
    side: SurfaceSide
  ) -> SurfaceParameterCurve {
    switch side {
    case .first:
      return intersection.firstSurfaceParameterCurve
    case .second:
      return intersection.secondSurfaceParameterCurve
    }
  }

  private static func surfaceParameter(
    _ point: BooleanUVPoint,
    side: SurfaceSide
  ) -> SurfaceParameter {
    switch side {
    case .first:
      return SurfaceParameter(u: point.targetU, v: point.targetV)
    case .second:
      return SurfaceParameter(u: point.toolU, v: point.toolV)
    }
  }

  private static func parameterBounds(
    _ domain: ParameterDomain,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> (lower: Double, upper: Double) {
        try execution.consumeWork(1)
    switch domain {
    case .closed(let lower, let upper):
      return (lower, upper)
    case .periodic(let period):
      return (0.0, period)
    case .unbounded:
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A closed Boolean arrangement cannot consume an unbounded curve."
      )
    }
  }

  private static func stableID(
    _ reference: BooleanFaceSplitComponentReference,
    faceID: FaceID,
    segmentOrdinal: Int
  ) -> String {
    "face-intersection:\(reference.facePair.targetFaceID):\(reference.facePair.toolFaceID):\(reference.componentID.ordinal):face:\(faceID):segment:\(segmentOrdinal)"
  }
}
