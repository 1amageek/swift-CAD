import CADCore
import CADGeometry
import CADModeling
import CADTopology
import Foundation

enum ExactTrimEdgeIntersectionResult: Sendable {
  case subdivisionPoints([Point3D])
  case coincident
}

struct ExactTrimEdgeIntersector {
  // FIXME(INCOMPLETE_IMPLEMENTATION): Boolean UV splitting, finite coincident
  // contact, Imprint and Natural joins require complete endpoint/critical and
  // continuous-contact producers under the same caller allowance. The complete
  // authored range is retained here; unresolved lower roots must fail rather
  // than drop a sampled endpoint band or publish incomplete empty contacts.
  func intersections(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    sharedSurface: Surface3D? = nil,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> ExactTrimEdgeIntersectionResult {
    do {
      execution.context = execution.context.at(stage: .relation)
      let result = try resolve(using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
    func resolve(using execution: inout OriginalQueryExecution) throws -> ExactTrimEdgeIntersectionResult {
    try execution.consumeWork(1)
    try tolerance.validate()
    let equivalent: Bool
    do {
      equivalent = try spansAreEquivalent(
        first,
        second,
        tolerance: tolerance
      , using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: "whole-span coincidence classification",
        tolerance: tolerance
      )
    }
    if equivalent {
      return .coincident
    }

    if let componentResult = try certifiedComponentIntersections(
      first,
      second,
      tolerance: tolerance
    , using: &execution) {
      return .subdivisionPoints(componentResult)
    }

    if let straightSpanResult = straightSpanIntersections(
      first,
      second,
      tolerance: tolerance
    ) {
      return .subdivisionPoints(straightSpanResult)
    }

    let partitioned: [Point3D]?
    do {
      partitioned = try partitionedCoincidenceIntersections(
        first,
        second,
        sharedSurface: sharedSurface,
        tolerance: tolerance
      , using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: "partitioned coincidence classification",
        tolerance: tolerance
      )
    }
    if let partitioned {
      return .subdivisionPoints(partitioned)
    }

    return .subdivisionPoints(
      try discreteIntersections(
        first,
        second,
        sharedSurface: sharedSurface,
        tolerance: tolerance
      , using: &execution))
      }
  }

  /// Uses the component-completeness certificate retained by analytic
  /// intersection truth. Derived B-spline caches are deliberately absent
  /// from this decision: their bounded residual does not establish either
  /// topological identity or intersection.
  private func certifiedComponentIntersections(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D]? {
    try execution.consumeWork(1)
    guard let firstTruth = certifiedAnalyticPairTruth(first.curve),
      let secondTruth = certifiedAnalyticPairTruth(second.curve),
      let relation = firstTruth.componentRelation(to: secondTruth)
    else {
      return nil
    }
    switch relation {
    case .disjointComponents:
      return []
    case .sameEmbeddedComponent(let isClosed):
      let firstLower = min(first.startParameter, first.endParameter)
      let firstUpper = max(first.startParameter, first.endParameter)
      let secondLower = min(second.startParameter, second.endParameter)
      let secondUpper = max(second.startParameter, second.endParameter)
      let overlapLower = max(firstLower, secondLower)
      let overlapUpper = min(firstUpper, secondUpper)
      if overlapLower <= overlapUpper {
        var points = [
          try first.curve.point(
            at: overlapLower,
            tolerance: tolerance
          , using: &execution)
        ]
        if overlapUpper > overlapLower {
          try OriginalParameterQueryStorage.append(
            try first.curve.point(
              at: overlapUpper,
              tolerance: tolerance
            , using: &execution), to: &points, using: &execution)
        }
        return points
      }
      let firstContainsStart = firstLower == 0.0
      let firstContainsEnd = firstUpper == 1.0
      let secondContainsStart = secondLower == 0.0
      let secondContainsEnd = secondUpper == 1.0
      if isClosed,
        (firstContainsStart && secondContainsEnd)
          || (firstContainsEnd && secondContainsStart)
      {
        return [try first.curve.point(at: 0.0, tolerance: tolerance, using: &execution)]
      }
      return []
    }
  }

  private func certifiedAnalyticPairTruth(
    _ curve: Curve3D
  ) -> CertifiedAnalyticAnalyticIntersectionCurve? {
    guard case .surfaceLift(let lift) = curve,
      case .certifiedAnalyticPair(let parameterCurve) = lift.parameterCurve
    else {
      return nil
    }
    return parameterCurve.intersection
  }

  private func straightSpanIntersections(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    tolerance: ModelingTolerance
  ) -> [Point3D]? {
    guard first.curve.hasExactLinearParameterization,
      second.curve.hasExactLinearParameterization
    else {
      return nil
    }
    let firstDirection = first.endPoint - first.startPoint
    let secondDirection = second.endPoint - second.startPoint
    let firstSquaredLength = firstDirection.dot(firstDirection)
    let secondSquaredLength = secondDirection.dot(secondDirection)
    guard firstSquaredLength > tolerance.distance * tolerance.distance,
      secondSquaredLength > tolerance.distance * tolerance.distance
    else {
      return []
    }

    let offset = second.startPoint - first.startPoint
    let cross = firstDirection.cross(secondDirection)
    let crossSquaredLength = cross.dot(cross)
    let parallelThreshold =
      firstSquaredLength * secondSquaredLength
      * sin(tolerance.angle) * sin(tolerance.angle)
    if crossSquaredLength <= parallelThreshold {
      let lineDistance =
        offset.cross(firstDirection).length
        / sqrt(firstSquaredLength)
      guard lineDistance <= tolerance.distance else { return [] }
      let secondStart = offset.dot(firstDirection) / firstSquaredLength
      let secondEnd =
        (second.endPoint - first.startPoint).dot(firstDirection)
        / firstSquaredLength
      let lower = max(0.0, min(secondStart, secondEnd))
      let upper = min(1.0, max(secondStart, secondEnd))
      let parameterTolerance = tolerance.distance / sqrt(firstSquaredLength)
      guard upper >= lower - parameterTolerance else { return [] }
      let boundedLower = min(max(lower, 0.0), 1.0)
      let boundedUpper = min(max(upper, 0.0), 1.0)
      let lowerPoint = first.startPoint + firstDirection * boundedLower
      guard
        (boundedUpper - boundedLower) * sqrt(firstSquaredLength)
          > tolerance.distance
      else {
        return [lowerPoint]
      }
      return [
        lowerPoint,
        first.startPoint + firstDirection * boundedUpper,
      ]
    }

    let planeDistance = abs(offset.dot(cross)) / sqrt(crossSquaredLength)
    guard planeDistance <= tolerance.distance else { return [] }
    let firstParameter =
      offset.cross(secondDirection).dot(cross)
      / crossSquaredLength
    let secondParameter =
      offset.cross(firstDirection).dot(cross)
      / crossSquaredLength
    let firstParameterTolerance = tolerance.distance / sqrt(firstSquaredLength)
    let secondParameterTolerance = tolerance.distance / sqrt(secondSquaredLength)
    guard firstParameter >= -firstParameterTolerance,
      firstParameter <= 1.0 + firstParameterTolerance,
      secondParameter >= -secondParameterTolerance,
      secondParameter <= 1.0 + secondParameterTolerance
    else {
      return []
    }
    let firstPoint =
      first.startPoint
      + firstDirection * min(max(firstParameter, 0.0), 1.0)
    let secondPoint =
      second.startPoint
      + secondDirection * min(max(secondParameter, 0.0), 1.0)
    guard (firstPoint - secondPoint).length <= tolerance.distance else {
      return []
    }
    return [
      Point3D(
        x: (firstPoint.x + secondPoint.x) * 0.5,
        y: (firstPoint.y + secondPoint.y) * 0.5,
        z: (firstPoint.z + secondPoint.z) * 0.5
      )
    ]
  }

  private func discreteIntersections(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    sharedSurface: Surface3D?,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D] {
    try execution.consumeWork(1)
    let lifted: [Point3D]?
    do {
      lifted = try surfaceLiftIntersections(
        first,
        second,
        sharedSurface: sharedSurface,
        tolerance: tolerance
      , using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: "shared-surface pcurve intersection",
        tolerance: tolerance
      )
    }
    if let lifted {
      return lifted
    }

    if let sectionPoints = try samePlaneTorusSectionIntersections(
      first,
      second,
      tolerance: tolerance
    , using: &execution) {
      return sectionPoints
    }

    if let circlePoints = try coplanarCircularIntersections(
      first,
      second,
      tolerance: tolerance
    , using: &execution) {
      return circlePoints
    }

    let firstCurve: BSplineCurve3D?
    let secondCurve: BSplineCurve3D?
    do {
      firstCurve = try exactRationalCurve(first, tolerance: tolerance, using: &execution)
      secondCurve = try exactRationalCurve(second, tolerance: tolerance, using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: "rational chart preparation",
        tolerance: tolerance
      )
    }
    var attempts: [(source: BRepSewingEdge, ruled: BRepSewingEdge, curve: BSplineCurve3D?)] = []
    if let secondCurve {
      try OriginalParameterQueryStorage.append((source: first, ruled: second, curve: secondCurve), to: &attempts, using: &execution)
    } else if try analyticCurvePlane(second.curve, tolerance: tolerance, using: &execution) != nil {
      // A planar edge without an exact rational span still reduces to
      // its own plane chart.
      try OriginalParameterQueryStorage.append((source: first, ruled: second, curve: nil), to: &attempts, using: &execution)
    }
    if let firstCurve {
      try OriginalParameterQueryStorage.append((source: second, ruled: first, curve: firstCurve), to: &attempts, using: &execution)
    } else if try analyticCurvePlane(first.curve, tolerance: tolerance, using: &execution) != nil {
      try OriginalParameterQueryStorage.append((source: second, ruled: first, curve: nil), to: &attempts, using: &execution)
    }
    attempts.sort { firstAttempt, secondAttempt in
      let firstHasAnalyticRuledPlane: Bool
      if case .line = firstAttempt.ruled.curve {
        firstHasAnalyticRuledPlane = true
      } else {
        firstHasAnalyticRuledPlane = false
      }
      let secondHasAnalyticRuledPlane: Bool
      if case .line = secondAttempt.ruled.curve {
        secondHasAnalyticRuledPlane = true
      } else {
        secondHasAnalyticRuledPlane = false
      }
      return firstHasAnalyticRuledPlane && secondHasAnalyticRuledPlane == false
    }
    if attempts.isEmpty,
      let certifiedPoints = try certifiedSupportSurfaceIntersections(
        first,
        second,
        sharedSurface: sharedSurface,
        tolerance: tolerance
      , using: &execution)
    {
      return certifiedPoints
    }
    if attempts.isEmpty {
      // Every Curve3D has certified point, differential, and interval
      // enclosure contracts. Preserve the faster rational charts above,
      // then use the same exact curve as a procedural ruled boundary for
      // representations that cannot be reduced to a rational span.
      attempts = [
        (source: first, ruled: second, curve: nil),
        (source: second, ruled: first, curve: nil),
      ]
    }

    // Shared or touching endpoints are collected without excluding any
    // neighboring original parameter range. Complete lower root certificates
    // still cover that entire range before structural contacts are merged.
    let contacts = try endpointContacts(first, second, tolerance: tolerance, using: &execution)
    var failures: [(context: String, error: any Error, classification: KernelError)] = []
    for attempt in attempts {
      let sourceRange = try contactTrimmedRange(
        source: attempt.source,
        other: attempt.ruled,
        contacts: contacts,
        tolerance: tolerance
      , using: &execution)
      for direction in try chartDirections(
        source: attempt.source,
        ruled: attempt.ruled,
        tolerance: tolerance
      , using: &execution) {
        do {
          var points = try intersections(
            source: attempt.source,
            sourceRange: sourceRange,
            ruled: attempt.ruled,
            ruledCurve: attempt.curve,
            extrusionDirection: direction,
            tolerance: tolerance
          , using: &execution)
          for contact in contacts {
            try appendUnique(contact, to: &points, tolerance: tolerance, using: &execution)
          }
          return points.sorted(by: pointOrder)
        } catch {
          let published = OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
          guard let classified = OriginalQueryFailure.classification(of: published) else { throw published }
          switch classified.code {
          case .intersectionFailure, .singularSystem, .nonDiscreteIntersection, .unsupportedCapability:
            break
          default:
            throw published
          }
          try OriginalParameterQueryStorage.append((context: "\(attempt.source.stableID) against \(attempt.ruled.stableID) using (\(direction.x), \(direction.y), \(direction.z))", error: published,
            classification: classified), to: &failures, using: &execution)
        }
      }
    }

    let residual = failures.compactMap(\.classification.residual).min()
    let details = failures.prefix(3).map {
      "\($0.context): \($0.classification.code.rawValue): \($0.classification.message)"
    }.joined(separator: " | ")
    throw OriginalQueryFailure.contextualizing(failures[0].error, classification: KernelError(
      phase: .geometry,
      code: failures.contains(where: {
        $0.classification.code == .nonDiscreteIntersection
      })
        ? .nonDiscreteIntersection
        : .intersectionFailure,
      residual: residual,
      tolerance: tolerance,
      message:
        "Every exact ruled-surface chart failed to certify the trim-edge intersection. \(details)"
    ))
  }

  /// Intersects two non-rational certified trim curves without replacing
  /// either curve by a sampled or fitted representation. On a shared face,
  /// each curve retains the other exact surface that defines its locus. A
  /// crossing is therefore a triple-surface point: the first curve can be
  /// intersected with the second curve's other support, and vice versa.
  private func certifiedSupportSurfaceIntersections(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    sharedSurface: Surface3D?,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D]? {
    try execution.consumeWork(1)
    let surface: Surface3D
    if let sharedSurface {
      surface = sharedSurface
    } else if case .surfaceLift(let firstLift) = first.curve,
      case .surfaceLift(let secondLift) = second.curve,
      firstLift.surface == secondLift.surface
    {
      surface = firstLift.surface
    } else {
      return nil
    }

    try first.surfaceParameterCurve.validate(
      on: surface,
      tolerance: tolerance
    , using: &execution)
    try second.surfaceParameterCurve.validate(
      on: surface,
      tolerance: tolerance
    , using: &execution)

    var attempts:
      [(
        source: BRepSewingEdge,
        other: BRepSewingEdge,
        targetSurface: Surface3D
      )] = []
    if let targetSurface = try second.curve
      .otherIntersectionSupportSurface(
        on: surface,
        tolerance: tolerance, using: &execution
      )
      ?? second.surfaceParameterCurve.otherIntersectionSupportSurface(
        on: surface,
        tolerance: tolerance, using: &execution
      )
    {
      try OriginalParameterQueryStorage.append((first, second, targetSurface), to: &attempts, using: &execution)
    }
    if let targetSurface = try first.curve
      .otherIntersectionSupportSurface(
        on: surface,
        tolerance: tolerance, using: &execution
      )
      ?? first.surfaceParameterCurve.otherIntersectionSupportSurface(
        on: surface,
        tolerance: tolerance, using: &execution
      )
    {
      try OriginalParameterQueryStorage.append((second, first, targetSurface), to: &attempts, using: &execution)
    }
    guard attempts.isEmpty == false else { return nil }

    // Two edges whose other supports are one surface (one intersection curve split where that
    // surface's faces meet, as a drilled cylinder's wall crossing another cylinder's halves) lie
    // on each other's support all along, so the reductions below cannot separate them: they
    // cross only where they end.
    let contacts = try endpointContacts(first, second, tolerance: tolerance, using: &execution)
    if attempts.count == 2, attempts[0].targetSurface == attempts[1].targetSurface {
      return contacts.sorted(by: pointOrder)
    }
    let subdivider = BRepSewingEdgeSubdivider()
    var failures: [(context: String, error: any Error, classification: KernelError)] = []
    for attempt in attempts {
      do {
        let sourceRange = try contactTrimmedRange(
          source: attempt.source,
          other: attempt.other,
          contacts: contacts,
          tolerance: tolerance
        , using: &execution)
        let intersections = try DefaultCurveSurfaceIntersector()
          .intersections(
            curve: attempt.source.curve,
            surface: attempt.targetSurface,
            options: CurveSurfaceIntersectionOptions(
              curveRange: sourceRange,
              maximumSubdivisionDepth: 32,
              maximumSubdivisionCells: 4_194_304,
              maximumIterations: 64,
              maximumCandidateCount: 65_536
            ),
            tolerance: tolerance
          , using: &execution)
        var points = contacts
        for intersection in intersections
        where
          try subdivider.contains(
            intersection.point,
            on: attempt.source,
            tolerance: tolerance
          , using: &execution)
          && subdivider.contains(
            intersection.point,
            on: attempt.other,
            tolerance: tolerance
          , using: &execution)
        {
          try appendUnique(
            intersection.point,
            to: &points,
            tolerance: tolerance
          , using: &execution)
        }
        return points.sorted(by: pointOrder)
      } catch {
          let published = OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
          guard let classified = OriginalQueryFailure.classification(of: published) else { throw published }
          switch classified.code {
          case .intersectionFailure, .singularSystem, .nonDiscreteIntersection, .unsupportedCapability:
            break
          default:
            throw published
          }
          try OriginalParameterQueryStorage.append((context: "\(attempt.source.stableID) against the other exact support of \(attempt.other.stableID)", error: published,
            classification: classified), to: &failures, using: &execution)
        }
    }

    let primary = failures[0].classification
    let details = failures.map {
      "\($0.context): \($0.classification.code.rawValue): \($0.classification.message)"
    }.joined(separator: " | ")
    throw OriginalQueryFailure.contextualizing(failures[0].error, classification: KernelError(
      phase: primary.phase,
      code: primary.code,
      residual: failures.compactMap(\.classification.residual).min(),
      tolerance: tolerance,
      message: "Every exact certified support-surface reduction failed. \(details)"
    ))
  }

  /// Endpoints of either edge that lie on the other edge within tolerance
  /// are structural crossing points.
  private func endpointContacts(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D] {
    try execution.consumeWork(1)
    var contacts: [Point3D] = []
    let subdivider = BRepSewingEdgeSubdivider()
    for point in [first.startPoint, first.endPoint]
    where try subdivider.contains(
      point,
      on: second,
      tolerance: tolerance
    , using: &execution) {
      try appendUnique(point, to: &contacts, tolerance: tolerance, using: &execution)
    }
    for point in [second.startPoint, second.endPoint]
    where try subdivider.contains(
      point,
      on: first,
      tolerance: tolerance
    , using: &execution) {
      try appendUnique(point, to: &contacts, tolerance: tolerance, using: &execution)
    }
    return contacts
  }

  /// Retains the entire original directed trim at known endpoint contacts.
  private func contactTrimmedRange(
    source: BRepSewingEdge,
    other: BRepSewingEdge,
    contacts: [Point3D],
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    try execution.consumeWork(1)
    try Task.checkCancellation()
    try tolerance.validate()
    return try parameterRange(source, using: &execution)
  }

  private func chartDirections(
    source: BRepSewingEdge,
    ruled: BRepSewingEdge,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Vector3D] {
    try execution.consumeWork(1)
    var directions: [Vector3D] = []
    func appendUniqueDirection(_ vector: Vector3D) throws {
      guard vector.length > tolerance.distance else { return }
      let unit = vector / vector.length
      guard
        directions.contains(where: {
          abs($0.dot(unit)) >= 1.0 - tolerance.angle
        }) == false
      else { return }
      try OriginalParameterQueryStorage.append(unit, to: &directions, using: &execution)
    }
    func midpointTangent(_ edge: BRepSewingEdge) throws -> Vector3D {
      let midpoint = 0.5 * (edge.startParameter + edge.endParameter)
      let geometry = try edge.curve.differentialGeometry(
        at: midpoint,
        tolerance: tolerance
      , using: &execution)
      return geometry.firstDerivative
    }
    let sourceChord = source.endPoint - source.startPoint
    let ruledChord = ruled.endPoint - ruled.startPoint
    try appendUniqueDirection(ruledChord.cross(sourceChord))
    // Curved edges can graze a chord-based chart, so tangent-based
    // transverse directions join the chart pool.
    let sourceTangent = try midpointTangent(source)
    let ruledTangent = try midpointTangent(ruled)
    try appendUniqueDirection(ruledTangent.cross(sourceTangent))
    try appendUniqueDirection(ruledChord.cross(sourceTangent))
    try appendUniqueDirection(ruledTangent.cross(sourceChord))
    for axis in [Vector3D.unitX, .unitY, .unitZ] {
      try appendUniqueDirection(axis)
    }
    return directions
  }

  private func partitionedCoincidenceIntersections(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    sharedSurface: Surface3D?,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D]? {
    try execution.consumeWork(1)
    var sharedPoints: [Point3D] = []
    // Structural points are constructed directly on their source edge.
    // Reprojecting each point back onto that same edge repeats the most
    // expensive part of partial-coincidence classification and cannot
    // add information after the edge has passed BRep validation. Only
    // membership on the opposite edge needs to be established.
    let subdivider = BRepSewingEdgeSubdivider()
    for point in try subdivider.containedPoints(
      from: structuralPoints(first, tolerance: tolerance, using: &execution),
      on: second,
      tolerance: tolerance
    , using: &execution) {
      try appendUnique(point, to: &sharedPoints, tolerance: tolerance, using: &execution)
    }
    for point in try subdivider.containedPoints(
      from: structuralPoints(second, tolerance: tolerance, using: &execution),
      on: first,
      tolerance: tolerance
    , using: &execution) {
      try appendUnique(point, to: &sharedPoints, tolerance: tolerance, using: &execution)
    }
    guard sharedPoints.count >= 2 else { return nil }

    let firstSegments = try subdivider.subdivide(
      first,
      at: sharedPoints,
      tolerance: tolerance
    , using: &execution)
    let secondSegments = try subdivider.subdivide(
      second,
      at: sharedPoints,
      tolerance: tolerance
    , using: &execution)
    let pairCount = firstSegments.count * secondSegments.count
    guard pairCount <= 16_384 else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        residual: Double(pairCount),
        tolerance: tolerance,
        message: "Exact coincident trim partitioning exceeded its span-pair budget."
      )
    }

    var coincidentPairs = Set<SpanPair>()
    for firstIndex in firstSegments.indices {
      for secondIndex in secondSegments.indices
      where try spansAreEquivalent(
        firstSegments[firstIndex],
        secondSegments[secondIndex],
        tolerance: tolerance
      , using: &execution) {
        coincidentPairs.insert(
          SpanPair(
            firstIndex: firstIndex,
            secondIndex: secondIndex
          ))
      }
    }
    guard coincidentPairs.isEmpty == false else { return nil }

    let preparedSurface: PreparedSurfaceDifferentialEncloser?
    if let sharedSurface {
      preparedSurface = try PreparedSurfaceDifferentialEncloser(
        surface: sharedSurface,
        tolerance: tolerance
      , remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32, using: &execution)
    } else if case .surfaceLift(let firstLift) = first.curve,
      case .surfaceLift(let secondLift) = second.curve,
      firstLift.surface == secondLift.surface
    {
      preparedSurface = try PreparedSurfaceDifferentialEncloser(
        surface: firstLift.surface,
        tolerance: tolerance
      , remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32, using: &execution)
    } else {
      preparedSurface = nil
    }

    var points: [Point3D] = []
    for pair in coincidentPairs {
      let span = firstSegments[pair.firstIndex]
      try appendUnique(span.startPoint, to: &points, tolerance: tolerance, using: &execution)
      try appendUnique(span.endPoint, to: &points, tolerance: tolerance, using: &execution)
    }
    for firstIndex in firstSegments.indices {
      for secondIndex in secondSegments.indices {
        let pair = SpanPair(
          firstIndex: firstIndex,
          secondIndex: secondIndex
        )
        guard coincidentPairs.contains(pair) == false else { continue }
        let endpointContacts = try endpointContacts(
          firstSegments[firstIndex],
          secondSegments[secondIndex],
          tolerance: tolerance
        , using: &execution)
        if endpointContacts.isEmpty == false,
          try rationalControlHullOverlapIsCoveredByContacts(
            firstSegments[firstIndex],
            secondSegments[secondIndex],
            contacts: endpointContacts,
            sharedSurface: sharedSurface,
            preparedSurface: preparedSurface,
            tolerance: tolerance
          , using: &execution)
        {
          for point in endpointContacts {
            try appendUnique(point, to: &points, tolerance: tolerance, using: &execution)
          }
          continue
        }
        let discrete = try discreteIntersections(
          firstSegments[firstIndex],
          secondSegments[secondIndex],
          sharedSurface: sharedSurface,
          tolerance: tolerance
        , using: &execution)
        for point in discrete {
          try appendUnique(point, to: &points, tolerance: tolerance, using: &execution)
        }
      }
    }
    return points.sorted(by: pointOrder)
  }

  private func rationalControlHullOverlapIsCoveredByContacts(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    contacts: [Point3D],
    sharedSurface: Surface3D?,
    preparedSurface: PreparedSurfaceDifferentialEncloser?,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    let surface: Surface3D
    if let sharedSurface {
      surface = sharedSurface
    } else if case .surfaceLift(let firstLift) = first.curve,
      case .surfaceLift(let secondLift) = second.curve,
      firstLift.surface == secondLift.surface
    {
      surface = firstLift.surface
    } else {
      return false
    }
    guard
      let firstCurve = try exactRationalPcurve(
        first,
        tolerance: tolerance
      , using: &execution),
      let secondCurve = try exactRationalPcurve(
        second,
        tolerance: tolerance
      , using: &execution)
    else {
      return false
    }
    let alignedSecond = try periodicallyAligned(
      secondCurve,
      to: firstCurve,
      on: surface
    , using: &execution)
    if try rationalCurvesOccupyOppositeStrictSides(
      firstCurve,
      alignedSecond,
      contacts: contacts,
      surface: surface,
      tolerance: tolerance
    , using: &execution) {
      return true
    }
    let firstPoints = firstCurve.controlPoints
    let secondPoints = alignedSecond.controlPoints
    guard firstPoints.isEmpty == false, secondPoints.isEmpty == false else {
      return false
    }
    let uLower = max(
      firstPoints.map(\.x).min() ?? .infinity,
      secondPoints.map(\.x).min() ?? .infinity
    )
    let uUpper = min(
      firstPoints.map(\.x).max() ?? -.infinity,
      secondPoints.map(\.x).max() ?? -.infinity
    )
    let vLower = max(
      firstPoints.map(\.y).min() ?? .infinity,
      secondPoints.map(\.y).min() ?? .infinity
    )
    let vUpper = min(
      firstPoints.map(\.y).max() ?? -.infinity,
      secondPoints.map(\.y).max() ?? -.infinity
    )
    if uLower > uUpper || vLower > vUpper {
      return true
    }
    let encloser: PreparedSurfaceDifferentialEncloser
    if let preparedSurface {
      guard preparedSurface.surface == surface else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          tolerance: tolerance,
          message: "Prepared trim-overlap surface does not match the shared support surface."
        )
      }
      encloser = preparedSurface
    } else {
      encloser = try PreparedSurfaceDifferentialEncloser(
        surface: surface,
        tolerance: tolerance
      , remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32, using: &execution)
    }
    let position = try encloser.enclosure(
      over: SurfaceParameterBox(
        u: try boundedEnclosure(lower: uLower, upper: uUpper, domain: surface.uDomain, using: &execution),
        v: try boundedEnclosure(lower: vLower, upper: vUpper, domain: surface.vDomain, using: &execution)
      ),
      tolerance: tolerance
    , using: &execution).position
    return contacts.contains { contact in
      let x = max(
        abs(position.x.lower - contact.x),
        abs(position.x.upper - contact.x)
      ).nextUp
      let y = max(
        abs(position.y.lower - contact.y),
        abs(position.y.upper - contact.y)
      ).nextUp
      let z = max(
        abs(position.z.lower - contact.z),
        abs(position.z.upper - contact.z)
      ).nextUp
      return sqrt((x * x + y * y + z * z).nextUp).nextUp
        <= tolerance.distance
    }
  }

  private func rationalCurvesOccupyOppositeStrictSides(
    _ first: BSplineCurve2D,
    _ second: BSplineCurve2D,
    contacts: [Point3D],
    surface: Surface3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    guard contacts.count >= 2 else { return false }
    let endpointCandidates = [
      first.controlPoints.first,
      first.controlPoints.last,
      second.controlPoints.first,
      second.controlPoints.last,
    ].compactMap { $0 }
    var separatorPoints: [Point2D] = []
    for contact in contacts {
      for candidate in endpointCandidates {
        let lifted = try surface.point(
          u: candidate.x,
          v: candidate.y,
          tolerance: tolerance
        , using: &execution)
        if (lifted - contact).length <= tolerance.distance {
          if separatorPoints.contains(candidate) == false {
            try OriginalParameterQueryStorage.append(candidate, to: &separatorPoints, using: &execution)
          }
          break
        }
      }
    }
    guard separatorPoints.count >= 2 else { return false }
    let separatorStart = separatorPoints[0]
    guard
      let separatorEnd = separatorPoints.dropFirst().first(where: {
        $0 != separatorStart
      })
    else {
      return false
    }

    func side(
      of curve: BSplineCurve2D
    ) throws -> RobustSign? {
      let patches = try curve.rationalBezierPatches(
        tolerance: tolerance
      )
      var curveSide: RobustSign?
      for patch in patches {
        let signs = try patch.controlPoints.map {
          try RobustPredicates.orientation2D(
            separatorStart,
            separatorEnd,
            relativeTo: $0,
            determinantTolerance: 0.0
          )
        }
        guard signs.contains(.indeterminate) == false,
          signs.contains(.positive) == false
            || signs.contains(.negative) == false
        else {
          return nil
        }
        let patchSide: RobustSign
        if signs.contains(.positive) {
          patchSide = .positive
        } else if signs.contains(.negative) {
          patchSide = .negative
        } else {
          return nil
        }
        if let curveSide, curveSide != patchSide {
          return nil
        }
        curveSide = patchSide
        for endpoint in [
          patch.controlPoints.first,
          patch.controlPoints.last,
        ].compactMap({ $0 }) {
          let sign = try RobustPredicates.orientation2D(
            separatorStart,
            separatorEnd,
            relativeTo: endpoint,
            determinantTolerance: 0.0
          )
          if sign == .zero {
            guard
              try endpointIsCoveredByContact(
                endpoint,
                contacts: contacts,
                surface: surface,
                tolerance: tolerance
              , using: &execution)
            else {
              return nil
            }
          }
        }
      }
      return curveSide
    }

    guard let firstSide = try side(of: first),
      let secondSide = try side(of: second)
    else {
      return false
    }
    return (firstSide == .positive && secondSide == .negative)
      || (firstSide == .negative && secondSide == .positive)
  }

  private func endpointIsCoveredByContact(
    _ endpoint: Point2D,
    contacts: [Point3D],
    surface: Surface3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    let lifted = try surface.point(
      u: endpoint.x,
      v: endpoint.y,
      tolerance: tolerance
    , using: &execution)
    return contacts.contains {
      (lifted - $0).length <= tolerance.distance
    }
  }

  private func structuralPoints(
    _ edge: BRepSewingEdge,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D] {
    try execution.consumeWork(1)
    var points = [edge.startPoint, edge.endPoint]
    let curve: BSplineCurve3D
    let pointAt: (Double, inout OriginalQueryExecution) throws -> Point3D
    let lower: Double
    let upper: Double
    switch edge.curve {
    case .bSpline(let bSpline):
      curve = bSpline
      lower = min(edge.startParameter, edge.endParameter)
      upper = max(edge.startParameter, edge.endParameter)
      pointAt = { parameter, execution in
        try bSpline.point(at: parameter, tolerance: tolerance, using: &execution)
      }
    case .surfaceLift(let lift):
      guard case .bSpline(let parameterCurve) = edge.surfaceParameterCurve else {
        return points
      }
      curve = embedded(parameterCurve, z: 0.0)
      guard case .closed(let domainLower, let domainUpper) = parameterCurve.domain else {
        return points
      }
      lower = domainLower
      upper = domainUpper
      pointAt = { parameter, execution in
        let uv = try parameterCurve.point(at: parameter, tolerance: tolerance, using: &execution)
        return try lift.surface.point(
          u: uv.x,
          v: uv.y,
          tolerance: tolerance
        , using: &execution)
      }
    case .affineImage(let image):
      let interval = try ScalarInterval(
        lower: min(edge.startParameter, edge.endParameter),
        upper: max(edge.startParameter, edge.endParameter)
      )
      guard
        let exactCurve = try AnalyticCurveBSplineBuilder().boundedCurve(
          curve: image.source,
          interval: interval,
          maximumSpanCount: 4_096,
          tolerance: tolerance
        , using: &execution)
      else {
        return points
      }
      curve = exactCurve
      lower = interval.lower
      upper = interval.upper
      pointAt = { parameter, execution in
        try edge.curve.point(at: parameter, tolerance: tolerance, using: &execution)
      }
    case .line, .circle, .analytic, .implicit, .certifiedIntersection,
      .rigidImage, .parameterImage, .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalGuideTraversalChain, .originalPolyline, .originalGuideEndpointConnector, .originalDrafted:
      return points
    }
    let scale = max(abs(lower), abs(upper), abs(upper - lower), 1.0)
    let resolution = max(
      tolerance.relative * scale,
      Double.ulpOfOne * scale * 256.0
    )
    var previous: Double?
    for knot in curve.knots.sorted()
    where
      knot > lower + resolution && knot < upper - resolution
    {
      if let previous, abs(knot - previous) <= resolution { continue }
      try appendUnique(
        try pointAt(knot, &execution),
        to: &points,
        tolerance: tolerance
      , using: &execution)
      previous = knot
    }
    return points
  }

  /// Validated pcurves lie in the support domain. Outward rounding at a boundary
  /// may extend the root enclosure beyond it; intersect that enclosure with the
  /// domain before asking the surface for a spatial bound.
  private func boundedEnclosure(
    lower: Double, upper: Double, domain: ParameterDomain
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    try execution.consumeWork(1)
    if case .closed(let start, let end) = domain {
      return try ScalarInterval(lower: max(start, lower.nextDown), upper: min(end, upper.nextUp))
    }
    return try ScalarInterval(lower: lower.nextDown, upper: upper.nextUp)
  }

  private func surfaceLiftIntersections(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    sharedSurface: Surface3D?,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D]? {
    try execution.consumeWork(1)
    let surface: Surface3D
    if let sharedSurface {
      surface = sharedSurface
    } else if case .surfaceLift(let firstLift) = first.curve,
      case .surfaceLift(let secondLift) = second.curve,
      firstLift.surface == secondLift.surface
    {
      surface = firstLift.surface
    } else {
      return nil
    }
    if let points = try implicitIsoparametricIntersections(
      first, second, surface: surface, tolerance: tolerance
    , using: &execution) ?? implicitIsoparametricIntersections(second, first, surface: surface, tolerance: tolerance, using: &execution) {
      return points
    }
    guard
      let firstPcurve = try exactRationalPcurve(
        first,
        tolerance: tolerance
      , using: &execution),
      let secondPcurve = try exactRationalPcurve(
        second,
        tolerance: tolerance
      , using: &execution)
    else { return nil }
    try first.surfaceParameterCurve.validate(
      on: surface,
      tolerance: tolerance
    , using: &execution)
    try second.surfaceParameterCurve.validate(
      on: surface,
      tolerance: tolerance
    , using: &execution)
    let structuralContacts = try endpointContacts(
      first,
      second,
      tolerance: tolerance
    , using: &execution)
    let preparedSurface = try PreparedSurfaceDifferentialEncloser(
      surface: surface,
      tolerance: tolerance
    , remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32, using: &execution)
    if structuralContacts.isEmpty == false,
      try rationalControlHullOverlapIsCoveredByContacts(
        first,
        second,
        contacts: structuralContacts,
        sharedSurface: surface,
        preparedSurface: preparedSurface,
        tolerance: tolerance
      , using: &execution)
    {
      return structuralContacts.sorted(by: pointOrder)
    }
    let firstSearchRange = try contactTrimmedRange(
      source: first,
      other: second,
      contacts: structuralContacts,
      tolerance: tolerance
    , using: &execution)
    let secondSearchRange = try contactTrimmedRange(
      source: second,
      other: first,
      contacts: structuralContacts,
      tolerance: tolerance
    , using: &execution)
    let searchedFirstPcurve = try rationalPcurve(
      firstPcurve,
      on: first,
      restrictedTo: firstSearchRange,
      tolerance: tolerance
    , using: &execution)
    let searchedSecondPcurve = try rationalPcurve(
      secondPcurve,
      on: second,
      restrictedTo: secondSearchRange,
      tolerance: tolerance
    , using: &execution)
    let alignedSecondPcurve = try periodicallyAligned(
      searchedSecondPcurve,
      to: searchedFirstPcurve,
      on: surface
    , using: &execution)
    guard
      controlHullsMayIntersect(
        searchedFirstPcurve,
        alignedSecondPcurve,
        surface: surface,
        tolerance: tolerance
      )
    else {
      return []
    }
    let intersections: [RationalBSplineCurveIntersection2D]
    let surfaceEncloser = try PreparedSurfaceDifferentialEncloser(
      surface: surface,
      tolerance: tolerance
    , remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32, using: &execution)
    do {
      intersections = try RationalBSplineCurveIntersector2D().intersections(
        first: searchedFirstPcurve,
        second: alignedSecondPcurve,
        maximumSubdivisionDepth: 32,
        maximumSubdivisionCells: 1_048_576,
        accepting: { intersection, execution in
          let spatial = try surfaceEncloser.enclosure(
            over: SurfaceParameterBox(
              u: try boundedEnclosure(lower: intersection.pointEnclosure.x.lower,
                upper: intersection.pointEnclosure.x.upper, domain: surface.uDomain, using: &execution),
              v: try boundedEnclosure(lower: intersection.pointEnclosure.y.lower,
                upper: intersection.pointEnclosure.y.upper, domain: surface.vDomain, using: &execution)
            ),
            tolerance: tolerance, maximumSpanCount: 262_144, maximumSubdivisionDepth: 32,
            remainingSourceDepth: 16, using: &execution
          ).position
          let xWidth = spatial.x.width.nextUp
          let yWidth = spatial.y.width.nextUp
          let zWidth = spatial.z.width.nextUp
          let xySquared = (xWidth * xWidth + yWidth * yWidth).nextUp
          let diameter = sqrt(
            (xySquared + zWidth * zWidth).nextUp
          ).nextUp
          return diameter <= tolerance.distance
        },
        tolerance: tolerance
      , using: &execution)
    } catch {
      throw contextualized(
        error,
        stage:
          "rational pcurve chart (first: \(pcurveDiagnostic(searchedFirstPcurve)); second: \(pcurveDiagnostic(alignedSecondPcurve)))",
        tolerance: tolerance
      )
    }
    var points = structuralContacts
    for intersection in intersections {
      let liftedPoint = try surface.point(
        u: intersection.pointEnclosure.x.midpoint,
        v: intersection.pointEnclosure.y.midpoint,
        tolerance: tolerance
      , using: &execution)
      try appendUnique(liftedPoint, to: &points, tolerance: tolerance, using: &execution)
    }
    return points.sorted(by: pointOrder)
  }

  /// A separated coordinate enclosure excludes crossings. Otherwise a strictly
  /// monotone coordinate and an exact endpoint certify the only possible root.
  private func implicitIsoparametricIntersections(
    _ boundary: BRepSewingEdge, _ contact: BRepSewingEdge,
    surface: Surface3D, tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D]? {
    try execution.consumeWork(1)
    guard case .bSpline = surface else { return nil }
    let isU: Bool
    let constant: Double
    let start: Double
    let end: Double
    switch boundary.surfaceParameterCurve {
    case .constantU(let u, let vStart, let vEnd): (isU, constant, start, end) = (true, u, vStart, vEnd)
    case .constantV(let v, let uStart, let uEnd): (isU, constant, start, end) = (false, v, uStart, uEnd)
    default: return nil
    }
    var pcurve = contact.surfaceParameterCurve
    while case .offsetSurfaceImage(let image) = pcurve { pcurve = image.source }
    guard case .certifiedImplicit(let implicit) = pcurve,
      min(implicit.startFraction, implicit.endFraction) >= 0,
      max(implicit.startFraction, implicit.endFraction) <= 1, start != end else { return nil }
    try boundary.surfaceParameterCurve.validate(on: surface, tolerance: tolerance, using: &execution)
    try contact.surfaceParameterCurve.validate(on: surface, tolerance: tolerance, using: &execution)
    let jet = try ImplicitCurveIntervalJetEncloser(intersection: implicit.intersection, tolerance: tolerance, using: &execution)
      .parameterIntervalJet(of: implicit.intersection,
        over: ScalarInterval(lower: min(implicit.startFraction, implicit.endFraction),
                             upper: max(implicit.startFraction, implicit.endFraction)), tolerance: tolerance, using: &execution)
    let coordinate: SurfaceIntersectionParameterCoordinate = implicit.role == .first
      ? (isU ? .firstU : .firstV) : (isU ? .secondU : .secondV)
    let bounds = jet[coordinate].value
    if !intervalsMayOverlap((bounds.lower, bounds.upper), (constant, constant),
      period: nil, tolerance: tolerance) {
      return []
    }
    let first = try contact.surfaceParameterCurve.startParameter(tolerance: tolerance, using: &execution)
    let last = try contact.surfaceParameterCurve.endParameter(tolerance: tolerance, using: &execution)
    let endpoint: (uv: SurfaceParameter, point: Point3D)
    if (isU ? first.u : first.v) == constant { endpoint = (first, contact.startPoint) }
    else if (isU ? last.u : last.v) == constant { endpoint = (last, contact.endPoint) }
    else { return nil }
    let derivative = jet[coordinate].firstDerivative
    guard derivative.lower > 0 || derivative.upper < 0 else { return nil }
    let varying = isU ? endpoint.uv.v : endpoint.uv.u
    guard varying >= min(start, end), varying <= max(start, end) else { return [] }
    let fraction = (varying - start) / (end - start)
    let point = try boundary.curve.point(at: boundary.startParameter
      + (boundary.endParameter - boundary.startParameter) * fraction, tolerance: tolerance, using: &execution)
    guard (point - endpoint.point).length <= tolerance.distance else {
      throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
        message: "An implicit chart endpoint does not match its source boundary in model space.")
    }
    return [endpoint.point]
  }

  /// Maps a structural-contact-free edge parameter range into the exact
  /// pcurve's own bounded parameter domain. Some exact representations use
  /// the edge parameter directly while materialized affine/polyline curves
  /// use a normalized domain, so the mapping is expressed through oriented
  /// edge fractions instead of assuming same numeric parameters.
  private func rationalPcurve(
    _ curve: BSplineCurve2D,
    on edge: BRepSewingEdge,
    restrictedTo searchRange: ScalarInterval,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BSplineCurve2D {
    try execution.consumeWork(1)
    guard case .closed(let curveLower, let curveUpper) = curve.domain else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "An exact rational pcurve search requires a bounded parameter domain."
      )
    }
    let edgeSpan = edge.endParameter - edge.startParameter
    guard edgeSpan.isFinite,
      abs(edgeSpan) > Double.leastNonzeroMagnitude
    else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        residual: edgeSpan,
        tolerance: tolerance,
        message: "An exact rational pcurve search received a degenerate edge span."
      )
    }
    let firstFraction = (searchRange.lower - edge.startParameter) / edgeSpan
    let secondFraction = (searchRange.upper - edge.startParameter) / edgeSpan
    let curveSpan = curveUpper - curveLower
    let firstParameter = curveLower + curveSpan * firstFraction
    let secondParameter = curveLower + curveSpan * secondFraction
    let lower = min(firstParameter, secondParameter)
    let upper = max(firstParameter, secondParameter)
    let roundoff =
      Double.ulpOfOne
      * max(
        abs(curveLower),
        abs(curveUpper),
        abs(lower),
        abs(upper),
        1.0
      ) * 8_192.0
    let boundedLower = max(curveLower, lower)
    let boundedUpper = min(curveUpper, upper)
    guard boundedLower >= curveLower - roundoff,
      boundedUpper <= curveUpper + roundoff,
      boundedUpper - boundedLower
        > max(
          tolerance.angle,
          Double.ulpOfOne * max(abs(curveSpan), 1.0) * 64.0
        )
    else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        residual: boundedUpper - boundedLower,
        tolerance: tolerance,
        message: "Structural endpoint exclusion exhausted an exact rational pcurve search span."
      )
    }
    if abs(boundedLower - curveLower) <= roundoff,
      abs(boundedUpper - curveUpper) <= roundoff
    {
      return curve
    }
    return try curve.trimmed(
      from: boundedLower,
      to: boundedUpper,
      tolerance: tolerance, using: &execution
    )
  }

  private func exactRationalPcurve(
    _ edge: BRepSewingEdge,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BSplineCurve2D? {
    try execution.consumeWork(1)
    // A B-spline stored as a surface-intersection derived representation
    // is a bounded cache, not the exact locus of the certified 3D curve.
    // Only use rational root certificates when the edge's truth curve
    // carries a rational parameter curve of its own. Other truth models
    // must stay on their certified support-surface path.
    if case .surfaceLift(let lift) = edge.curve,
      try exactRationalPcurve(
        lift.parameterCurve,
        tolerance: tolerance
      , using: &execution) == nil
    {
      return nil
    }
    switch edge.curve {
    case .implicit, .certifiedIntersection, .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalGuideTraversalChain, .originalPolyline, .originalGuideEndpointConnector, .originalDrafted:
      return nil
    case .line, .circle, .analytic, .bSpline, .surfaceLift,
      .rigidImage, .affineImage, .parameterImage:
      return try exactRationalPcurve(
        edge.surfaceParameterCurve,
        tolerance: tolerance
      , using: &execution)
    }
  }

  private func exactRationalPcurve(
    _ curve: SurfaceParameterCurve,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BSplineCurve2D? {
    try execution.consumeWork(1)
    switch curve {
    case .affine(let origin, let direction, let startParameter, let endParameter):
      return try linearPcurve(
        from: Point2D(
          x: origin.x + direction.x * startParameter,
          y: origin.y + direction.y * startParameter
        ),
        to: Point2D(
          x: origin.x + direction.x * endParameter,
          y: origin.y + direction.y * endParameter
        )
      , using: &execution)
    case .constantU(let u, let vStart, let vEnd):
      return try linearPcurve(
        from: Point2D(x: u, y: vStart),
        to: Point2D(x: u, y: vEnd)
      , using: &execution)
    case .constantV(let v, let uStart, let uEnd):
      return try linearPcurve(
        from: Point2D(x: uStart, y: v),
        to: Point2D(x: uEnd, y: v)
      , using: &execution)
    case .harmonic(
      let
        center,
      let
        cosine,
      let
        sine,
      let
        startParameter,
      let
        endParameter
    ):
      // FIXME(INCOMPLETE_IMPLEMENTATION): Boolean trim intersection cannot use
      // a rounded rational conic net as the original harmonic clock. No retained
      // whole-law/native-parameter transport proof exists for this restriction.
      // Keep the original harmonic source and fail until that producer exists.
      throw KernelError(phase: .geometry, code: .unsupportedCapability,
        tolerance: tolerance,
        message: "Original harmonic trim restriction requires certified native-parameter transport.")
    case .polyline(let parameters):
      guard parameters.count >= 2 else { return nil }
      let denominator = Double(parameters.count - 1)
      let interiorKnots = parameters.indices.dropFirst().dropLast().map {
        Double($0) / denominator
      }
      let result = BSplineCurve2D(
        degree: 1,
        knots: [0.0, 0.0] + interiorKnots + [1.0, 1.0],
        controlPoints: parameters.map { Point2D(x: $0.u, y: $0.v) }
      )
      try result.validate(tolerance: tolerance, using: &execution)
      return result
    case .bSpline(let curve):
      return curve
    case .offsetSurfaceImage(let image):
      return try exactRationalPcurve(
        image.source,
        tolerance: tolerance
      , using: &execution)
    case .originalBSplineContinuation, .originalImage, .originalAffineWord, .sphericalGreatCircle, .certifiedImplicit,
      .certifiedAnalyticImplicit, .certifiedAnalyticPair,
      .projectedAnalytic, .rigidImage:
      return nil
    case .periodicTranslation:
      return try exactRationalPcurve(
        try curve.materializingPeriodicTranslation(using: &execution),
        tolerance: tolerance
      , using: &execution)
    }
  }

  private func linearPcurve(
    from start: Point2D,
    to end: Point2D
  , using execution: inout OriginalQueryExecution) throws -> BSplineCurve2D {
    try execution.consumeWork(1)
    try execution.retainKernelValues(count: 4, stride: MemoryLayout<Double>.stride)
    try execution.retainKernelValues(count: 2, stride: MemoryLayout<Point2D>.stride)
    return BSplineCurve2D(
      degree: 1,
      knots: [0.0, 0.0, 1.0, 1.0],
      controlPoints: [start, end]
    )
  }

  private func periodicallyAligned(
    _ curve: BSplineCurve2D,
    to reference: BSplineCurve2D,
    on surface: Surface3D
  , using execution: inout OriginalQueryExecution) throws -> BSplineCurve2D {
    try execution.consumeWork(curve.controlPoints.count)
    try execution.consumeWork(reference.controlPoints.count)
    try execution.retainKernelValues(count: curve.controlPoints.count, stride: MemoryLayout<Point2D>.stride)
    func center(
      of points: [Point2D],
      keyPath: KeyPath<Point2D, Double>
    ) -> Double {
      guard let minimum = points.map({ $0[keyPath: keyPath] }).min(),
        let maximum = points.map({ $0[keyPath: keyPath] }).max()
      else {
        return 0.0
      }
      return minimum + (maximum - minimum) * 0.5
    }
    let referenceU = center(of: reference.controlPoints, keyPath: \.x)
    let referenceV = center(of: reference.controlPoints, keyPath: \.y)
    let curveU = center(of: curve.controlPoints, keyPath: \.x)
    let curveV = center(of: curve.controlPoints, keyPath: \.y)
    let uShift =
      period(of: surface.uDomain).map {
        ((referenceU - curveU) / $0).rounded() * $0
      } ?? 0.0
    let vShift =
      period(of: surface.vDomain).map {
        ((referenceV - curveV) / $0).rounded() * $0
      } ?? 0.0
    guard uShift != 0.0 || vShift != 0.0 else { return curve }
    return BSplineCurve2D(
      degree: curve.degree,
      knots: curve.knots,
      controlPoints: curve.controlPoints.map {
        Point2D(x: $0.x + uShift, y: $0.y + vShift)
      },
      weights: curve.weights
    )
  }

  private func pcurveDiagnostic(_ curve: BSplineCurve2D) -> String {
    let u = coordinateBounds(curve.controlPoints, keyPath: \.x)
    let v = coordinateBounds(curve.controlPoints, keyPath: \.y)
    let minimumWeight = curve.weights.min() ?? .nan
    let maximumWeight = curve.weights.max() ?? .nan
    let start = curve.controlPoints.first ?? Point2D(x: .nan, y: .nan)
    let end = curve.controlPoints.last ?? Point2D(x: .nan, y: .nan)
    return "degree \(curve.degree), controls \(curve.controlPoints.count), domain \(curve.domain), "
      + "start (\(start.x), \(start.y)), end (\(end.x), \(end.y)), "
      + "u [\(u?.lower ?? .nan), \(u?.upper ?? .nan)], "
      + "v [\(v?.lower ?? .nan), \(v?.upper ?? .nan)], "
      + "weights [\(minimumWeight), \(maximumWeight)]"
  }

  private func controlHullsMayIntersect(
    _ first: BSplineCurve2D,
    _ second: BSplineCurve2D,
    surface: Surface3D,
    tolerance: ModelingTolerance
  ) -> Bool {
    guard let firstU = coordinateBounds(first.controlPoints, keyPath: \.x),
      let firstV = coordinateBounds(first.controlPoints, keyPath: \.y),
      let secondU = coordinateBounds(second.controlPoints, keyPath: \.x),
      let secondV = coordinateBounds(second.controlPoints, keyPath: \.y)
    else {
      return false
    }
    return intervalsMayOverlap(
      firstU,
      secondU,
      period: period(of: surface.uDomain),
      tolerance: tolerance
    )
      && intervalsMayOverlap(
        firstV,
        secondV,
        period: period(of: surface.vDomain),
        tolerance: tolerance
      )
  }

  private func coordinateBounds(
    _ points: [Point2D],
    keyPath: KeyPath<Point2D, Double>
  ) -> (lower: Double, upper: Double)? {
    guard let firstPoint = points.first else { return nil }
    let first = firstPoint[keyPath: keyPath]
    var lower = first
    var upper = first
    for point in points.dropFirst() {
      let value = point[keyPath: keyPath]
      lower = min(lower, value)
      upper = max(upper, value)
    }
    return (lower, upper)
  }

  private func intervalsMayOverlap(
    _ first: (lower: Double, upper: Double),
    _ second: (lower: Double, upper: Double),
    period: Double?,
    tolerance: ModelingTolerance
  ) -> Bool {
    let scale = max(
      abs(first.lower),
      abs(first.upper),
      abs(second.lower),
      abs(second.upper),
      period ?? 0.0,
      1.0
    )
    let resolution = max(
      tolerance.relative * scale,
      Double.ulpOfOne * scale * 256.0
    )
    guard let period else {
      return first.lower <= second.upper + resolution
        && second.lower <= first.upper + resolution
    }
    let firstCenter = 0.5 * (first.lower + first.upper)
    let secondCenter = 0.5 * (second.lower + second.upper)
    let centerDelta = secondCenter - firstCenter
    let reducedDelta = centerDelta - (centerDelta / period).rounded() * period
    let combinedHalfWidth = 0.5 * (first.upper - first.lower + second.upper - second.lower)
    return abs(reducedDelta) <= combinedHalfWidth + resolution
  }

  private func period(
    of domain: ParameterDomain
  ) -> Double? {
    guard case .periodic(let period) = domain else { return nil }
    return period
  }

  private func embedded(
    _ curve: BSplineCurve2D,
    z: Double
  ) -> BSplineCurve3D {
    BSplineCurve3D(
      degree: curve.degree,
      knots: curve.knots,
      controlPoints: curve.controlPoints.map {
        Point3D(x: $0.x, y: $0.y, z: z)
      },
      weights: curve.weights
    )
  }

  private func intersections(
    source: BRepSewingEdge,
    sourceRange: ScalarInterval,
    ruled: BRepSewingEdge,
    ruledCurve: BSplineCurve3D?,
    extrusionDirection: Vector3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D] {
    try execution.consumeWork(1)
    if let line = ruledLine(ruled.curve),
      let plane = try analyticRuledPlane(
        line: line,
        extrusionDirection: extrusionDirection,
        tolerance: tolerance
      , using: &execution)
    {
      return try intersections(
        source: source,
        sourceRange: sourceRange,
        ruled: ruled,
        plane: plane,
        tolerance: tolerance
      , using: &execution)
    }
    // A circular or elliptic ruled edge lies in its own plane, so its
    // crossings with the source reduce to a curve-plane scalar
    // intersection instead of a ruled-surface chart. A source lying in
    // that same plane keeps the ruled-chart path, whose crossings stay
    // discrete where a curve-plane intersection is a continuum.
    if let plane = try analyticCurvePlane(ruled.curve, tolerance: tolerance, using: &execution),
      try sourceLeavesPlane(
        source,
        range: sourceRange,
        plane: plane,
        tolerance: tolerance
      , using: &execution)
    {
      return try intersections(
        source: source,
        sourceRange: sourceRange,
        ruled: ruled,
        plane: plane,
        tolerance: tolerance
      , using: &execution)
    }
    let extent = max(
      (source.endPoint - source.startPoint).length,
      (ruled.endPoint - ruled.startPoint).length,
      tolerance.distance * 1_024.0
    )
    let ruledRange: ScalarInterval
    let surface: Surface3D
    if let ruledCurve {
      let rationalSurface = try ruledSurface(
        curve: ruledCurve,
        offset: extrusionDirection * extent,
        tolerance: tolerance
      , using: &execution)
      ruledRange = try parameterRange(ruledCurve, using: &execution)
      surface = .bSpline(rationalSurface)
    } else {
      ruledRange = try parameterRange(ruled, using: &execution)
      surface = try proceduralRuledSurface(
        curve: ruled.curve,
        range: ruledRange,
        offset: extrusionDirection * extent,
        tolerance: tolerance
      , using: &execution)
    }
    let intersections: [CurveSurfaceIntersection]
    do {
      intersections = try DefaultCurveSurfaceIntersector().intersections(
        curve: source.curve,
        surface: surface,
        options: CurveSurfaceIntersectionOptions(
          curveRange: sourceRange,
          surfaceURange: ruledRange,
          surfaceVRange: try ScalarInterval(lower: 0.0, upper: 1.0),
          maximumSubdivisionDepth: 32,
          maximumSubdivisionCells: 4_194_304,
          maximumIterations: 64,
          maximumCandidateCount: 65_536
        ),
        tolerance: tolerance
      , using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: ruledCurve == nil
          ? "procedural ruled-surface root certification"
          : "rational ruled-surface root certification",
        tolerance: tolerance
      )
    }
    var points: [Point3D] = []
    for intersection in intersections {
      guard
        try BRepSewingEdgeSubdivider().contains(
          intersection.point,
          on: source,
          tolerance: tolerance
        , using: &execution),
        try BRepSewingEdgeSubdivider().contains(
          intersection.point,
          on: ruled,
          tolerance: tolerance
        , using: &execution)
      else {
        continue
      }
      try appendUnique(intersection.point, to: &points, tolerance: tolerance, using: &execution)
    }
    return points.sorted(by: pointOrder)
  }

  /// Resolves coplanar circular loci in their native two-dimensional
  /// geometry. Sending this case through a three-parameter ruled-surface
  /// chart leaves a coincident plane direction unconstrained and can keep
  /// the subdivision frontier alive down to the global resource limit.
  private func coplanarCircularIntersections(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D]? {
    try execution.consumeWork(1)
    guard let firstCircle = circularLocus(first.curve),
      let secondCircle = circularLocus(second.curve)
    else {
      return nil
    }
    let firstNormal = try firstCircle.normal.normalized(
      tolerance: tolerance.angle
    )
    let secondNormal = try secondCircle.normal.normalized(
      tolerance: tolerance.angle
    )
    guard abs(firstNormal.dot(secondNormal)) >= 1.0 - tolerance.angle else {
      return nil
    }
    let centerOffset = secondCircle.center - firstCircle.center
    let normalSeparation = centerOffset.dot(firstNormal)
    guard abs(normalSeparation) <= tolerance.distance else { return nil }
    let planarOffset = centerOffset - firstNormal * normalSeparation
    let centerDistance = planarOffset.length
    let radiusSum = firstCircle.radius + secondCircle.radius
    let radiusDifference = abs(firstCircle.radius - secondCircle.radius)
    if centerDistance > radiusSum + tolerance.distance
      || centerDistance < radiusDifference - tolerance.distance
    {
      return []
    }
    if centerDistance <= tolerance.distance {
      guard radiusDifference <= tolerance.distance else { return [] }
      return try endpointContacts(first, second, tolerance: tolerance, using: &execution)
        .sorted(by: pointOrder)
    }

    let alongCenter =
      (firstCircle.radius * firstCircle.radius
        - secondCircle.radius * secondCircle.radius
        + centerDistance * centerDistance) / (2.0 * centerDistance)
    let heightSquared =
      firstCircle.radius * firstCircle.radius
      - alongCenter * alongCenter
    let squaredResolution =
      tolerance.distance
      * max(
        firstCircle.radius,
        secondCircle.radius,
        centerDistance,
        1.0
      ) * 8.0
    guard heightSquared >= -squaredResolution else { return [] }
    let centerDirection = planarOffset / centerDistance
    let base = firstCircle.center + centerDirection * alongCenter
    let perpendicular = try firstNormal.cross(centerDirection).normalized(
      tolerance: tolerance.angle
    )
    let height = sqrt(max(heightSquared, 0.0))
    let candidates =
      height <= tolerance.distance
      ? [base]
      : [base + perpendicular * height, base + perpendicular * -height]
    let subdivider = BRepSewingEdgeSubdivider()
    var points: [Point3D] = []
    for point in candidates
    where try subdivider.contains(
      point,
      on: first,
      tolerance: tolerance
    , using: &execution)
      && subdivider.contains(
        point,
        on: second,
        tolerance: tolerance
      , using: &execution)
    {
      try appendUnique(point, to: &points, tolerance: tolerance, using: &execution)
    }
    return points.sorted(by: pointOrder)
  }

  private func circularLocus(_ curve: Curve3D) -> CircularLocus? {
    switch curve {
    case .circle(let circle):
      CircularLocus(
        center: circle.center,
        normal: circle.normal,
        radius: circle.radius
      )
    case .analytic(.circle(let center, let normal, let radius)),
      .analytic(.arc(let center, let normal, let radius, _, _)):
      CircularLocus(center: center, normal: normal, radius: radius)
    default:
      nil
    }
  }

  private func samePlaneTorusSectionIntersections(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D]? {
    try execution.consumeWork(1)
    // Distinct components of one plane-torus section never cross in
    // their interiors: root-free full branches keep a strictly positive
    // discriminant between the sheets, bounded components occupy
    // disjoint minor-angle windows, and inner-tangency branches meet
    // only at their nodal endpoints. Every admissible contact is
    // therefore an endpoint contact, which is collected structurally.
    guard case .analytic(.planeTorus(let firstSection)) = first.curve,
      case .analytic(.planeTorus(let secondSection)) = second.curve
    else {
      return nil
    }
    guard firstSection.torusSurface == secondSection.torusSurface,
      case .plane(let firstPlane) = firstSection.planeSurface,
      case .plane(let secondPlane) = secondSection.planeSurface
    else {
      return nil
    }
    let firstNormalLength = firstPlane.normal.length
    let secondNormalLength = secondPlane.normal.length
    guard firstNormalLength > tolerance.angle,
      secondNormalLength > tolerance.angle
    else {
      return nil
    }
    let firstNormal = firstPlane.normal / firstNormalLength
    let secondNormal = secondPlane.normal / secondNormalLength
    let parallel =
      abs(firstNormal.dot(secondNormal))
      >= 1.0 - tolerance.angle
    let separation = abs(
      (secondPlane.origin - firstPlane.origin).dot(firstNormal)
    )
    guard parallel, separation <= tolerance.distance else {
      return nil
    }
    // Two sub-spans of one simple component reach this classifier only
    // after the whole-span and partitioned coincidence passes found at
    // most one shared structural point, so interior overlap is already
    // excluded and every remaining contact is an endpoint contact.
    let sameComponent =
      firstSection.componentKind
      == secondSection.componentKind
      && abs(
        firstSection.lowerMinorAngle - secondSection.lowerMinorAngle
      ) <= tolerance.angle
      && abs(
        firstSection.upperMinorAngle - secondSection.upperMinorAngle
      ) <= tolerance.angle
    let disjointComponents: Bool
    switch (firstSection.componentKind, secondSection.componentKind) {
    case (.negativeFullBranch, .positiveFullBranch),
      (.positiveFullBranch, .negativeFullBranch),
      (.negativeInnerTangencyBranch, .positiveInnerTangencyBranch),
      (.positiveInnerTangencyBranch, .negativeInnerTangencyBranch):
      disjointComponents = true
    case (.boundedMinorAngle, .boundedMinorAngle):
      disjointComponents =
        firstSection.upperMinorAngle
        <= secondSection.lowerMinorAngle + tolerance.angle
        || secondSection.upperMinorAngle
          <= firstSection.lowerMinorAngle + tolerance.angle
    default:
      disjointComponents = false
    }
    guard sameComponent || disjointComponents else {
      // Distinct-kind, window-overlapping components of one section
      // are a coincident span the upstream classifiers own.
      return nil
    }
    let contacts = try endpointContacts(first, second, tolerance: tolerance, using: &execution)
    return contacts.sorted(by: pointOrder)
  }

  private func sourceLeavesPlane(
    _ source: BRepSewingEdge,
    range: ScalarInterval,
    plane: Plane3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let parameter = range.lower + range.width * fraction
      let point = try source.curve.point(
        at: parameter,
        tolerance: tolerance
      , using: &execution)
      let separation = abs((point - plane.origin).dot(plane.normal))
      if separation > tolerance.distance {
        return true
      }
    }
    return false
  }

  private func planeTrimmedRange(
    source: BRepSewingEdge,
    range: ScalarInterval,
    plane: Plane3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    try execution.consumeWork(1)
    try Task.checkCancellation()
    try tolerance.validate()
    // A numerical station leaving a chart plane cannot exclude earlier roots.
    return range
  }

  private func ruledLine(_ curve: Curve3D) -> Line3D? {
    switch curve {
    case .line(let line):
      return line
    case .analytic(.line(let origin, let direction)):
      return Line3D(origin: origin, direction: direction)
    default:
      return nil
    }
  }

  private func analyticCurvePlane(
    _ curve: Curve3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Plane3D? {
    try execution.consumeWork(1)
    let center: Point3D
    let normal: Vector3D
    switch curve {
    case .analytic(.circle(let circleCenter, let circleNormal, _)),
      .analytic(.arc(let circleCenter, let circleNormal, _, _, _)):
      center = circleCenter
      normal = circleNormal
    case .analytic(.ellipse(let ellipseCenter, let ellipseNormal, _, _, _)):
      center = ellipseCenter
      normal = ellipseNormal
    case .analytic(.planeTorus(let planeTorusCurve)):
      guard case .plane(let sectionPlane) = planeTorusCurve.planeSurface else {
        return nil
      }
      center = sectionPlane.origin
      normal = sectionPlane.normal
    case .circle(let circle):
      center = circle.center
      normal = circle.normal
    default:
      return nil
    }
    let length = normal.length
    guard length > tolerance.angle else { return nil }
    let plane = Plane3D(origin: center, normal: normal / length)
    try plane.validate(tolerance: tolerance)
    return plane
  }

  private func analyticRuledPlane(
    line: Line3D,
    extrusionDirection: Vector3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Plane3D? {
    try execution.consumeWork(1)
    let normal = line.direction.cross(extrusionDirection)
    guard normal.length > tolerance.angle else { return nil }
    let plane = Plane3D(
      origin: line.origin,
      normal: normal / normal.length
    )
    try plane.validate(tolerance: tolerance)
    return plane
  }

  private func intersections(
    source: BRepSewingEdge,
    sourceRange: ScalarInterval,
    ruled: BRepSewingEdge,
    plane: Plane3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> [Point3D] {
    try execution.consumeWork(1)
    // The chart plane is unbounded, so the adaptive intersector receives
    // a finite window around the ruled segment; accepted crossings must
    // lie on that segment, so padding by both edge extents keeps every
    // admissible crossing inside the window.
    let surface = Surface3D.plane(plane)
    let startProjection = try surface.parameterProjection(
      of: ruled.startPoint,
      tolerance: tolerance
    , using: &execution)
    let endProjection = try surface.parameterProjection(
      of: ruled.endPoint,
      tolerance: tolerance
    , using: &execution)
    let padding = max(
      (source.endPoint - source.startPoint).length,
      (ruled.endPoint - ruled.startPoint).length,
      tolerance.distance * 1_024.0
    )
    let trimmedRange = try planeTrimmedRange(
      source: source,
      range: sourceRange,
      plane: plane,
      tolerance: tolerance
    , using: &execution)
    let intersections: [CurveSurfaceIntersection]
    do {
      intersections = try DefaultCurveSurfaceIntersector().intersections(
        curve: source.curve,
        surface: surface,
        options: CurveSurfaceIntersectionOptions(
          curveRange: trimmedRange,
          surfaceURange: try ScalarInterval(
            lower: min(startProjection.u, endProjection.u) - padding,
            upper: max(startProjection.u, endProjection.u) + padding
          ),
          surfaceVRange: try ScalarInterval(
            lower: min(startProjection.v, endProjection.v) - padding,
            upper: max(startProjection.v, endProjection.v) + padding
          ),
          // Near-miss exclusion beside a marched contact margin needs
          // leaf cells at the tolerance scale, far below the default
          // depth of the three-parameter adaptive subdivision, and a
          // near-tangential quartic keeps a wide frontier alive on the
          // way down.
          maximumSubdivisionDepth: 32,
          maximumSubdivisionCells: 4_194_304,
          maximumIterations: 64
        ),
        tolerance: tolerance
      , using: &execution)
    } catch {
      throw contextualized(
        error,
        stage: "analytic plane root certification",
        tolerance: tolerance
      )
    }
    var points: [Point3D] = []
    for intersection in intersections {
      guard
        try BRepSewingEdgeSubdivider().contains(
          intersection.point,
          on: source,
          tolerance: tolerance
        , using: &execution),
        try BRepSewingEdgeSubdivider().contains(
          intersection.point,
          on: ruled,
          tolerance: tolerance
        , using: &execution)
      else {
        continue
      }
      try appendUnique(intersection.point, to: &points, tolerance: tolerance, using: &execution)
    }
    return points.sorted(by: pointOrder)
  }

  private func spansAreEquivalent(
    _ first: BRepSewingEdge,
    _ second: BRepSewingEdge,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    let matcher = CurveSpanCoincidenceMatcher()
    let firstSpan = CurveSpanDefinition(first)
    let secondSpan = CurveSpanDefinition(second)
    return try matcher.matches(
      firstSpan,
      secondSpan,
      orientation: .forward,
      tolerance: tolerance
    , using: &execution)
      || matcher.matches(
        firstSpan,
        secondSpan,
        orientation: .reversed,
        tolerance: tolerance
      , using: &execution)
  }

  private func exactRationalCurve(
    _ edge: BRepSewingEdge,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BSplineCurve3D? {
    try execution.consumeWork(1)
    let range = try parameterRange(edge, using: &execution)
    if case .bSpline(let curve) = edge.curve {
      return try curve.trimmed(
        from: range.lower,
        to: range.upper,
        tolerance: tolerance, using: &execution
      )
    }
    return try AnalyticCurveBSplineBuilder().boundedCurve(
      curve: edge.curve,
      interval: range,
      maximumSpanCount: 4_096,
      tolerance: tolerance
    , using: &execution)
  }

  private func ruledSurface(
    curve: BSplineCurve3D,
    offset: Vector3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> BSplineSurface3D {
    try execution.consumeWork(1)
    let lower = try OriginalParameterQueryStorage.map(curve.controlPoints, using: &execution) { point, execution in point + offset * -1.0 }
    let upper = try OriginalParameterQueryStorage.map(curve.controlPoints, using: &execution) { point, execution in point + offset }
    let surface = BSplineSurface3D(
      uDegree: curve.degree,
      vDegree: 1,
      uKnots: curve.knots,
      vKnots: [0.0, 0.0, 1.0, 1.0],
      controlPoints: [lower, upper],
      weights: [curve.weights, curve.weights]
    )
    try surface.validate(tolerance: tolerance, using: &execution)
    return surface
  }

  private func proceduralRuledSurface(
    curve: Curve3D,
    range: ScalarInterval,
    offset: Vector3D,
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws -> Surface3D {
    try execution.consumeWork(1)
    let lower = Curve3D.rigidImage(
      try RigidImageCurve3D(
        source: curve,
        transform: .translated(by: offset * -1.0),
        tolerance: tolerance, using: &execution
      ))
    let upper = Curve3D.rigidImage(
      try RigidImageCurve3D(
        source: curve,
        transform: .translated(by: offset),
        tolerance: tolerance, using: &execution
      ))
    let surface = Surface3D.procedural(
      .ruled(
        RuledSurface3D(
          startBoundary: lower,
          endBoundary: upper,
          uDomain: .closed(range.lower, range.upper)
        )))
    try surface.validate(tolerance: tolerance, using: &execution)
    return surface
  }

  private func parameterRange(_ edge: BRepSewingEdge,
    using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    try execution.consumeWork(1)
    return try ScalarInterval(
      lower: min(edge.startParameter, edge.endParameter),
      upper: max(edge.startParameter, edge.endParameter)
    )
  }

  private func parameterRange(_ curve: BSplineCurve3D,
    using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    try execution.consumeWork(1)
    guard case .closed(let lower, let upper) = curve.domain else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: nil,
        message: "An exact ruled trim surface requires a bounded rational curve."
      )
    }
    return try ScalarInterval(lower: lower, upper: upper)
  }

  private func appendUnique(
    _ point: Point3D,
    to points: inout [Point3D],
    tolerance: ModelingTolerance
  ,
    using execution: inout OriginalQueryExecution
  ) throws  {
    try execution.consumeWork(1)
    guard
      try OriginalParameterQueryStorage.contains(points, using: &execution, predicate: { candidate, execution in
        candidate.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
      }) == false
    else {
      return
    }
    try OriginalParameterQueryStorage.append(point, to: &points, using: &execution)
  }

  private func pointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
    if lhs.x != rhs.x { return lhs.x < rhs.x }
    if lhs.y != rhs.y { return lhs.y < rhs.y }
    return lhs.z < rhs.z
  }

  private func contextualized(_ error: any Error, stage: String,
    tolerance: ModelingTolerance) -> any Error {
    let classification = KernelError.wrapping(error, phase: .geometry, tolerance: tolerance)
    return OriginalQueryFailure.contextualizing(error, classification: KernelError(
      phase: classification.phase, code: classification.code, residual: classification.residual,
      tolerance: classification.tolerance ?? tolerance,
      message: "Exact trim-edge \(stage) failed: \(classification.message)"))
  }

  private struct SpanPair: Hashable, Sendable {
    let firstIndex: Int
    let secondIndex: Int
  }

  private struct CircularLocus {
    let center: Point3D
    let normal: Vector3D
    let radius: Double
  }
}
