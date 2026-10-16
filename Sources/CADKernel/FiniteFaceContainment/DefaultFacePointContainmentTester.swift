import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Foundation

public struct DefaultFacePointContainmentTester: FacePointContainmentTesting,
  FacePointContainmentSessionPreparing,
  FacePointContainmentPreparationCaching,
  FaceParameterContainmentPreparationCaching,
  FaceParameterContainmentSessionPreparing
{
  private let maximumSubdivisionDepth: Int
  private let remainingSourceDepth: Int
  private let maximumAlgebraicDepth: Int

  public init(
    maximumSubdivisionDepth: Int = 48,
    remainingSourceDepth: Int = 16,
    maximumAlgebraicDepth: Int = 32
  ) {
    self.maximumSubdivisionDepth = maximumSubdivisionDepth
    self.remainingSourceDepth = remainingSourceDepth
    self.maximumAlgebraicDepth = maximumAlgebraicDepth
  }

  private func reserve<Value>(_ count: Int, in values: inout [Value],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    try consume(0, tolerance: tolerance, using: &execution)
    let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Value>.stride)
    guard count >= 0, !bytes.overflow else {
      throw KernelError(phase: .classification, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Original face preparation buffer byte count overflowed.")
    }
    try execution.retainStorage(bytes: bytes.partialValue)
    values.reserveCapacity(count)
  }

  private func reverseOriginalCurves(_ curves: inout [SurfaceParameterCurve],
    lower: Int, upper: Int, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    var first = lower, last = upper - 1
    while first < last {
      try consume(0, tolerance: tolerance, using: &execution)
      curves.swapAt(first, last)
      first += 1; last -= 1
    }
  }

  private func consume(_ depth: Int, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    let maximumSubdivisionDepth = min(self.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
    let remainingSourceDepth = min(16, self.remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth)
    try Task.checkCancellation()
    guard maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 48,
          remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth) else {
      throw KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance,
        message: "Finite face containment requires supported independent subdivision, source and algebra ceilings.")
    }
    guard depth <= maximumSubdivisionDepth else {
      throw KernelError(phase: .classification, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Finite face containment exhausted the caller's subdivision depth.")
    }
    try execution.admitGeometricDepth(depth); try execution.consumeWork(1)
  }

  public func contains(_ point: Point3D, on faceID: FaceID,
    in model: BRepModel, tolerance: ModelingTolerance) throws -> Bool {
    var execution = try OriginalQueryExecution.kernelOriginal()
    return try contains(point, on: faceID, in: model, tolerance: tolerance, using: &execution)
  }

  public func contains(_ point: Point3D, on faceID: FaceID,
    in model: BRepModel, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> Bool {
    do {
    var cache = FacePointContainmentPreparationCache()
    let tester = self
    return try tester.contains(point, on: faceID, in: model,
      preparationCache: &cache, tolerance: tolerance, using: &execution)

    } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
  }

  public func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
    tolerance: ModelingTolerance) throws -> (any FacePointContainmentSession)? {
    var execution = try OriginalQueryExecution.kernelOriginal()
    return try preparedContainmentSession(for: faceIDs, in: model,
      tolerance: tolerance, using: &execution)
  }

  public func preparedContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws -> any FacePointContainmentSession {
    do {
    return try makeContainmentSession(for: faceIDs, in: model,
      tolerance: tolerance, using: &execution)

    } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
  }



  func makeContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws -> any FacePointContainmentSession {
    try makePreparedSession(for: faceIDs, in: model, tolerance: tolerance, using: &execution)
  }

  func makeParameterContainmentSession(for faceIDs: [FaceID], in model: BRepModel,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws -> any FaceParameterContainmentSession {
    try makePreparedSession(for: faceIDs, in: model, tolerance: tolerance, using: &execution)
  }

  private func makePreparedSession(for faceIDs: [FaceID], in model: BRepModel,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Session {
    let prepared = try execution.withPreparationScope { execution in
      try consume(0, tolerance: tolerance, using: &execution)
      try tolerance.validate()
      var faces: [FaceID: FacePointContainmentPreparationCache.PreparedFace] = [:]
      for faceID in faceIDs where faces[faceID] == nil {
        let face = try prepare(faceID: faceID, model: model,
          tolerance: tolerance, using: &execution)
        try OriginalParameterQueryStorage.set(face, for: faceID, in: &faces, using: &execution)
      }
      return faces
    }
    try execution.retainStorage(bytes: MemoryLayout<Session.Payload>.stride
      + 2 * MemoryLayout<UnsafeRawPointer>.stride)
    let lifetime = try PreparedBooleanQueryLifetime.retain(depth: prepared.depth, using: &execution)
    let payload = Session.Payload(tester: self, preparedFaces: prepared.result,
      tolerance: tolerance, lifetime: lifetime)
    try execution.checkpoint()
    return Session(payload: payload)
  }

  func contains(
    _ point: Point3D,
    on faceID: FaceID,
    in model: BRepModel,
    preparationCache: inout FacePointContainmentPreparationCache,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> Bool {
    try consume(0, tolerance: tolerance, using: &execution)
    try tolerance.validate()
    try point.validate()
    let preparedFace: FacePointContainmentPreparationCache.PreparedFace
    if let cached = preparationCache.faces[faceID] {
      preparedFace = cached
    } else {
      preparedFace = try prepare(
        faceID: faceID,
        model: model,
        tolerance: tolerance
      , using: &execution)
      try OriginalParameterQueryStorage.set(preparedFace, for: faceID,
        in: &preparationCache.faces, using: &execution)
    }
    return try contains(
      point,
      on: preparedFace,
      tolerance: tolerance
    , using: &execution)
  }

  func contains(
    _ point: Point3D,
    on preparedFace: FacePointContainmentPreparationCache.PreparedFace,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> Bool {
    return try execution.withProofScope(maximum: .init(value: maximumAlgebraicDepth,
      coefficient: maximumAlgebraicDepth)) { execution in
    let maximumSubdivisionDepth = min(self.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
    try consume(0, tolerance: tolerance, using: &execution)
    let result: SurfaceParameterProjectionResult
    if let domain = preparedFace.parameterBounds {
      result = try DefaultSurfaceParameterProjector().projectionResult(of: point,
        on: preparedFace.surface, over: domain,
        options: SurfaceParameterProjectionOptions(), tolerance: tolerance,
        maximumSubdivisionDepth: min(maximumSubdivisionDepth, 32),
        remainingSourceDepth: min(16, remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth),
        maximumAlgebraicDepth: min(maximumAlgebraicDepth, execution.effectiveLimits.maximumValueDepth,
          execution.effectiveLimits.maximumCoefficientDepth), using: &execution)
    } else {
      // Nil extent is issued only for untrimmed native plane/cylinder proximity.
      result = try preparedFace.surface.parameterProjectionResult(of: point,
        tolerance: tolerance, using: &execution)
    }
    switch result {
    case .projected(let projection):
      return try contains(
        SurfaceParameter(u: projection.u, v: projection.v),
        on: preparedFace,
        tolerance: tolerance
      , using: &execution)
    case .outsideTolerance:
      return false
    }
      }
}

  func contains(
    _ parameter: SurfaceParameter,
    on faceID: FaceID,
    in model: BRepModel,
    preparationCache: inout FacePointContainmentPreparationCache,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> Bool {
    try consume(0, tolerance: tolerance, using: &execution)
    try tolerance.validate()
    try parameter.validate()
    let preparedFace: FacePointContainmentPreparationCache.PreparedFace
    if let cached = preparationCache.faces[faceID] {
      preparedFace = cached
    } else {
      preparedFace = try prepare(
        faceID: faceID,
        model: model,
        tolerance: tolerance
      , using: &execution)
      try OriginalParameterQueryStorage.set(preparedFace, for: faceID,
        in: &preparationCache.faces, using: &execution)
    }
    return try contains(
      parameter,
      on: preparedFace,
      tolerance: tolerance
    , using: &execution)
  }

  private func contains(
    _ parameter: SurfaceParameter,
    on preparedFace: FacePointContainmentPreparationCache.PreparedFace,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> Bool {
    return try execution.withProofScope(maximum: .init(value: maximumAlgebraicDepth,
      coefficient: maximumAlgebraicDepth)) { execution in
    let maximumSubdivisionDepth = min(self.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
    try consume(0, tolerance: tolerance, using: &execution)
    if preparedFace.loops.isEmpty {
      return try preparedFace.surface.uDomain.contains(
        parameter.u,
        tolerance: tolerance
      )
        && preparedFace.surface.vDomain.contains(
          parameter.v,
          tolerance: tolerance
        )
    }
    // Band faces are bounded by loops that wind a periodic direction;
    // their unwrapped polygons are open paths, so planar winding is
    // undefined and containment reduces to lying between the winding
    // loops' levels in the transverse coordinate.
    var windingULevels: [Double] = []
    var windingVLevels: [Double] = []
    try reserve(preparedFace.loops.count, in: &windingULevels, tolerance: tolerance, using: &execution)
    try reserve(preparedFace.loops.count, in: &windingVLevels, tolerance: tolerance, using: &execution)
    for loop in preparedFace.loops {
      try consume(0, tolerance: tolerance, using: &execution)
      if loop.uWinding != 0,
        loop.vWinding == 0,
        let level = loop.constantVLevel
      {
        windingVLevels.append(level)
      }
      if loop.vWinding != 0,
        loop.uWinding == 0,
        let level = loop.constantULevel
      {
        windingULevels.append(level)
      }
    }
    if windingVLevels.count >= 2 || windingULevels.count >= 2 {
      let projectionPoint = UV(u: parameter.u, v: parameter.v)
      var inside = true
      if windingVLevels.count >= 2,
        let lowerLevel = windingVLevels.min(),
        let upperLevel = windingVLevels.max()
      {
        let query = try aligned(
          projectionPoint,
          to: UV(u: 0.0, v: (lowerLevel + upperLevel) * 0.5),
          on: preparedFace.surface
        , using: &execution)
        inside =
          inside
          && query.v >= lowerLevel - tolerance.angle
          && query.v <= upperLevel + tolerance.angle
      }
      if windingULevels.count >= 2,
        let lowerLevel = windingULevels.min(),
        let upperLevel = windingULevels.max()
      {
        let query = try aligned(
          projectionPoint,
          to: UV(u: (lowerLevel + upperLevel) * 0.5, v: 0.0),
          on: preparedFace.surface
        , using: &execution)
        inside =
          inside
          && query.u >= lowerLevel - tolerance.angle
          && query.u <= upperLevel + tolerance.angle
      }
      return inside
    }
    var insideOuter = false
    for loop in preparedFace.loops {
      try consume(0, tolerance: tolerance, using: &execution)
      let query = try aligned(
        UV(u: parameter.u, v: parameter.v),
        to: loop.center,
        on: preparedFace.surface
      , using: &execution)
      // A near-seam query has several periodic chart representatives
      // and only one of them lines up with the unrolled polygon, so
      // every in-extent representative votes and any inside verdict
      // wins; representatives beyond the polygon's parameter extent
      // can never be inside it.
      var classification = PlanarPointClassification.outside
      for representative in try periodicRepresentatives(
        of: query,
        on: preparedFace.surface, using: &execution
      ) {
        let candidate: PlanarPointClassification
        if let predicate = loop.certifiedPredicate {
          candidate = try predicate.classify(Point2D(x: representative.u, y: representative.v),
        tolerance: tolerance,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        using: &execution)
        } else {
          throw KernelError(
            phase: .classification,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message:
              "Trimmed-face containment requires a certified contractible pcurve loop or a certified constant-level periodic band."
          )
        }
        if candidate == .inside {
          classification = .inside
          break
        }
        if candidate != .outside {
          classification = candidate
        }
      }
      guard classification != .indeterminate else {
        throw KernelError(
          phase: .classification,
          code: .classificationFailure,
          tolerance: tolerance,
          message: "Trimmed-face containment could not resolve a planar predicate."
        )
      }
      switch loop.role {
      case .outer:
        insideOuter = classification != .outside
      case .inner:
        if classification == .inside { return false }
      }
    }
    return insideOuter
      }
}

  func prepare(
    faceID: FaceID,
    model: BRepModel,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> FacePointContainmentPreparationCache.PreparedFace {
    return try execution.withProofScope(maximum: .init(value: maximumAlgebraicDepth,
      coefficient: maximumAlgebraicDepth)) { execution in
    let maximumSubdivisionDepth = min(self.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
    let remainingSourceDepth = min(16, self.remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth)
    try consume(0, tolerance: tolerance, using: &execution)
    guard let face = model.faces[faceID],
      let surface = model.geometry.surfaces[face.surfaceID]
    else {
      throw KernelError(
        phase: .topology,
        code: .missingReference,
        tolerance: tolerance,
        message: "Trimmed-face containment references missing face geometry."
      )
    }
    try surface.validate(tolerance: tolerance, using: &execution)
    let untrimmedPrimitive: Bool
    switch surface {
    case .plane, .cylinder, .analytic(.plane), .analytic(.cylinder):
      untrimmedPrimitive = face.loops.isEmpty
    default:
      untrimmedPrimitive = false
    }
    if face.loops.isEmpty && !untrimmedPrimitive {
      let unboundedU: Bool
      let unboundedV: Bool
      if case .unbounded = surface.uDomain { unboundedU = true } else { unboundedU = false }
      if case .unbounded = surface.vDomain { unboundedV = true } else { unboundedV = false }
      // FIXME(INCOMPLETE_IMPLEMENTATION): Nonprimitive untrimmed unbounded face
      // containment has no original projection/threshold producer. Public and
      // prepared callers must fail until that actual source capability exists.
      guard !unboundedU && !unboundedV else {
        execution.context = execution.context.at(stage: .domain)
        throw KernelError(phase: .classification, code: .unsupportedCapability, tolerance: tolerance,
          message: "Untrimmed unbounded nonprimitive faces require original membership coverage.")
      }
    }
    var regions: [FacePointContainmentPreparationCache.LoopRegion] = []
    try reserve(face.loops.count, in: &regions, tolerance: tolerance, using: &execution)
    for loopID in face.loops {
      try consume(0, tolerance: tolerance, using: &execution)
      guard let loop = model.loops[loopID] else {
        throw KernelError(
          phase: .topology,
          code: .missingReference,
          tolerance: tolerance,
          message: "Trimmed-face containment references a missing loop."
        )
      }
      let polygon: [UV]
      let certification: LoopCertification
      do {
        polygon = try loopParameters(
          loop,
          surface: surface,
          model: model,
          tolerance: tolerance
        , using: &execution)
        certification = try certifyLoop(
          loop,
          surface: surface,
          model: model,
          tolerance: tolerance
        , using: &execution)
      } catch {
        let wrapped = KernelError.wrapping(
          error,
          phase: .classification,
          tolerance: tolerance
        )
        let classification = KernelError(
          phase: wrapped.phase,
          code: wrapped.code,
          featureID: wrapped.featureID,
          subshapeID: wrapped.subshapeID,
          residual: wrapped.residual,
          tolerance: wrapped.tolerance ?? tolerance,
          message:
            "Trimmed-face containment could not parameterize loop \(loopID) on face \(faceID): \(wrapped.message)"
        )
        throw OriginalQueryFailure.contextualizing(error, classification: classification)
      }
      regions.append(FacePointContainmentPreparationCache.LoopRegion(
        role: loop.role,
        polygon: polygon,
        certifiedPredicate: certification.predicate,
        uWinding: certification.uWinding,
        vWinding: certification.vWinding,
        constantULevel: certification.constantULevel,
        constantVLevel: certification.constantVLevel
      ))
    }
    return FacePointContainmentPreparationCache.PreparedFace(
      surface: surface,
      loops: regions,
      faceID: faceID, surfaceID: face.surfaceID,
      parameterBounds: untrimmedPrimitive ? nil : try OriginalFaceParameterBounds.resolve(for: faceID,
        surface: surface, model: model, tolerance: tolerance,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    )
      }
}

  private func certifyLoop(
    _ loop: Loop,
    surface: Surface3D,
    model: BRepModel,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> LoopCertification {
    let maximumSubdivisionDepth = min(self.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
    let remainingSourceDepth = min(16, self.remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth)
    let parameterTolerance = max(tolerance.distance, tolerance.angle)
    let parameterTopology = try SurfaceParameterTopology(surface: surface, using: &execution)
    var authoredCurves: [SurfaceParameterCurve] = []
    try reserve(loop.coedges.count, in: &authoredCurves, tolerance: tolerance, using: &execution)
    for coedge in loop.coedges {
      try consume(0, tolerance: tolerance, using: &execution)
      guard let edge = model.edges[coedge.edgeID],
        let spatialCurve = model.geometry.curves[edge.curveID]
      else {
        throw KernelError(
          phase: .topology,
          code: .missingReference,
          tolerance: tolerance,
          message: "Certified face containment references missing edge geometry."
        )
      }
      let parameterCurve: SurfaceParameterCurve
      if let authored = coedge.surfaceParameterCurve {
        parameterCurve = authored
      } else {
        guard let trim = edge.trim else {
          throw KernelError(
            phase: .classification,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message:
              "Certified face containment requires exact pcurves or exact trimmed edge geometry."
          )
        }
        let startParameter =
          coedge.orientation == .forward
          ? trim.startParameter
          : trim.endParameter
        let endParameter =
          coedge.orientation == .forward
          ? trim.endParameter
          : trim.startParameter
        parameterCurve = try ExactFacePcurveBuilder().surfaceParameterCurve(
          for: spatialCurve,
          startParameter: startParameter,
          endParameter: endParameter,
          on: surface,
          tolerance: tolerance
        , using: &execution)
      }
      try parameterCurve.validate(on: surface, tolerance: tolerance,
        remainingSourceDepth: remainingSourceDepth,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
      authoredCurves.append(parameterCurve)
    }
    guard authoredCurves.isEmpty == false else {
      throw KernelError(
        phase: .classification,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified face containment requires a non-empty trim loop."
      )
    }
    if let singularStartIndex = try authoredCurves.firstIndex(where: { curve in
      try parameterTopology.isUSingular(
        try curve.startParameter(tolerance: tolerance, using: &execution),
        tolerance: tolerance
      , using: &execution)
    }), singularStartIndex != authoredCurves.startIndex {
      try reverseOriginalCurves(&authoredCurves, lower: 0, upper: singularStartIndex, tolerance: tolerance, using: &execution)
      try reverseOriginalCurves(&authoredCurves, lower: singularStartIndex,
        upper: authoredCurves.count, tolerance: tolerance, using: &execution)
      try reverseOriginalCurves(&authoredCurves, lower: 0, upper: authoredCurves.count, tolerance: tolerance, using: &execution)
    }

    var alignedCurves: [SurfaceParameterCurve] = []
    let doubled = authoredCurves.count.multipliedReportingOverflow(by: 2)
    let capacity = doubled.partialValue.addingReportingOverflow(1)
    guard !doubled.overflow, !capacity.overflow else {
      throw KernelError(phase: .classification, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Original aligned chart capacity overflowed.")
    }
    try reserve(capacity.partialValue, in: &alignedCurves, tolerance: tolerance, using: &execution)
    var firstStart: SurfaceParameter?
    var previousEnd: SurfaceParameter?
    for parameterCurve in authoredCurves {
      try consume(0, tolerance: tolerance, using: &execution)
      let rawStart = try parameterCurve.startParameter(tolerance: tolerance, using: &execution)
      let crossesUSingularity =
        try previousEnd.map {
          try parameterTopology.isUSingular($0, tolerance: tolerance, using: &execution)
            && parameterTopology.isUSingular(rawStart, tolerance: tolerance, using: &execution)
        } ?? false
      let alignedStart =
        crossesUSingularity
        ? UV(u: rawStart.u, v: rawStart.v)
        : try unwrapped(
          UV(u: rawStart.u, v: rawStart.v),
          relativeTo: previousEnd.map { UV(u: $0.u, v: $0.v) },
          on: surface
        , using: &execution)
      let uShift = alignedStart.u - rawStart.u
      let vShift = alignedStart.v - rawStart.v
      let alignedCurve: SurfaceParameterCurve
      if uShift == 0.0, vShift == 0.0 {
        alignedCurve = parameterCurve
      } else {
        alignedCurve = .periodicTranslation(
          base: parameterCurve,
          uShift: uShift,
          vShift: vShift
        )
      }
      let start = try alignedCurve.startParameter(tolerance: tolerance, using: &execution)
      if let previousEnd {
        let residual = hypot(start.u - previousEnd.u, start.v - previousEnd.v)
        if residual > parameterTolerance,
          try parameterTopology.isUSingular(previousEnd, tolerance: tolerance, using: &execution),
          try parameterTopology.isUSingular(start, tolerance: tolerance, using: &execution)
        {
          alignedCurves.append(
            .constantV(
              v: start.v,
              uStart: previousEnd.u,
              uEnd: start.u
            ))
        } else if residual > parameterTolerance {
          throw KernelError(
            phase: .classification,
            code: .topologyFailure,
            residual: residual,
            tolerance: tolerance,
            message: "Certified face pcurves do not form one continuous chart chain."
          )
        }
      } else {
        firstStart = start
      }
      previousEnd = try continuousEndParameter(
        of: alignedCurve,
        from: start,
        on: surface,
        tolerance: tolerance
      , using: &execution)
      alignedCurves.append(alignedCurve)
    }
    guard let firstStart, var previousEnd else {
      throw KernelError(
        phase: .classification,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Certified face containment requires a non-empty trim loop."
      )
    }
    let closureResidual = hypot(
      previousEnd.u - firstStart.u,
      previousEnd.v - firstStart.v
    )
    if closureResidual > parameterTolerance,
      try parameterTopology.isUSingular(previousEnd, tolerance: tolerance, using: &execution),
      try parameterTopology.isUSingular(firstStart, tolerance: tolerance, using: &execution)
    {
      alignedCurves.append(
        .constantV(
          v: firstStart.v,
          uStart: previousEnd.u,
          uEnd: firstStart.u
        ))
      previousEnd = firstStart
    }
    let uWinding = try periodicWinding(
      displacement: previousEnd.u - firstStart.u,
      domain: surface.uDomain,
      tolerance: tolerance
    )
    let vWinding = try periodicWinding(
      displacement: previousEnd.v - firstStart.v,
      domain: surface.vDomain,
      tolerance: tolerance
    )
    if uWinding == 0, vWinding == 0 {
      let predicate: CertifiedSurfaceParameterLoopPredicate
      predicate = try CertifiedSurfaceParameterLoopPredicate(curves: alignedCurves,
        on: surface, uPeriod: parameterTopology.uPeriod, vPeriod: parameterTopology.vPeriod,
        tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
      return LoopCertification(predicate: predicate, uWinding: 0, vWinding: 0,
        constantULevel: nil, constantVLevel: nil)
    }
    guard abs(uWinding) + abs(vWinding) == 1 else {
      throw KernelError(
        phase: .classification,
        code: .unsupportedCapability,
        tolerance: tolerance,
        message:
          "Certified face containment supports primitive periodic trim loops with one winding generator."
      )
    }
    let bounds = try certifiedBounds(
      of: alignedCurves,
      on: surface,
      tolerance: tolerance
    , using: &execution)
    if uWinding != 0,
      vWinding == 0,
      bounds.v.width <= parameterTolerance * 2.0
    {
      return LoopCertification(
        predicate: nil,
        uWinding: uWinding,
        vWinding: 0,
        constantULevel: nil,
        constantVLevel: bounds.v.midpoint
      )
    }
    if vWinding != 0,
      uWinding == 0,
      bounds.u.width <= parameterTolerance * 2.0
    {
      return LoopCertification(
        predicate: nil,
        uWinding: 0,
        vWinding: vWinding,
        constantULevel: bounds.u.midpoint,
        constantVLevel: nil
      )
    }
    throw KernelError(
      phase: .classification,
      code: .unsupportedCapability,
      tolerance: tolerance,
      message: "A non-contractible face trim must have a certified constant transverse level."
    )
  }

  private func continuousEndParameter(
    of curve: SurfaceParameterCurve,
    from start: SurfaceParameter,
    on surface: Surface3D,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
    let maximumSubdivisionDepth = min(self.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
    let remainingSourceDepth = min(16, self.remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth)
    let topology = try SurfaceParameterTopology(surface: surface, using: &execution)
    let minimumPeriod: Double?
    switch (topology.uPeriod, topology.vPeriod) {
    case let (u?, v?): minimumPeriod = min(u, v)
    case let (u?, nil): minimumPeriod = u
    case let (nil, v?): minimumPeriod = v
    case (nil, nil): minimumPeriod = nil
    }
    guard let minimumPeriod else {
      return try curve.endParameter(tolerance: tolerance, using: &execution)
    }
    var enclosures = try CertifiedSurfaceParameterCurveEncloser(maximumSubdivisionDepth: maximumSubdivisionDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth,
        remainingSourceDepth: remainingSourceDepth).enclosures(
      for: curve,
      on: surface,
      maximumWidth: minimumPeriod * 0.25,
      tolerance: tolerance
    , using: &execution)
    try OriginalParameterQueryStorage.sort(&enclosures, using: &execution,
      less: { $0.lowerFraction < $1.lowerFraction })
    var reference = UV(u: start.u, v: start.v)
    for enclosure in enclosures {
      try consume(0, tolerance: tolerance, using: &execution)
      reference = UV(
        u: try unwrapped(
          enclosure.u.midpoint,
          relativeTo: reference.u,
          domain: surface.uDomain
        , using: &execution),
        v: try unwrapped(
          enclosure.v.midpoint,
          relativeTo: reference.v,
          domain: surface.vDomain
        , using: &execution)
      )
    }
    let rawEnd = try curve.endParameter(tolerance: tolerance, using: &execution)
    return SurfaceParameter(
      u: try unwrapped(
        rawEnd.u,
        relativeTo: reference.u,
        domain: surface.uDomain
      , using: &execution),
      v: try unwrapped(
        rawEnd.v,
        relativeTo: reference.v,
        domain: surface.vDomain
      , using: &execution)
    )
  }

  private func certifiedBounds(
    of curves: [SurfaceParameterCurve],
    on surface: Surface3D,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> (u: ScalarInterval, v: ScalarInterval) {
    let maximumSubdivisionDepth = min(self.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
    let remainingSourceDepth = min(16, self.remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth)
    var minimumU = Double.infinity
    var maximumU = -Double.infinity
    var minimumV = Double.infinity
    var maximumV = -Double.infinity
    for curve in curves {
      try consume(0, tolerance: tolerance, using: &execution)
      var enclosures = try CertifiedSurfaceParameterCurveEncloser(maximumSubdivisionDepth: maximumSubdivisionDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth,
        remainingSourceDepth: remainingSourceDepth).enclosures(
        for: curve,
        on: surface,
        maximumWidth: Double.greatestFiniteMagnitude.squareRoot(),
        tolerance: tolerance
      , using: &execution)
      for enclosure in enclosures {
        try consume(0, tolerance: tolerance, using: &execution)
        minimumU = min(minimumU, enclosure.u.lower)
        maximumU = max(maximumU, enclosure.u.upper)
        minimumV = min(minimumV, enclosure.v.lower)
        maximumV = max(maximumV, enclosure.v.upper)
      }
    }
    guard minimumU.isFinite,
      maximumU.isFinite,
      minimumV.isFinite,
      maximumV.isFinite
    else {
      throw KernelError(
        phase: .classification,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Certified face containment produced no finite pcurve bounds."
      )
    }
    return (
      try ScalarInterval(lower: minimumU, upper: maximumU),
      try ScalarInterval(lower: minimumV, upper: maximumV)
    )
  }

  private func periodicWinding(
    displacement: Double,
    domain: ParameterDomain,
    tolerance: ModelingTolerance
  ) throws -> Int {
    let parameterTolerance = max(tolerance.distance, tolerance.angle)
    guard case .periodic(let period) = domain else {
      guard abs(displacement) <= parameterTolerance else {
        throw KernelError(
          phase: .classification,
          code: .topologyFailure,
          residual: abs(displacement),
          tolerance: tolerance,
          message: "A face trim does not close in a non-periodic chart direction."
        )
      }
      return 0
    }
    let rounded = (displacement / period).rounded()
    let residual = abs(displacement - rounded * period)
    guard rounded >= Double(Int.min),
      rounded <= Double(Int.max),
      residual <= parameterTolerance
    else {
      throw KernelError(
        phase: .classification,
        code: .topologyFailure,
        residual: residual,
        tolerance: tolerance,
        message: "A face trim has a non-integral periodic winding."
      )
    }
    return Int(rounded)
  }

  private func loopParameters(
    _ loop: Loop,
    surface: Surface3D,
    model: BRepModel,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> [UV] {
    var polygon: [UV] = []
    var uSingularFlags: [Bool] = []
    let singularVValues = try SurfaceParameterTopology(
      surface: surface
    , using: &execution).uSingularVValues
    for coedge in loop.coedges {
      try consume(0, tolerance: tolerance, using: &execution)
      guard let edge = model.edges[coedge.edgeID] else {
        throw KernelError(
          phase: .topology,
          code: .missingReference,
          tolerance: tolerance,
          message: "Trimmed-face containment references a missing edge."
        )
      }
      if let parameterCurve = coedge.surfaceParameterCurve {
        try parameterCurve.validate(on: surface, tolerance: tolerance, remainingSourceDepth: min(16, self.remainingSourceDepth, execution.effectiveLimits.remainingSourceDepth), maximumSubdivisionDepth: min(self.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth), maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let authoredSamples = try parameterSamples(
          parameterCurve,
          tolerance: tolerance
        , using: &execution)
        try appendAuthoredParameterSamples(
          authoredSamples,
          to: &polygon,
          uSingularFlags: &uSingularFlags,
          singularVValues: singularVValues,
          on: surface,
          preservesAuthoredWinding: preservesAuthoredWinding(
            parameterCurve
          ),
          tolerance: tolerance
        , using: &execution)
        continue
      }
      let samples = try edgeSamples(
        edge,
        orientation: coedge.orientation,
        model: model,
        tolerance: tolerance
      , using: &execution)
      for sample in samples {
        try consume(0, tolerance: tolerance, using: &execution)
        let projection = try surface.parameterProjection(of: sample, tolerance: tolerance, using: &execution)
        let parameter = try unwrapped(
          UV(u: projection.u, v: projection.v),
          relativeTo: polygon.last,
          on: surface
        , using: &execution)
        let countBefore = polygon.count
        try append(
          parameter,
          to: &polygon,
          tolerance: tolerance.distance
        , using: &execution)
        if polygon.count > countBefore {
          try OriginalParameterQueryStorage.append(singularVValues.contains {
            abs(projection.v - $0) <= tolerance.distance
          }, to: &uSingularFlags, using: &execution)
        }
      }
    }
    // A vertex at a u-singular locus (cone apex, sphere pole) projects
    // to an arbitrary u; drawing its edge with that u cuts a diagonal
    // through the face interior, so the singular vertex inherits its
    // polygon neighbor's u instead.
    if uSingularFlags.contains(true), uSingularFlags.contains(false) {
      for index in polygon.indices where uSingularFlags[index] {
        var neighbor: Int? = nil
        var offset = 1
        while offset < polygon.count {
          let previous = (index - offset + polygon.count) % polygon.count
          if uSingularFlags[previous] == false {
            neighbor = previous
            break
          }
          let next = (index + offset) % polygon.count
          if uSingularFlags[next] == false {
            neighbor = next
            break
          }
          offset += 1
        }
        if let neighbor {
          polygon[index] = UV(
            u: polygon[neighbor].u,
            v: polygon[index].v
          )
        }
      }
    }
    if polygon.count > 1,
      let first = polygon.first,
      let last = polygon.last,
      hypot(last.u - first.u, last.v - first.v) <= tolerance.distance
    {
      polygon.removeLast()
    }
    return polygon
  }

  private func appendAuthoredParameterSamples(
    _ samples: [SurfaceParameter],
    to polygon: inout [UV],
    uSingularFlags: inout [Bool],
    singularVValues: [Double],
    on surface: Surface3D,
    preservesAuthoredWinding: Bool,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws {
    guard let first = samples.first else { return }
    let authoredFirst = UV(u: first.u, v: first.v)
    let alignedFirst = try unwrapped(
      authoredFirst,
      relativeTo: polygon.last,
      on: surface
    , using: &execution)
    let uOffset = alignedFirst.u - authoredFirst.u
    let vOffset = alignedFirst.v - authoredFirst.v
    for sample in samples {
      try consume(0, tolerance: tolerance, using: &execution)
      let authored = UV(u: sample.u, v: sample.v)
      let parameter: UV
      if preservesAuthoredWinding {
        // Explicit parameter curves may intentionally traverse more
        // than half a period. Translate their whole chart once so
        // winding and orientation remain unchanged.
        parameter = UV(
          u: authored.u + uOffset,
          v: authored.v + vOffset
        )
      } else {
        // Projection-backed curves return canonical chart values at
        // each evaluation, so their samples must be unwrapped
        // continuously along the loop.
        parameter = try unwrapped(
          authored,
          relativeTo: polygon.last,
          on: surface
        , using: &execution)
      }
      let countBefore = polygon.count
      try append(
        parameter,
        to: &polygon,
        tolerance: tolerance.distance
      , using: &execution)
      if polygon.count > countBefore {
        try OriginalParameterQueryStorage.append(singularVValues.contains {
          abs(parameter.v - $0) <= tolerance.distance
        }, to: &uSingularFlags, using: &execution)
      }
    }
  }

  private func preservesAuthoredWinding(
    _ curve: SurfaceParameterCurve
  ) -> Bool {
    switch curve {
    case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline, .originalBSplineContinuation:
      return true
    case .sphericalGreatCircle, .certifiedImplicit,
      .certifiedAnalyticImplicit, .certifiedAnalyticPair,
      .projectedAnalytic, .rigidImage:
      return false
    case .periodicTranslation(let base, _, _):
      return preservesAuthoredWinding(base)
    case .offsetSurfaceImage(let image):
      return preservesAuthoredWinding(image.source)
    case .originalImage(let image):
      return preservesAuthoredWinding(image.source.parameterCurve)
    case .originalAffineWord(let image):
      return preservesAuthoredWinding(image.source.parameterCurve)
    }
  }

  private func unwrapped(
    _ point: UV,
    relativeTo reference: UV?,
    on surface: Surface3D
  , using execution: inout OriginalQueryExecution) throws -> UV {
    guard let reference else { return point }
    return UV(
      u: try unwrapped(point.u, relativeTo: reference.u, domain: surface.uDomain, using: &execution),
      v: try unwrapped(point.v, relativeTo: reference.v, domain: surface.vDomain, using: &execution)
    )
  }

  private func edgeSamples(
    _ edge: Edge,
    orientation: Orientation,
    model: BRepModel,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> [Point3D] {
    guard let curve = model.geometry.curves[edge.curveID],
      let startVertex = model.vertices[edge.startVertexID],
      let endVertex = model.vertices[edge.endVertexID]
    else {
      throw KernelError(
        phase: .topology,
        code: .missingReference,
        tolerance: tolerance,
        message: "Trimmed-face containment references missing edge geometry."
      )
    }
    guard let trim = edge.trim else {
      try execution.retainKernelValues(count: 2, stride: MemoryLayout<Point3D>.stride)
      return orientation == .forward
        ? [startVertex.point, endVertex.point]
        : [endVertex.point, startVertex.point]
    }
    let startParameter =
      orientation == .forward
      ? trim.startParameter
      : trim.endParameter
    let endParameter =
      orientation == .forward
      ? trim.endParameter
      : trim.startParameter
    let validatedCurve = try ValidatedCurve3D(
      curve,
      tolerance: tolerance
    , using: &execution)
    let start = try validatedCurve.point(at: startParameter, using: &execution)
    let end = try validatedCurve.point(at: endParameter, using: &execution)
    try execution.retainKernelValues(count: 1, stride: MemoryLayout<Point3D>.stride)
    var result = [start]
    try appendEdgeSamples(
      curve: validatedCurve,
      lowerParameter: startParameter,
      lowerPoint: start,
      upperParameter: endParameter,
      upperPoint: end,
      depth: 0,
      points: &result,
      tolerance: tolerance
    , using: &execution)
    return result
  }

  private func appendEdgeSamples(
    curve: ValidatedCurve3D,
    lowerParameter: Double,
    lowerPoint: Point3D,
    upperParameter: Double,
    upperPoint: Point3D,
    depth: Int,
    points: inout [Point3D],
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws {
    try execution.visitGeometricCell(depth: depth)
    let midpointParameter = lowerParameter + (upperParameter - lowerParameter) * 0.5
    let midpoint = try curve.point(at: midpointParameter, using: &execution)
    let deviation = distance(midpoint, toSegmentFrom: lowerPoint, to: upperPoint)
    if deviation <= tolerance.distance {
      try OriginalParameterQueryStorage.append(upperPoint, to: &points, using: &execution)
      return
    }
    guard depth < 20 else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: deviation,
        tolerance: tolerance,
        message: "Trimmed-face boundary sampling exceeded its subdivision limit."
      )
    }
    try appendEdgeSamples(
      curve: curve,
      lowerParameter: lowerParameter,
      lowerPoint: lowerPoint,
      upperParameter: midpointParameter,
      upperPoint: midpoint,
      depth: depth + 1,
      points: &points,
      tolerance: tolerance
    , using: &execution)
    try appendEdgeSamples(
      curve: curve,
      lowerParameter: midpointParameter,
      lowerPoint: midpoint,
      upperParameter: upperParameter,
      upperPoint: upperPoint,
      depth: depth + 1,
      points: &points,
      tolerance: tolerance
    , using: &execution)
  }

  private func parameterSamples(
    _ curve: SurfaceParameterCurve,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> [SurfaceParameter] {
    return try SurfaceParameterCurveSampler(tolerance: tolerance).sample(curve, using: &execution)
  }

  private func unwrapped(
    _ value: Double,
    relativeTo reference: Double,
    domain: ParameterDomain
  , using execution: inout OriginalQueryExecution) throws -> Double {
    guard case .periodic(let period) = domain else { return value }
    var result = value
    while result - reference > period * 0.5 {
      try execution.consumeWork(1)
      let next = result - period
      guard next != result else { throw GeometryConversionError.resourceLimitExceeded("Periodic chart representative cannot advance in finite arithmetic.") }
      result = next
    }
    while result - reference < -period * 0.5 {
      try execution.consumeWork(1)
      let next = result + period
      guard next != result else { throw GeometryConversionError.resourceLimitExceeded("Periodic chart representative cannot advance in finite arithmetic.") }
      result = next
    }
    return result
  }

  private func periodicRepresentatives(
    of point: UV, on surface: Surface3D,
    using execution: inout OriginalQueryExecution
  ) throws -> [UV] {
    let uPeriod: Double?
    let vPeriod: Double?
    if case .periodic(let period) = surface.uDomain { uPeriod = period } else { uPeriod = nil }
    if case .periodic(let period) = surface.vDomain { vPeriod = period } else { vPeriod = nil }
    var result: [UV] = []
    try execution.retainKernelValues(count: (uPeriod == nil ? 1 : 3) * (vPeriod == nil ? 1 : 3),
      stride: MemoryLayout<UV>.stride)
    result.reserveCapacity((uPeriod == nil ? 1 : 3) * (vPeriod == nil ? 1 : 3))
    for uIndex in 0..<(uPeriod == nil ? 1 : 3) {
      let u = point.u + (uPeriod ?? 0) * (uIndex == 0 ? 0 : uIndex == 1 ? -1 : 1)
      for vIndex in 0..<(vPeriod == nil ? 1 : 3) {
        try execution.consumeWork(1)
        let v = point.v + (vPeriod ?? 0) * (vIndex == 0 ? 0 : vIndex == 1 ? -1 : 1)
        result.append(UV(u: u, v: v))
      }
    }
    return result
  }

  private func aligned(_ point: UV, to center: UV, on surface: Surface3D, using execution: inout OriginalQueryExecution) throws -> UV {
    return UV(
      u: try unwrapped(point.u, relativeTo: center.u, domain: surface.uDomain, using: &execution),
      v: try unwrapped(point.v, relativeTo: center.v, domain: surface.vDomain, using: &execution)
    )
  }

  private func distance(
    _ point: Point3D,
    toSegmentFrom start: Point3D,
    to end: Point3D
  ) -> Double {
    let segment = end - start
    let lengthSquared = segment.dot(segment)
    guard lengthSquared > Double.ulpOfOne else { return (point - start).length }
    let fraction = min(max((point - start).dot(segment) / lengthSquared, 0.0), 1.0)
    return (point - (start + segment * fraction)).length
  }

  private func append(_ point: UV, to polygon: inout [UV], tolerance: Double, using execution: inout OriginalQueryExecution) throws {
    guard polygon.last.map({ hypot($0.u - point.u, $0.v - point.v) <= tolerance }) != true else {
      return
    }
    try OriginalParameterQueryStorage.append(point, to: &polygon, using: &execution)
  }

  private typealias UV = FacePointContainmentPreparationCache.UV

  private struct LoopCertification {
    let predicate: CertifiedSurfaceParameterLoopPredicate?
    let uWinding: Int
    let vWinding: Int
    let constantULevel: Double?
    let constantVLevel: Double?
  }

  private final class Session: FacePointContainmentSession, FaceParameterContainmentSession {
    struct Payload: Sendable {
      let tester: DefaultFacePointContainmentTester
      let preparedFaces: [FaceID: FacePointContainmentPreparationCache.PreparedFace]
      let tolerance: ModelingTolerance
      let lifetime: PreparedBooleanQueryLifetime
    }
    let payload: Payload
    init(payload: Payload) { self.payload = payload }
    func containsParameter(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool? {
      var execution = try payload.lifetime.execution()
      return try contains(parameter, on: faceID, using: &execution)
    }
    func containsParameter(_ parameter: SurfaceParameter, on faceID: FaceID,
      using execution: inout OriginalQueryExecution) throws -> Bool? {
      try contains(parameter, on: faceID, using: &execution)
    }
    func contains(_ point: Point3D, on faceID: FaceID) throws -> Bool {
      var execution = try payload.lifetime.execution()
      return try contains(point, on: faceID, using: &execution)
    }
    func contains(_ point: Point3D, on faceID: FaceID,
      using execution: inout OriginalQueryExecution) throws -> Bool {
      do {
        return try payload.lifetime.withRead(using: &execution) { execution in
        try execution.consumeWork(1); try point.validate()
        guard let face = payload.preparedFaces[faceID] else {
          throw KernelError(phase: .classification, code: .missingReference, tolerance: payload.tolerance,
            message: "Face containment session does not own the requested face.")
        }
        let result = try payload.tester.contains(point, on: face, tolerance: payload.tolerance, using: &execution)
        try execution.checkpoint(); return result
        }
      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: payload.tolerance) }
    }
    func contains(_ parameter: SurfaceParameter, on faceID: FaceID) throws -> Bool {
      var execution = try payload.lifetime.execution()
      return try contains(parameter, on: faceID, using: &execution)
    }
    func contains(_ parameter: SurfaceParameter, on faceID: FaceID,
      using execution: inout OriginalQueryExecution) throws -> Bool {
      do {
        return try payload.lifetime.withRead(using: &execution) { execution in
        try execution.consumeWork(1); try parameter.validate()
        guard let face = payload.preparedFaces[faceID] else {
          throw KernelError(phase: .classification, code: .missingReference, tolerance: payload.tolerance,
            message: "Face containment session does not own the requested face.")
        }
        let result = try payload.tester.contains(parameter, on: face, tolerance: payload.tolerance, using: &execution)
        try execution.checkpoint(); return result
        }
      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: payload.tolerance) }
    }
  }
}

// This immutable preparation is issued only by the source/extent path in this
// file. Its finite box scopes search; retained loop predicates decide material.
extension FacePointContainmentPreparationCache {
  struct PreparedFace: Sendable {
    let surface: Surface3D
    let loops: [LoopRegion]
    let faceID: FaceID
    let surfaceID: SurfaceID
    let parameterBounds: SurfaceParameterBox?

    fileprivate init(surface: Surface3D, loops: [LoopRegion], faceID: FaceID,
      surfaceID: SurfaceID, parameterBounds: SurfaceParameterBox?) {
      self.surface = surface
      self.loops = loops
      self.faceID = faceID
      self.surfaceID = surfaceID
      self.parameterBounds = parameterBounds
    }
  }
}
