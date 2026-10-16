import HashTreeCollections
import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

/// Certifies divergence-theorem volume for shells containing trimmed parametric faces.
///
/// Polynomial Bezier spans use exact Bernstein coefficient integration,
/// axis-aligned planar straight-edge faces use an outward-rounded boundary
/// Green integral, arbitrary polynomial Bezier loops use an exact Bernstein
/// flux primitive, remaining rational rectangles use certified adaptive
/// quadrature, and analytic faces are composed through their certified
/// surface-flux integrator. Procedural surfaces first use an exact
/// chart-preserving canonical surface when one exists; remaining procedural
/// trims use a certified boundary-flux enclosure with second-derivative error
/// bounds. Unsupported trims never enter an approximate success path.
struct TrimmedParametricSurfaceVolumeEvaluator {
  struct VolumeBounds: Sendable, Hashable {
    let lower: Double
    let upper: Double

    var midpoint: Double {
      lower + (upper - lower) * 0.5
    }

    var errorRadius: Double {
      (upper - lower) * 0.5
    }
  }

  private let maximumCoefficientOperations: Int
  private let maximumRationalSubdivisionDepth: Int
  private let maximumRationalCellCount: Int
  private let maximumProceduralSubdivisionDepth: Int
  private let maximumProceduralCellCount: Int

  init(
    maximumCoefficientOperations: Int = 2_000_000,
    maximumRationalSubdivisionDepth: Int = 10,
    maximumRationalCellCount: Int = 1_000_000,
    maximumProceduralSubdivisionDepth: Int = 32,
    maximumProceduralCellCount: Int = 1_000_000
  ) {
    self.maximumCoefficientOperations = maximumCoefficientOperations
    self.maximumRationalSubdivisionDepth = maximumRationalSubdivisionDepth
    self.maximumRationalCellCount = maximumRationalCellCount
    self.maximumProceduralSubdivisionDepth = maximumProceduralSubdivisionDepth
    self.maximumProceduralCellCount = maximumProceduralCellCount
  }

  func volume(of shell: Shell, in model: BRepModel, tolerance: ModelingTolerance) throws -> Double {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try volume(of: shell, in: model, tolerance: tolerance, using: &execution)
  }

  func volumeBounds(of shell: Shell, in model: BRepModel, tolerance: ModelingTolerance) throws -> VolumeBounds {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try volumeBounds(of: shell, in: model, tolerance: tolerance, using: &execution)
  }

  func rationalLoopVolumeBounds(surface: BSplineSurface3D, parameterCurves: [SurfaceParameterCurve], role: LoopRole, reference: Point3D, requestedWidth: Double, tolerance: ModelingTolerance) throws -> VolumeBounds? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try rationalLoopVolumeBounds(surface: surface, parameterCurves: parameterCurves, role: role, reference: reference, requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
  }

  func polynomialLoopVolumeBounds(surface: BSplineSurface3D, parameterCurves: [SurfaceParameterCurve], role: LoopRole, reference: Point3D, requestedWidth: Double, tolerance: ModelingTolerance) throws -> VolumeBounds? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try polynomialLoopVolumeBounds(surface: surface, parameterCurves: parameterCurves, role: role, reference: reference, requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
  }

  func volume(
    of shell: Shell,
    in model: BRepModel,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
      try execution.consumeWork(1)
    let bounds = try volumeBounds(
      of: shell,
      in: model,
      tolerance: tolerance, using: &execution
    )
    let reference = try referencePoint(for: shell, in: model, using: &execution)
    let characteristicLength = try characteristicLength(
      of: shell,
      in: model,
      reference: reference,
      tolerance: tolerance, using: &execution
    )
    let requestedError = volumeTolerance(
      characteristicLength: characteristicLength,
      tolerance: tolerance
    )
    guard bounds.errorRadius <= requestedError else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: bounds.errorRadius,
        tolerance: tolerance,
        message: "Certified parametric surface-flux volume exceeded the requested enclosure width."
      )
    }
    return bounds.midpoint
  }

  func volumeBounds(
    of shell: Shell,
    in model: BRepModel,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> VolumeBounds {
      try execution.consumeWork(1)
    try tolerance.validate()
    let reference = try referencePoint(for: shell, in: model, using: &execution)
    let characteristicLength = try characteristicLength(
      of: shell,
      in: model,
      reference: reference,
      tolerance: tolerance, using: &execution
    )
    let requestedError = volumeTolerance(
      characteristicLength: characteristicLength,
      tolerance: tolerance
    )
    let faceCount = shell.faceIDs.count
    guard faceCount > 0 else {
      throw TopologyError.openShell(shell.id)
    }
    let totalCoedgeCount = try coedgeCount(of: shell, in: model, using: &execution)
    guard totalCoedgeCount > 0 else {
      throw TopologyError.openShell(shell.id)
    }
    var coefficientOperations = CoefficientOperationCount(limit: maximumCoefficientOperations)
    var total = OutwardInterval.exact(0.0)
    for faceID in shell.faceIDs {
      try execution.consumeWork(1)
      guard let face = model.faces[faceID],
        let surface = model.geometry.surfaces[face.surfaceID]
      else {
        throw TopologyError.missingReference(
          "Parametric volume references missing face geometry."
        )
      }
      var contribution: OutwardInterval
      switch surface {
      case .bSpline(let spline):
        guard
          let bSplineContribution = try bSplineFaceContribution(
            face: face,
            surface: spline,
            model: model,
            reference: reference,
            requestedFaceError: requestedError * 0.99 / Double(faceCount),
            requestedCurveWidth: requestedError * 1.98 / Double(totalCoedgeCount),
            coefficientOperations: &coefficientOperations,
            tolerance: tolerance, using: &execution
          )
        else {
          throw unhandledValidatedFace(
            surface: surface,
            tolerance: tolerance
          )
        }
        contribution = bSplineContribution
      case .procedural(let procedural):
        if let exactSurface = try procedural.exactChartPreservingSurface(
          tolerance: tolerance, using: &execution
        ) {
          switch exactSurface {
          case .bSpline(let spline):
            guard
              let exactContribution = try bSplineFaceContribution(
                face: face,
                surface: spline,
                model: model,
                reference: reference,
                requestedFaceError: requestedError * 0.99 / Double(faceCount),
                requestedCurveWidth: requestedError * 1.98 / Double(totalCoedgeCount),
                coefficientOperations: &coefficientOperations,
                tolerance: tolerance, using: &execution
              )
            else {
              throw unhandledValidatedFace(
                surface: surface,
                tolerance: tolerance
              )
            }
            contribution = exactContribution
          case .procedural:
            throw KernelError(
              phase: .topology,
              code: .topologyFailure,
              tolerance: tolerance,
              message: "An exact procedural representation must be canonical."
            )
          default:
            guard
              let exactContribution = try analyticFaceContribution(
                face: face,
                surface: exactSurface,
                model: model,
                reference: reference,
                requestedCurveWidth: requestedError * 1.98 / Double(totalCoedgeCount),
                tolerance: tolerance, using: &execution
              )
            else {
              throw unhandledValidatedFace(
                surface: surface,
                tolerance: tolerance
              )
            }
            contribution = exactContribution
          }
        } else if let proceduralContribution = try proceduralRectangularContribution(
          face: face,
          surface: surface,
          model: model,
          reference: reference,
          requestedError: requestedError * 0.99 / Double(faceCount),
          tolerance: tolerance, using: &execution
        ) {
          contribution = proceduralContribution
        } else if let proceduralContribution = try arbitraryProceduralContribution(
          face: face,
          surface: surface,
          model: model,
          reference: reference,
          requestedCurveWidth: requestedError * 1.98 / Double(totalCoedgeCount),
          tolerance: tolerance, using: &execution
        ) {
          contribution = proceduralContribution
        } else {
          throw unhandledValidatedFace(
            surface: surface,
            tolerance: tolerance
          )
        }
      default:
        guard
          let analyticContribution = try analyticFaceContribution(
            face: face,
            surface: surface,
            model: model,
            reference: reference,
            requestedCurveWidth: requestedError * 1.98 / Double(totalCoedgeCount),
            tolerance: tolerance, using: &execution
          )
        else {
          throw unhandledValidatedFace(
            surface: surface,
            tolerance: tolerance
          )
        }
        contribution = analyticContribution
      }
      if face.orientation == .reversed {
        contribution = -contribution
      }
      total = total + contribution
    }

    guard total.lower.isFinite, total.upper.isFinite else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Certified parametric surface-flux volume exceeded finite arithmetic."
      )
    }
    return VolumeBounds(lower: total.lower, upper: total.upper)
  }

  private func unhandledValidatedFace(
    surface: Surface3D,
    tolerance: ModelingTolerance
  ) -> KernelError {
    KernelError(
      phase: .topology,
      code: .topologyFailure,
      tolerance: tolerance,
      message: "A validated \(surfaceKind(surface)) face has no certified surface-flux strategy."
    )
  }

  private func surfaceKind(_ surface: Surface3D) -> String {
    switch surface {
    case .plane: "plane"
    case .cylinder: "cylinder"
    case .analytic: "analytic"
    case .bSpline: "B-spline"
    case .procedural(.offset): "offset"
    case .procedural(.ruled): "ruled"
    case .procedural(.rollingBall): "rolling-ball"
    case .procedural(.originalImage): "original-image"
    case .procedural(.originalRevolution): "original-revolution"
    case .procedural(.originalCoons): "original-Coons"
    case .procedural(.originalBoundaryCorrected): "original-boundary-corrected"
    case .procedural(.originalPlaneDerivative): "original-plane-derivative"
    case .procedural(.originalDrafted): "original-drafted"
    case .procedural(.originalAngularTransport): "original-angular-transport"
    case .procedural(.originalAffineWord): "original-affine-word"
    }
  }

  private func bSplineFaceContribution(
    face: Face,
    surface: BSplineSurface3D,
    model: BRepModel,
    reference: Point3D,
    requestedFaceError: Double,
    requestedCurveWidth: Double,
    coefficientOperations: inout CoefficientOperationCount,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    try surface.validate(tolerance: tolerance, using: &execution)
    let trim = try ExactRectangularPcurveDomainResolver().resolve(
      face: face,
      model: model,
      tolerance: tolerance, maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
        remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth), using: &execution
    )
    if let trim {
      if var patch = try PolynomialBezierPatch(
        surface: surface,
        tolerance: tolerance, using: &execution
      ) {
        patch = try patch.trimmed(
          uLower: trim.uLower,
          uUpper: trim.uUpper,
          vLower: trim.vLower,
          vUpper: trim.vUpper,
          sourceUDomain: surface.uDomain,
          sourceVDomain: surface.vDomain,
          tolerance: tolerance, using: &execution
        )
        return try patch.fluxIntegral(
          reference: reference,
          coefficientOperations: &coefficientOperations,
          tolerance: tolerance, using: &execution
        )
      }
      if let piecewise = try piecewisePolynomialRectangleContribution(
        surface: surface,
        trim: trim,
        reference: reference,
        coefficientOperations: &coefficientOperations,
        tolerance: tolerance, using: &execution
      ) {
        return piecewise
      }
      if let planarContribution = try axisAlignedPlanarContribution(
        face: face,
        surface: surface,
        model: model,
        reference: reference,
        tolerance: tolerance, using: &execution
      ) {
        return planarContribution
      }
      guard
        let rationalBounds = try CertifiedRationalBezierSurfaceFluxIntegrator(
          maximumSubdivisionDepth: maximumRationalSubdivisionDepth,
          maximumCellCount: maximumRationalCellCount
        ).integrate(
          surface: surface,
          uLower: trim.uLower,
          uUpper: trim.uUpper,
          vLower: trim.vLower,
          vUpper: trim.vUpper,
          reference: reference,
          requestedError: requestedFaceError,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      return OutwardInterval(
        lower: rationalBounds.lower,
        upper: rationalBounds.upper
      )
    }
    if let patch = try PolynomialBezierPatch(
      surface: surface,
      tolerance: tolerance, using: &execution
    ),
      let polynomialContribution = try arbitraryPolynomialContribution(
        face: face,
        model: model,
        primitive: try patch.fluxPrimitive(
          reference: reference,
          uDomain: surface.uDomain,
          vDomain: surface.vDomain,
          coefficientOperations: &coefficientOperations,
          tolerance: tolerance, using: &execution
        ),
        requestedCurveWidth: requestedCurveWidth,
        tolerance: tolerance, using: &execution
      )
    {
      return polynomialContribution
    }
    if let planarContribution = try axisAlignedPlanarContribution(
      face: face,
      surface: surface,
      model: model,
      reference: reference,
      tolerance: tolerance, using: &execution
    ) {
      return planarContribution
    }
    guard
      let field = try CertifiedRationalBezierSurfaceFluxIntegrator(
        maximumSubdivisionDepth: maximumRationalSubdivisionDepth,
        maximumCellCount: maximumRationalCellCount
      ).preparedField(
        surface: surface,
        reference: reference,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    return try arbitraryRationalContribution(
      face: face,
      surface: surface,
      model: model,
      field: field,
      requestedCurveWidth: requestedCurveWidth,
      coefficientOperations: &coefficientOperations,
      tolerance: tolerance, using: &execution
    )
  }

  /// The flux of a non-rational B-spline surface of several spans over a rectangular trim: each
  /// span's certified Bezier patch cut to its share of the rectangle and integrated exactly, the
  /// shares summed. A share narrower than the parameter resolution but not empty (a trim side a
  /// hair from a knot) cannot be cut exactly, so the face is left to the general path; a rational
  /// surface is left to it too. Nil when this path does not apply.
  private func piecewisePolynomialRectangleContribution(
    surface: BSplineSurface3D,
    trim: ExactRectangularPcurveDomain,
    reference: Point3D,
    coefficientOperations: inout CoefficientOperationCount,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    guard !surface.isRational,
      let patches = try CertifiedBSplineSurfaceBezierExtractor().patches(
        surface: surface,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    var total = OutwardInterval.exact(0.0)
    for piece in patches {
      try execution.consumeWork(1)
      let uLower = max(trim.uLower, piece.uLower), uUpper = min(trim.uUpper, piece.uUpper)
      let vLower = max(trim.vLower, piece.vLower), vUpper = min(trim.vUpper, piece.vUpper)
      guard uUpper > uLower, vUpper > vLower else { continue }
      let scale = max(1.0, abs(piece.uLower), abs(piece.uUpper), abs(piece.vLower), abs(piece.vUpper))
      let resolution = max(tolerance.relative * scale, Double.ulpOfOne * scale * 256.0)
      guard uUpper - uLower > resolution, vUpper - vLower > resolution,
        let patch = try PolynomialBezierPatch(certified: piece, using: &execution)
      else {
        return nil
      }
      let share = try patch.trimmed(
        uLower: uLower,
        uUpper: uUpper,
        vLower: vLower,
        vUpper: vUpper,
        sourceUDomain: .closed(piece.uLower, piece.uUpper),
        sourceVDomain: .closed(piece.vLower, piece.vUpper),
        tolerance: tolerance, using: &execution
      )
      total = total + (try share.fluxIntegral(reference: reference, coefficientOperations: &coefficientOperations, tolerance: tolerance, using: &execution))
    }
    return total
  }

  private func arbitraryProceduralContribution(
    face: Face,
    surface: Surface3D,
    model: BRepModel,
    reference: Point3D,
    requestedCurveWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    var total = OutwardInterval.exact(0.0)
    for loopID in face.loops {
      try execution.consumeWork(1)
      guard let loop = model.loops[loopID],
        loop.coedges.isEmpty == false
      else {
        throw TopologyError.missingReference(
          "Procedural volume references a missing or empty loop."
        )
      }
      let curves = try (try OriginalParameterQueryStorage.map(loop.coedges, using: &execution) { coedge, execution in
        guard let curve = coedge.surfaceParameterCurve else {
          throw TopologyError.invalidTrim(coedge.edgeID)
        }
        return curve
      })
      guard
        let contribution = try proceduralLoopContribution(
          parameterCurves: curves,
          role: loop.role,
          surface: surface,
          reference: reference,
          requestedCurveWidth: requestedCurveWidth,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      total = total + contribution
    }
    return total
  }

  private func proceduralLoopContribution(
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    surface: Surface3D,
    reference: Point3D,
    requestedCurveWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    guard let firstCurve = parameterCurves.first,
      requestedCurveWidth.isFinite,
      requestedCurveWidth > 0.0
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedCurveWidth,
        tolerance: tolerance,
        message: "Procedural volume requires pcurves and a positive curve enclosure width."
      )
    }
    let uBase = try firstCurve.startParameter(tolerance: tolerance, using: &execution).u
    let integrator = CertifiedAnalyticPcurveFluxIntegrator()
    var rawFlux = TrimmedAnalyticSurfaceVolumeEvaluator.Interval.exact(0.0)
    var areaBounds = SurfaceParameterAreaBounds.zero
    for curve in parameterCurves {
      try execution.consumeWork(1)
      guard
        let contribution = try integrator.proceduralSurfaceBounds(
          for: curve,
          surface: surface,
          reference: reference,
          uBase: uBase,
          requestedWidth: requestedCurveWidth,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      rawFlux = rawFlux + contribution
      areaBounds = areaBounds.adding(
        try SurfaceParameterCurveAreaIntegrator().bounds(
          for: curve,
          uShift: 0.0,
          requestedWidth: max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
          ),
          tolerance: tolerance, using: &execution
        )
      )
    }
    let traversalNormalized: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
    if areaBounds.lower > 0.0 {
      traversalNormalized = rawFlux
    } else if areaBounds.upper < 0.0 {
      traversalNormalized = -rawFlux
    } else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: areaBounds.minimumAbsoluteValue,
        tolerance: tolerance,
        message: "Procedural volume could not certify loop orientation."
      )
    }
    let roleNormalized =
      role == .outer
      ? traversalNormalized
      : -traversalNormalized
    return OutwardInterval(
      lower: roleNormalized.lower,
      upper: roleNormalized.upper
    )
  }

  private func proceduralRectangularContribution(
    face: Face,
    surface: Surface3D,
    model: BRepModel,
    reference: Point3D,
    requestedError: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    guard
      let trim = try ExactRectangularPcurveDomainResolver().resolve(
        face: face,
        model: model,
        tolerance: tolerance, maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
        remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth), using: &execution
      )
    else {
      return nil
    }
    guard requestedError.isFinite,
      requestedError > 0.0,
      maximumProceduralSubdivisionDepth >= 0,
      maximumProceduralCellCount > 0
    else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: requestedError,
        tolerance: tolerance,
        message: "Certified procedural volume requires a positive error and subdivision budget."
      )
    }
    try execution.retainStorage(bytes: MemoryLayout<ProceduralFluxWorkItem>.stride)
    var pending = [
      ProceduralFluxWorkItem(
        cell: ProceduralFluxCell(
          uLower: trim.uLower,
          uUpper: trim.uUpper,
          vLower: trim.vLower,
          vUpper: trim.vUpper
        ),
        errorBudget: requestedError,
        depth: 0
      )
    ]
    var accepted: [OutwardInterval] = []
    var leafCount = 1
    let fluxEncloser = try SurfaceFluxDifferentialEncloser(
      surface: surface,
      tolerance: tolerance, using: &execution
    )
    while let item = pending.popLast() {
      try execution.visitGeometricCell(depth: item.depth)
      let contribution = try proceduralFluxContribution(
        cell: item.cell,
        surface: surface,
        encloser: fluxEncloser,
        reference: reference,
        tolerance: tolerance, using: &execution
      )
      let truncationError = (contribution.uErrorUpper + contribution.vErrorUpper).nextUp
      if truncationError <= item.errorBudget {
        try OriginalParameterQueryStorage.append(contribution.interval, to: &accepted, using: &execution)
        continue
      }
      guard item.depth < maximumProceduralSubdivisionDepth,
        leafCount < maximumProceduralCellCount
      else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: contribution.interval.errorRadius,
          tolerance: tolerance,
          message:
            "Certified procedural surface-flux volume exhausted its adaptive subdivision budget."
        )
      }
      let splitAlongU: Bool
      if contribution.uErrorUpper == contribution.vErrorUpper {
        splitAlongU = item.cell.uWidth >= item.cell.vWidth
      } else {
        splitAlongU = contribution.uErrorUpper > contribution.vErrorUpper
      }
      let children = item.cell.split(alongU: splitAlongU)
      let childBudget = (item.errorBudget * 0.5).nextDown
      try OriginalParameterQueryStorage.append(
        ProceduralFluxWorkItem(
          cell: children.second,
          errorBudget: childBudget,
          depth: item.depth + 1
        ), to: &pending, using: &execution)
      try OriginalParameterQueryStorage.append(
        ProceduralFluxWorkItem(
          cell: children.first,
          errorBudget: childBudget,
          depth: item.depth + 1
        ), to: &pending, using: &execution)
      let nextLeaves = leafCount.addingReportingOverflow(1)
      guard !nextLeaves.overflow else { throw ExactScalarFailure.countOverflow }
      leafCount = nextLeaves.partialValue
    }
    let total = try OriginalParameterQueryStorage.reduce(accepted, initial: OutwardInterval.exact(0.0), using: &execution) { total, value, execution in total + value }
    return total
  }

  private func proceduralFluxContribution(
    cell: ProceduralFluxCell,
    surface: Surface3D,
    encloser: SurfaceFluxDifferentialEncloser,
    reference: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ProceduralFluxContribution {
      try execution.consumeWork(1)
    let parameterBox = try cell.parameterBox()
    let differential = try encloser.enclosure(
      over: parameterBox,
      relativeTo: reference,
      tolerance: tolerance, using: &execution
    )
    let center = try encloser.enclosure(
      over: cell.midpointBox(
        tolerance: tolerance,
        relativeWidthMultiplier: midpointWidthMultiplier(for: surface)
      ),
      relativeTo: reference,
      tolerance: tolerance, using: &execution
    )
    let uWidth =
      OutwardInterval.exact(cell.uUpper)
      - OutwardInterval.exact(cell.uLower)
    let vWidth =
      OutwardInterval.exact(cell.vUpper)
      - OutwardInterval.exact(cell.vLower)
    let area = uWidth * vWidth
    let centerValue = OutwardInterval(
      lower: center.value.lower,
      upper: center.value.upper
    )
    let secondU = OutwardInterval.exact(
      max(
        abs(differential.secondDerivativeUU.lower),
        abs(differential.secondDerivativeUU.upper)
      ).nextUp
    )
    let secondV = OutwardInterval.exact(
      max(
        abs(differential.secondDerivativeVV.lower),
        abs(differential.secondDerivativeVV.upper)
      ).nextUp
    )
    let uError =
      area * secondU * uWidth * uWidth
      / OutwardInterval.exact(24.0)
    let vError =
      area * secondV * vWidth * vWidth
      / OutwardInterval.exact(24.0)
    let uErrorUpper = max(abs(uError.lower), abs(uError.upper)).nextUp
    let vErrorUpper = max(abs(vError.lower), abs(vError.upper)).nextUp
    let errorUpper = (uErrorUpper + vErrorUpper).nextUp
    return ProceduralFluxContribution(
      interval: centerValue * area
        + OutwardInterval(
          lower: (-errorUpper).nextDown,
          upper: errorUpper.nextUp
        ),
      uErrorUpper: uErrorUpper,
      vErrorUpper: vErrorUpper
    )
  }

  private func midpointWidthMultiplier(for surface: Surface3D) -> Double {
    switch surface {
    case .procedural(.ruled): 16.0
    default: 1_024.0
    }
  }

  private func analyticFaceContribution(
    face: Face,
    surface: Surface3D,
    model: BRepModel,
    reference: Point3D,
    requestedCurveWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    var total = OutwardInterval.exact(0.0)
    let evaluator = TrimmedAnalyticSurfaceVolumeEvaluator()
    for loopID in face.loops {
      try execution.consumeWork(1)
      guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
        throw TopologyError.missingReference(
          "Mixed parametric volume references a missing or empty analytic face loop."
        )
      }
      var parameterCurves: [SurfaceParameterCurve] = []
      try OriginalParameterQueryStorage.reserve(loop.coedges.count, in: &parameterCurves, using: &execution)
      for coedge in loop.coedges {
        try execution.consumeWork(1)
        guard let parameterCurve = coedge.surfaceParameterCurve else {
          throw TopologyError.invalidTrim(coedge.edgeID)
        }
        try OriginalParameterQueryStorage.append(parameterCurve, to: &parameterCurves, using: &execution)
      }
      guard
        let bounds = try evaluator.analyticLoopVolumeBounds(
          surface: surface,
          parameterCurves: parameterCurves,
          role: loop.role,
          reference: reference,
          requestedWidth: requestedCurveWidth,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      total =
        total
        + OutwardInterval(
          lower: bounds.lower,
          upper: bounds.upper
        )
    }
    return total
  }

  func rationalLoopVolumeBounds(
    surface: BSplineSurface3D,
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    reference: Point3D,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> VolumeBounds? {
      try execution.consumeWork(1)
    try tolerance.validate()
    guard !parameterCurves.isEmpty,
      requestedWidth.isFinite,
      requestedWidth > 0.0
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedWidth,
        tolerance: tolerance,
        message: "Rational B-spline loop volume requires pcurves and a positive enclosure width."
      )
    }
    let integrator = CertifiedRationalBezierSurfaceFluxIntegrator(
      maximumSubdivisionDepth: maximumRationalSubdivisionDepth,
      maximumCellCount: maximumRationalCellCount
    )
    if let plane = try AxisAlignedPlane(
      surface: surface,
      tolerance: tolerance, using: &execution
    ) {
      if plane.coordinate == plane.coordinate(of: reference) {
        return VolumeBounds(lower: 0.0, upper: 0.0)
      }
      guard
        let planarField = try integrator.preparedField(
          surface: surface,
          reference: reference,
          includeFluxNumerator: false,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      if let planarContribution = try rationalPlanarLoopContribution(
        parameterCurves: parameterCurves,
        role: role,
        plane: plane,
        field: planarField,
        reference: reference,
        requestedCurveWidth: requestedWidth / Double(parameterCurves.count),
        tolerance: tolerance, using: &execution
      ) {
        return VolumeBounds(
          lower: planarContribution.lower,
          upper: planarContribution.upper
        )
      }
    }
    guard
      let field = try integrator.preparedField(
        surface: surface,
        reference: reference,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    guard case .closed(let uBase, _) = surface.uDomain else {
      throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
        message: "Original loop flux requires a bounded U chart.")
    }
    var coefficientOperations = CoefficientOperationCount(limit: maximumCoefficientOperations)
    let allImplicit = (try OriginalParameterQueryStorage.allSatisfy(parameterCurves, using: &execution) { item, execution in if case .certifiedImplicit = item { return true }; return false })
    let coefficientOperationLimit = coefficientOperations.limit
    let primitive = allImplicit ? nil : try field.preparedPolynomialGreenPrimitive(uBase: uBase,
      coefficientOperations: &coefficientOperations.consumed,
      maximumCoefficientOperations: coefficientOperationLimit, using: &execution)
    guard
      let contribution = try rationalLoopContribution(
        parameterCurves: parameterCurves,
        role: role,
        surface: surface,
        field: field,
        requestedCurveWidth: requestedWidth / Double(parameterCurves.count),
        polynomialPrimitive: primitive,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    return VolumeBounds(lower: contribution.lower, upper: contribution.upper)
  }

  private func rationalPlanarLoopContribution(
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    plane: AxisAlignedPlane,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    reference: Point3D,
    requestedCurveWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    var projectedArea = TrimmedAnalyticSurfaceVolumeEvaluator.Interval.exact(0.0)
    var parameterArea = SurfaceParameterAreaBounds.zero
    let integrator = CertifiedAnalyticPcurveFluxIntegrator()
    for curve in parameterCurves {
      try execution.consumeWork(1)
      guard
        let curveArea = try integrator.rationalPlanarAreaBounds(
          for: curve,
          field: field,
          projection: plane.projection,
          requestedWidth: requestedCurveWidth,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      projectedArea = projectedArea + curveArea
      parameterArea = parameterArea.adding(
        try SurfaceParameterCurveAreaIntegrator().bounds(
          for: curve,
          uShift: 0.0,
          requestedWidth: max(
            tolerance.relative,
            Double.ulpOfOne * 256.0
          ),
          tolerance: tolerance, using: &execution
        )
      )
    }
    let traversalNormalized: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
    if parameterArea.lower > 0.0 {
      traversalNormalized = projectedArea
    } else if parameterArea.upper < 0.0 {
      traversalNormalized = -projectedArea
    } else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: parameterArea.minimumAbsoluteValue,
        tolerance: tolerance,
        message: "Certified rational planar area could not prove loop orientation."
      )
    }
    let roleNormalized =
      role == .outer
      ? traversalNormalized
      : -traversalNormalized
    let offset =
      OutwardInterval.exact(plane.coordinate)
      - OutwardInterval.exact(plane.coordinate(of: reference))
    return offset
      * OutwardInterval(
        lower: roleNormalized.lower,
        upper: roleNormalized.upper
      ) / OutwardInterval.exact(3.0)
  }

  func polynomialLoopVolumeBounds(
    surface: BSplineSurface3D,
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    reference: Point3D,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> VolumeBounds? {
      try execution.consumeWork(1)
    try tolerance.validate()
    guard !parameterCurves.isEmpty,
      requestedWidth.isFinite,
      requestedWidth > 0.0
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedWidth,
        tolerance: tolerance,
        message: "Polynomial B-spline loop volume requires pcurves and a positive enclosure width."
      )
    }
    guard
      let patch = try PolynomialBezierPatch(
        surface: surface,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    var coefficientOperations = CoefficientOperationCount(limit: maximumCoefficientOperations)
    let primitive = try patch.fluxPrimitive(
      reference: reference,
      uDomain: surface.uDomain,
      vDomain: surface.vDomain,
      coefficientOperations: &coefficientOperations,
      tolerance: tolerance, using: &execution
    )
    guard
      let contribution = try polynomialLoopContribution(
        parameterCurves: parameterCurves,
        role: role,
        primitive: primitive,
        requestedCurveWidth: requestedWidth / Double(parameterCurves.count),
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    return VolumeBounds(lower: contribution.lower, upper: contribution.upper)
  }

  private func arbitraryPolynomialContribution(
    face: Face,
    model: BRepModel,
    primitive: CertifiedPolynomialSurfaceFluxPrimitive,
    requestedCurveWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    var total = OutwardInterval.exact(0.0)
    for loopID in face.loops {
      try execution.consumeWork(1)
      guard let loop = model.loops[loopID],
        !loop.coedges.isEmpty
      else {
        throw TopologyError.missingReference(
          "Polynomial B-spline volume references a missing or empty loop."
        )
      }
      var curves: [SurfaceParameterCurve] = []
      try OriginalParameterQueryStorage.reserve(loop.coedges.count, in: &curves, using: &execution)
      for coedge in loop.coedges {
        try execution.consumeWork(1)
        guard let curve = coedge.surfaceParameterCurve else {
          throw TopologyError.invalidTrim(coedge.edgeID)
        }
        try OriginalParameterQueryStorage.append(curve, to: &curves, using: &execution)
      }
      guard
        let contribution = try polynomialLoopContribution(
          parameterCurves: curves,
          role: loop.role,
          primitive: primitive,
          requestedCurveWidth: requestedCurveWidth,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      total = total + contribution
    }
    return total
  }

  private func arbitraryRationalContribution(
    face: Face,
    surface: BSplineSurface3D,
    model: BRepModel,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    requestedCurveWidth: Double,
    coefficientOperations: inout CoefficientOperationCount,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    guard case .closed(let uBase, _) = surface.uDomain else {
      throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
        message: "Original polynomial flux requires a bounded U chart.")
    }
    let allImplicit = try OriginalParameterQueryStorage.allSatisfy(face.loops, using: &execution) { loopID, execution in
      guard let loop = model.loops[loopID] else { return false }
      return try OriginalParameterQueryStorage.allSatisfy(loop.coedges, using: &execution) { coedge, execution in
        if case .certifiedImplicit? = coedge.surfaceParameterCurve { return true }
        return false
      }
    }
    let coefficientOperationLimit = coefficientOperations.limit
    let primitive = allImplicit ? nil : try field.preparedPolynomialGreenPrimitive(uBase: uBase,
      coefficientOperations: &coefficientOperations.consumed,
      maximumCoefficientOperations: coefficientOperationLimit, using: &execution)
    var total = OutwardInterval.exact(0.0)
    for loopID in face.loops {
      try execution.consumeWork(1)
      guard let loop = model.loops[loopID],
        !loop.coedges.isEmpty
      else {
        throw TopologyError.missingReference(
          "Rational B-spline volume references a missing or empty loop."
        )
      }
      var curves: [SurfaceParameterCurve] = []
      try OriginalParameterQueryStorage.reserve(loop.coedges.count, in: &curves, using: &execution)
      for coedge in loop.coedges {
        try execution.consumeWork(1)
        guard let curve = coedge.surfaceParameterCurve else {
          throw TopologyError.invalidTrim(coedge.edgeID)
        }
        try OriginalParameterQueryStorage.append(curve, to: &curves, using: &execution)
      }
      guard
        let contribution = try rationalLoopContribution(
          parameterCurves: curves,
          role: loop.role,
          surface: surface,
          field: field,
          requestedCurveWidth: requestedCurveWidth,
          polynomialPrimitive: primitive,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      total = total + contribution
    }
    return total
  }

  private func rationalLoopContribution(
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    surface: BSplineSurface3D,
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    requestedCurveWidth: Double,
    polynomialPrimitive: CertifiedPiecewisePolynomialSurfaceFluxPrimitive? = nil,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    guard case .closed(let uBase, _) = surface.uDomain,
      !parameterCurves.isEmpty,
      requestedCurveWidth.isFinite,
      requestedCurveWidth > 0.0
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedCurveWidth,
        tolerance: tolerance,
        message: "Rational B-spline volume requires a bounded surface and positive curve enclosure."
      )
    }
    let curveIntegrator = CertifiedAnalyticPcurveFluxIntegrator()
    var rawFlux = TrimmedAnalyticSurfaceVolumeEvaluator.Interval.exact(0.0)
    var areaBounds = SurfaceParameterAreaBounds.zero
    for curve in parameterCurves {
      try execution.consumeWork(1)
      let contribution: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
      if let primitive = polynomialPrimitive {
        // Explicit curves use prefixes; native implicit curves keep their existing owner.
        contribution = try curveIntegrator.piecewisePolynomialBounds(for: curve, primitive: primitive,
          requestedWidth: requestedCurveWidth, tolerance: tolerance)
      } else {
        guard let certified = try curveIntegrator.rationalSurfaceBounds(
          for: curve,
          field: field,
          uBase: uBase,
          requestedWidth: requestedCurveWidth,
          tolerance: tolerance, using: &execution
        )
        else { return nil }
        contribution = certified
      }
      rawFlux = rawFlux + contribution
      areaBounds = areaBounds.adding(
        try SurfaceParameterCurveAreaIntegrator().bounds(
          for: curve,
          uShift: 0.0,
          requestedWidth: max(tolerance.relative, Double.ulpOfOne * 256.0),
          tolerance: tolerance, using: &execution
        )
      )
    }
    let traversalNormalized: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
    if areaBounds.lower > 0.0 {
      traversalNormalized = rawFlux
    } else if areaBounds.upper < 0.0 {
      traversalNormalized = -rawFlux
    } else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: areaBounds.minimumAbsoluteValue,
        tolerance: tolerance,
        message: "Rational B-spline volume could not certify loop orientation."
      )
    }
    let roleNormalized =
      role == .outer
      ? traversalNormalized
      : -traversalNormalized
    return OutwardInterval(
      lower: roleNormalized.lower,
      upper: roleNormalized.upper
    )
  }

  private func polynomialLoopContribution(
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    primitive: CertifiedPolynomialSurfaceFluxPrimitive,
    requestedCurveWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    guard !parameterCurves.isEmpty,
      requestedCurveWidth.isFinite,
      requestedCurveWidth > 0.0
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedCurveWidth,
        tolerance: tolerance,
        message: "Polynomial B-spline volume requires a finite positive per-curve enclosure."
      )
    }
    let integrator = CertifiedAnalyticPcurveFluxIntegrator()
    var rawFlux = TrimmedAnalyticSurfaceVolumeEvaluator.Interval.exact(0.0)
    var areaBounds = SurfaceParameterAreaBounds.zero
    for curve in parameterCurves {
      try execution.consumeWork(1)
      guard
        let contribution = try integrator.polynomialBounds(
          for: curve,
          primitive: primitive,
          requestedWidth: requestedCurveWidth,
          tolerance: tolerance
        )
      else {
        return nil
      }
      rawFlux = rawFlux + contribution
      areaBounds = areaBounds.adding(
        try SurfaceParameterCurveAreaIntegrator().bounds(
          for: curve,
          uShift: 0.0,
          requestedWidth: max(tolerance.relative, Double.ulpOfOne * 256.0),
          tolerance: tolerance, using: &execution
        )
      )
    }
    let traversalNormalized: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
    if areaBounds.lower > 0.0 {
      traversalNormalized = rawFlux
    } else if areaBounds.upper < 0.0 {
      traversalNormalized = -rawFlux
    } else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: areaBounds.minimumAbsoluteValue,
        tolerance: tolerance,
        message: "Polynomial B-spline volume could not certify loop orientation."
      )
    }
    let roleNormalized =
      role == .outer
      ? traversalNormalized
      : -traversalNormalized
    return OutwardInterval(
      lower: roleNormalized.lower,
      upper: roleNormalized.upper
    )
  }

  private func axisAlignedPlanarContribution(
    face: Face,
    surface: BSplineSurface3D,
    model: BRepModel,
    reference: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OutwardInterval? {
      try execution.consumeWork(1)
    guard
      let plane = try AxisAlignedPlane(
        surface: surface,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    if plane.coordinate == plane.coordinate(of: reference) {
      return .exact(0.0)
    }
    var orientedArea = OutwardInterval.exact(0.0)
    for loopID in face.loops {
      try execution.consumeWork(1)
      guard let loop = model.loops[loopID],
        !loop.coedges.isEmpty
      else {
        throw TopologyError.missingReference(
          "Axis-aligned planar volume references a missing or empty loop."
        )
      }
      var points: [Point3D] = []
      try OriginalParameterQueryStorage.reserve(loop.coedges.count, in: &points, using: &execution)
      for coedge in loop.coedges {
        try execution.consumeWork(1)
        guard let edge = model.edges[coedge.edgeID],
          let curve = model.geometry.curves[edge.curveID],
          let start = model.vertices[
            coedge.orientation == .forward
              ? edge.startVertexID
              : edge.endVertexID
          ]?.point,
          let end = model.vertices[
            coedge.orientation == .forward
              ? edge.endVertexID
              : edge.startVertexID
          ]?.point
        else {
          throw TopologyError.missingReference(
            "Axis-aligned planar volume references missing edge geometry."
          )
        }
        guard
          try curveIsCertifiedStraight(
            curve,
            start: start,
            end: end, using: &execution
          ), plane.coordinate(of: start) == plane.coordinate,
          plane.coordinate(of: end) == plane.coordinate
        else {
          return nil
        }
        try OriginalParameterQueryStorage.append(start, to: &points, using: &execution)
      }
      var twiceArea = OutwardInterval.exact(0.0)
      for index in points.indices {
        try execution.consumeWork(1)
        let current = plane.projected(points[index])
        let next = plane.projected(points[(index + 1) % points.count])
        twiceArea =
          twiceArea
          + OutwardInterval.exact(current.first)
          * OutwardInterval.exact(next.second)
          - OutwardInterval.exact(next.first)
          * OutwardInterval.exact(current.second)
      }
      let signedArea = twiceArea / OutwardInterval.exact(2.0)
      let absoluteArea: OutwardInterval
      if signedArea.lower > 0.0 {
        absoluteArea = signedArea
      } else if signedArea.upper < 0.0 {
        absoluteArea = -signedArea
      } else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          residual: min(abs(signedArea.lower), abs(signedArea.upper)),
          tolerance: tolerance,
          message: "Axis-aligned planar volume could not certify loop orientation."
        )
      }
      orientedArea =
        orientedArea
        + (loop.role == .outer ? absoluteArea : -absoluteArea)
    }
    let offset =
      OutwardInterval.exact(plane.coordinate)
      - OutwardInterval.exact(plane.coordinate(of: reference))
    let orientation = OutwardInterval.exact(plane.normalSign)
    return offset * orientation * orientedArea / OutwardInterval.exact(3.0)
  }

  private func curveIsCertifiedStraight(
    _ curve: Curve3D,
    start: Point3D,
    end: Point3D, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
      try execution.consumeWork(1)
    switch curve {
    case .line, .analytic(.line):
      return true
    case .bSpline(let spline):
      try execution.retainStorage(bytes: 6 * MemoryLayout<CoordinateAxis>.stride)
      let changingAxes = (try OriginalParameterQueryStorage.filter(CoordinateAxis.allCases, using: &execution) { item, execution in
        item.coordinate(of: start) != item.coordinate(of: end)
      })
      guard changingAxes.count == 1 else {
        return false
      }
      let fixedAxes = (try OriginalParameterQueryStorage.filter(CoordinateAxis.allCases, using: &execution) { item, execution in
        item != changingAxes[0]
      })
      return (try OriginalParameterQueryStorage.allSatisfy(fixedAxes, using: &execution) { axis, execution in
        let coordinate = axis.coordinate(of: start)
        return try axis.coordinate(of: end) == coordinate
          && (try OriginalParameterQueryStorage.allSatisfy(spline.controlPoints, using: &execution) { item, execution in
            axis.coordinate(of: item) == coordinate
          })
      })
    case .rigidImage(let image):
      return try curveIsCertifiedStraight(
        image.source,
        start: image.transform.inverted().applying(to: start),
        end: image.transform.inverted().applying(to: end), using: &execution
      )
    case .parameterImage(let image):
      return try curveIsCertifiedStraight(image.source, start: start, end: end, using: &execution)
    case .affineImage, .originalAffineWord:
      return curve.hasExactLinearParameterization
    case .circle, .analytic, .implicit, .surfaceLift,
      .certifiedIntersection, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
      return false
    }
  }

  private enum CoordinateAxis: CaseIterable {
    case x
    case y
    case z

    func coordinate(of point: Point3D) -> Double {
      switch self {
      case .x: point.x
      case .y: point.y
      case .z: point.z
      }
    }
  }

  private struct AxisAlignedPlane {
    let axis: CoordinateAxis
    let coordinate: Double
    let normalSign: Double

    init?(
      surface: BSplineSurface3D,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
      try execution.consumeWork(1)
      guard let bottomLeft = surface.controlPoints.first?.first,
        let bottomRight = surface.controlPoints.first?.last,
        let topLeft = surface.controlPoints.last?.first
      else {
        return nil
      }
      try execution.retainStorage(bytes: 3 * MemoryLayout<CoordinateAxis>.stride)
      for candidate in CoordinateAxis.allCases {
        try execution.consumeWork(1)
        let value = candidate.coordinate(of: bottomLeft)
        guard
          (try OriginalParameterQueryStorage.allSatisfy(surface.controlPoints, using: &execution) { row, execution in
            (try OriginalParameterQueryStorage.allSatisfy(row, using: &execution) { item, execution in candidate.coordinate(of: item) == value })
          })
        else {
          continue
        }
        let minimumArea = tolerance.distance * tolerance.distance
        let sign = try RobustPredicates.orientation2D(
          Self.projected(bottomRight, axis: candidate),
          Self.projected(topLeft, axis: candidate),
          relativeTo: Self.projected(bottomLeft, axis: candidate),
          determinantTolerance: minimumArea, using: &execution
        )
        guard sign == .positive || sign == .negative else {
          continue
        }
        axis = candidate
        coordinate = value
        normalSign = sign == .positive ? 1.0 : -1.0
        return }
      return nil
    }

    func projected(_ point: Point3D) -> (first: Double, second: Double) {
      switch axis {
      case .x: (point.y, point.z)
      case .y: (point.z, point.x)
      case .z: (point.x, point.y)
      }
    }

    func coordinate(of point: Point3D) -> Double {
      axis.coordinate(of: point)
    }

    var projection: CertifiedRationalBezierSurfaceFluxIntegrator.AxisAlignedProjection {
      switch axis {
      case .x: .normalX
      case .y: .normalY
      case .z: .normalZ
      }
    }

    private static func projected(
      _ point: Point3D,
      axis: CoordinateAxis
    ) -> Point2D {
      switch axis {
      case .x: Point2D(x: point.y, y: point.z)
      case .y: Point2D(x: point.z, y: point.x)
      case .z: Point2D(x: point.x, y: point.y)
      }
    }
  }

  private func referencePoint(
    for shell: Shell,
    in model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
      try execution.consumeWork(1)
    return try BRepShellReferencePointResolver().referencePoint(
      for: shell,
      in: model,
      context: "Parametric volume", using: &execution
    )
  }

  private func coedgeCount(
    of shell: Shell,
    in model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> Int {
      try execution.consumeWork(1)
    var count = 0
    for faceID in shell.faceIDs {
      try execution.consumeWork(1)
      guard let face = model.faces[faceID] else {
        throw TopologyError.missingReference(
          "Parametric volume references a missing face."
        )
      }
      for loopID in face.loops {
        try execution.consumeWork(1)
        guard let loop = model.loops[loopID] else {
          throw TopologyError.missingReference(
            "Parametric volume references a missing loop."
          )
        }
        let next = count.addingReportingOverflow(loop.coedges.count)
        guard !next.overflow else { throw ExactScalarFailure.countOverflow }
        count = next.partialValue
      }
    }
    return count
  }

  private func characteristicLength(
    of shell: Shell,
    in model: BRepModel,
    reference: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
      try execution.consumeWork(1)
    var maximumLength = tolerance.distance
    for faceID in shell.faceIDs {
      try execution.consumeWork(1)
      guard let face = model.faces[faceID],
        let surface = model.geometry.surfaces[face.surfaceID]
      else {
        throw TopologyError.missingReference(
          "Parametric volume references missing face geometry."
        )
      }
      if case .bSpline(let spline) = surface {
        for row in spline.controlPoints {
          try execution.consumeWork(1)
          for point in row {
            try execution.consumeWork(1)
            maximumLength = max(maximumLength, (point - reference).length)
          }
        }
      }
    }
    return max(maximumLength, 1.0)
  }

  private func volumeTolerance(
    characteristicLength: Double,
    tolerance: ModelingTolerance
  ) -> Double {
    max(
      tolerance.distance * characteristicLength * characteristicLength * 0.0625,
      characteristicLength * characteristicLength * characteristicLength * 1.0e-13
    )
  }

  private struct PolynomialBezierPatch {
    var x: BernsteinPolynomial2D
    var y: BernsteinPolynomial2D
    var z: BernsteinPolynomial2D

    init?(
      surface: BSplineSurface3D,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
      try execution.consumeWork(1)
      let uCount = surface.uDegree.addingReportingOverflow(1)
      let vCount = surface.vDegree.addingReportingOverflow(1)
      guard !uCount.overflow, !vCount.overflow else { throw ExactScalarFailure.countOverflow }
      guard surface.uDegree >= 1,
        surface.vDegree >= 1,
        surface.uControlPointCount == uCount.partialValue,
        surface.vControlPointCount == vCount.partialValue,
        try Self.isSingleBezierKnotVector(
          surface.uKnots,
          degree: surface.uDegree, using: &execution
        ),
        try Self.isSingleBezierKnotVector(
          surface.vKnots,
          degree: surface.vDegree, using: &execution
        ),
        let firstWeight = surface.weights.first?.first,
        (try OriginalParameterQueryStorage.allSatisfy(surface.weights, using: &execution) { row, execution in (try OriginalParameterQueryStorage.allSatisfy(row, using: &execution) { item, execution in item == firstWeight }) })
      else {
        return nil
      }
      guard firstWeight.isFinite, firstWeight > Double.ulpOfOne else {
        throw GeometryError.invalidDistance(firstWeight)
      }
      x = BernsteinPolynomial2D(
        (try OriginalParameterQueryStorage.map(surface.controlPoints, using: &execution) { row, execution in
          (try OriginalParameterQueryStorage.map(row, using: &execution) { item, execution in OutwardInterval.exact(item.x) })
        }))
      y = BernsteinPolynomial2D(
        (try OriginalParameterQueryStorage.map(surface.controlPoints, using: &execution) { row, execution in
          (try OriginalParameterQueryStorage.map(row, using: &execution) { item, execution in OutwardInterval.exact(item.y) })
        }))
      z = BernsteinPolynomial2D(
        (try OriginalParameterQueryStorage.map(surface.controlPoints, using: &execution) { row, execution in
          (try OriginalParameterQueryStorage.map(row, using: &execution) { item, execution in OutwardInterval.exact(item.z) })
        }))
    }

    /// A span of a non-rational surface from its certified homogeneous Bezier controls, each
    /// coordinate enclosed by dividing by its weight's enclosure; nil when a weight's enclosure
    /// is not positive.
    init?(certified patch: CertifiedHomogeneousBezierSurfacePatch, using execution: inout OriginalQueryExecution) throws {
      try execution.consumeWork(1)
      func coordinate(_ value: (CertifiedHomogeneousBezierSurfacePatch.HomogeneousPoint) -> CertifiedHomogeneousBezierSurfacePatch.ScalarBounds,
        using execution: inout OriginalQueryExecution) throws -> BernsteinPolynomial2D? {
        var rows: [[OutwardInterval]] = []
        for row in patch.controls {
          try execution.consumeWork(1)
          var coefficients: [OutwardInterval] = []
          for point in row {
            try execution.consumeWork(1)
            guard point.weight.lower > 0.0, point.weight.isFinite, value(point).isFinite else { return nil }
            try OriginalParameterQueryStorage.append(
              OutwardInterval(lower: value(point).lower, upper: value(point).upper)
                / OutwardInterval(lower: point.weight.lower, upper: point.weight.upper)
            , to: &coefficients, using: &execution)
          }
          try OriginalParameterQueryStorage.append(coefficients, to: &rows, using: &execution)
        }
        return BernsteinPolynomial2D(rows)
      }
      guard let x = try coordinate({ $0.x }, using: &execution), let y = try coordinate({ $0.y }, using: &execution), let z = try coordinate({ $0.z }, using: &execution) else {
        return nil
      }
      self.init(x: x, y: y, z: z)
    }

    func trimmed(
      uLower: Double,
      uUpper: Double,
      vLower: Double,
      vUpper: Double,
      sourceUDomain: ParameterDomain,
      sourceVDomain: ParameterDomain,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> PolynomialBezierPatch {
      try execution.consumeWork(1)
      guard case .closed(let sourceULower, let sourceUUpper) = sourceUDomain,
        case .closed(let sourceVLower, let sourceVUpper) = sourceVDomain
      else {
        throw KernelError(
          phase: .topology,
          code: .invalidInput,
          tolerance: tolerance,
          message: "Polynomial B-spline volume requires closed parameter domains."
        )
      }
      let parameterScale = max(
        1.0,
        abs(sourceULower),
        abs(sourceUUpper),
        abs(sourceVLower),
        abs(sourceVUpper)
      )
      let parameterTolerance = max(
        tolerance.relative * parameterScale,
        Double.ulpOfOne * parameterScale * 256.0
      )
      guard uLower >= sourceULower - parameterTolerance,
        uUpper <= sourceUUpper + parameterTolerance,
        vLower >= sourceVLower - parameterTolerance,
        vUpper <= sourceVUpper + parameterTolerance,
        uUpper - uLower > parameterTolerance,
        vUpper - vLower > parameterTolerance
      else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "Rectangular pcurve trim lies outside its polynomial B-spline domain."
        )
      }
      let normalizedU = try Self.normalizedBounds(
        lower: uLower,
        upper: uUpper,
        domainLower: sourceULower,
        domainUpper: sourceUUpper,
        tolerance: tolerance
      )
      let normalizedV = try Self.normalizedBounds(
        lower: vLower,
        upper: vUpper,
        domainLower: sourceVLower,
        domainUpper: sourceVUpper,
        tolerance: tolerance
      )
      return try PolynomialBezierPatch(
        x: x.trimmed(u: normalizedU, v: normalizedV, using: &execution),
        y: y.trimmed(u: normalizedU, v: normalizedV, using: &execution),
        z: z.trimmed(u: normalizedU, v: normalizedV, using: &execution)
      )
    }

    func fluxIntegral(
      reference: Point3D,
      coefficientOperations: inout CoefficientOperationCount,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> OutwardInterval {
      try execution.consumeWork(1)
      return try fluxPolynomial(
        reference: reference,
        coefficientOperations: &coefficientOperations,
        tolerance: tolerance, using: &execution
      ).integral(using: &execution)
    }

    func fluxPrimitive(
      reference: Point3D,
      uDomain: ParameterDomain,
      vDomain: ParameterDomain,
      coefficientOperations: inout CoefficientOperationCount,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> CertifiedPolynomialSurfaceFluxPrimitive {
      try execution.consumeWork(1)
      let flux = try fluxPolynomial(
        reference: reference,
        coefficientOperations: &coefficientOperations,
        tolerance: tolerance, using: &execution
      )
      let denominator = OutwardInterval.exact(Double(flux.uDegree + 1))
      let primitive = (try OriginalParameterQueryStorage.map(flux.coefficients, using: &execution) { row, execution in
        var result: [OutwardInterval] = []
        let capacity = row.count.addingReportingOverflow(1)
        guard !capacity.overflow else { throw ExactScalarFailure.countOverflow }
        try OriginalParameterQueryStorage.reserve(capacity.partialValue, in: &result, using: &execution)
        try OriginalParameterQueryStorage.append(OutwardInterval.exact(0.0), to: &result, using: &execution)
        for coefficient in row {
          try execution.consumeWork(1)
          try OriginalParameterQueryStorage.append(result[result.count - 1] + coefficient / denominator, to: &result, using: &execution)
        }
        return (try OriginalParameterQueryStorage.map(result, using: &execution) { item, execution in
          TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
            lower: item.lower,
            upper: item.upper
          )
        })
      })
      return CertifiedPolynomialSurfaceFluxPrimitive(
        coefficients: primitive,
        uDomain: uDomain,
        vDomain: vDomain
      )
    }

    private func fluxPolynomial(
      reference: Point3D,
      coefficientOperations: inout CoefficientOperationCount,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      let tangentU = try PolynomialVector3(
        x: x.derivativeU(using: &execution),
        y: y.derivativeU(using: &execution),
        z: z.derivativeU(using: &execution)
      )
      let tangentV = try PolynomialVector3(
        x: x.derivativeV(using: &execution),
        y: y.derivativeV(using: &execution),
        z: z.derivativeV(using: &execution)
      )
      let areaVector = try tangentU.cross(
        tangentV,
        coefficientOperations: &coefficientOperations,
        tolerance: tolerance, using: &execution
      )
      let relativePosition = try PolynomialVector3(
        x: x.subtracting(constant: reference.x, using: &execution),
        y: y.subtracting(constant: reference.y, using: &execution),
        z: z.subtracting(constant: reference.z, using: &execution)
      )
      let flux = try relativePosition.dot(
        areaVector,
        coefficientOperations: &coefficientOperations,
        tolerance: tolerance, using: &execution
      ).scaled(by: OutwardInterval.exact(1.0) / OutwardInterval.exact(3.0), using: &execution)
      return flux
    }

    private init(
      x: BernsteinPolynomial2D,
      y: BernsteinPolynomial2D,
      z: BernsteinPolynomial2D
    ) {
      self.x = x
      self.y = y
      self.z = z
    }

    private static func isSingleBezierKnotVector(
      _ knots: [Double],
      degree: Int, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      try execution.consumeWork(1)
      let count = degree.addingReportingOverflow(1)
      let doubled = count.partialValue.multipliedReportingOverflow(by: 2)
      guard !count.overflow, !doubled.overflow else { throw ExactScalarFailure.countOverflow }
      guard knots.count == doubled.partialValue,
        let lower = knots.first,
        let upper = knots.last,
        upper > lower
      else {
        return false
      }
      return try OriginalParameterQueryStorage.allSatisfy(knots.prefix(degree + 1), using: &execution) { knot, execution in knot == lower }
        && OriginalParameterQueryStorage.allSatisfy(knots.suffix(degree + 1), using: &execution) { knot, execution in knot == upper }
    }

    private static func normalizedBounds(
      lower: Double,
      upper: Double,
      domainLower: Double,
      domainUpper: Double,
      tolerance: ModelingTolerance
    ) throws -> ClosedIntervalPair {
      let domainSpan =
        OutwardInterval.exact(domainUpper)
        - OutwardInterval.exact(domainLower)
      guard domainSpan.lower > 0.0 else {
        throw GeometryError.invalidDistance(domainUpper - domainLower)
      }
      let normalizedLower =
        lower == domainLower
        ? OutwardInterval.exact(0.0)
        : (OutwardInterval.exact(lower) - OutwardInterval.exact(domainLower))
          / domainSpan
      let normalizedUpper =
        upper == domainUpper
        ? OutwardInterval.exact(1.0)
        : (OutwardInterval.exact(upper) - OutwardInterval.exact(domainLower))
          / domainSpan
      let clampedLower = normalizedLower.intersection(
        OutwardInterval(lower: 0.0, upper: 1.0)
      )
      let clampedUpper = normalizedUpper.intersection(
        OutwardInterval(lower: 0.0, upper: 1.0)
      )
      guard let clampedLower,
        let clampedUpper,
        clampedUpper.upper > clampedLower.lower
      else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "Polynomial B-spline trim normalization produced an empty interval."
        )
      }
      return ClosedIntervalPair(lower: clampedLower, upper: clampedUpper)
    }
  }

  private struct ClosedIntervalPair {
    let lower: OutwardInterval
    let upper: OutwardInterval
  }

  private struct PolynomialVector3 {
    let x: BernsteinPolynomial2D
    let y: BernsteinPolynomial2D
    let z: BernsteinPolynomial2D

    func cross(
      _ other: PolynomialVector3,
      coefficientOperations: inout CoefficientOperationCount,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> PolynomialVector3 {
      try execution.consumeWork(1)
      return PolynomialVector3(
        x: try y.multiplied(
          by: other.z,
          coefficientOperations: &coefficientOperations,
          tolerance: tolerance, using: &execution
        ).subtracting(
          z.multiplied(
            by: other.y,
            coefficientOperations: &coefficientOperations,
            tolerance: tolerance, using: &execution
          ),
          tolerance: tolerance, using: &execution
        ),
        y: try z.multiplied(
          by: other.x,
          coefficientOperations: &coefficientOperations,
          tolerance: tolerance, using: &execution
        ).subtracting(
          x.multiplied(
            by: other.z,
            coefficientOperations: &coefficientOperations,
            tolerance: tolerance, using: &execution
          ),
          tolerance: tolerance, using: &execution
        ),
        z: try x.multiplied(
          by: other.y,
          coefficientOperations: &coefficientOperations,
          tolerance: tolerance, using: &execution
        ).subtracting(
          y.multiplied(
            by: other.x,
            coefficientOperations: &coefficientOperations,
            tolerance: tolerance, using: &execution
          ),
          tolerance: tolerance, using: &execution
        )
      )
    }

    func dot(
      _ other: PolynomialVector3,
      coefficientOperations: inout CoefficientOperationCount,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      let first = try x.multiplied(
        by: other.x,
        coefficientOperations: &coefficientOperations,
        tolerance: tolerance, using: &execution
      )
      let second = try y.multiplied(
        by: other.y,
        coefficientOperations: &coefficientOperations,
        tolerance: tolerance, using: &execution
      )
      let third = try z.multiplied(
        by: other.z,
        coefficientOperations: &coefficientOperations,
        tolerance: tolerance, using: &execution
      )
      return try first.adding(
        second,
        tolerance: tolerance, using: &execution
      ).adding(
        third,
        tolerance: tolerance, using: &execution
      )
    }
  }

  private struct BernsteinPolynomial2D {
    let coefficients: [[OutwardInterval]]

    var uDegree: Int {
      (coefficients.first?.count ?? 1) - 1
    }

    var vDegree: Int {
      coefficients.count - 1
    }

    init(_ coefficients: [[OutwardInterval]]) {
      self.coefficients = coefficients
    }

    func derivativeU(using execution: inout OriginalQueryExecution) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      return BernsteinPolynomial2D(
        (try OriginalParameterQueryStorage.map(coefficients, using: &execution) { row, execution in
          try OriginalParameterQueryStorage.map(0..<uDegree, using: &execution) { index, execution in
            (row[index + 1] - row[index]) * OutwardInterval.exact(Double(uDegree))
          }
        }))
    }

    func derivativeV(using execution: inout OriginalQueryExecution) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      return BernsteinPolynomial2D(
        try OriginalParameterQueryStorage.map(0..<vDegree, using: &execution) { rowIndex, execution in
          (try OriginalParameterQueryStorage.map(coefficients[rowIndex].indices, using: &execution) { columnIndex, execution in
            (coefficients[rowIndex + 1][columnIndex]
              - coefficients[rowIndex][columnIndex])
              * OutwardInterval.exact(Double(vDegree))
          })
        })
    }

    func subtracting(constant: Double, using execution: inout OriginalQueryExecution) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      let interval = OutwardInterval.exact(constant)
      return BernsteinPolynomial2D(
        (try OriginalParameterQueryStorage.map(coefficients, using: &execution) { row, execution in
          (try OriginalParameterQueryStorage.map(row, using: &execution) { item, execution in item - interval })
        }))
    }

    func scaled(by scale: OutwardInterval, using execution: inout OriginalQueryExecution) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      return BernsteinPolynomial2D(
        (try OriginalParameterQueryStorage.map(coefficients, using: &execution) { row, execution in
          (try OriginalParameterQueryStorage.map(row, using: &execution) { item, execution in item * scale })
        }))
    }

    func multiplied(
      by other: BernsteinPolynomial2D,
      coefficientOperations: inout CoefficientOperationCount,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      let uSum = uDegree.addingReportingOverflow(other.uDegree)
      let vSum = vDegree.addingReportingOverflow(other.vDegree)
      let uCount = uSum.partialValue.addingReportingOverflow(1)
      let vCount = vSum.partialValue.addingReportingOverflow(1)
      let coefficientCount = uCount.partialValue.multipliedReportingOverflow(by: vCount.partialValue)
      guard !uSum.overflow, !vSum.overflow, !uCount.overflow, !vCount.overflow,
        !coefficientCount.overflow else { throw ExactScalarFailure.countOverflow }
      let outputUDegree = uSum.partialValue
      let outputVDegree = vSum.partialValue
      try coefficientOperations.consume(coefficientCount.partialValue, tolerance: tolerance)
      var output = try OriginalParameterQueryStorage.map(0..<vCount.partialValue, using: &execution) { _, execution in
        try OriginalParameterQueryStorage.repeated(OutwardInterval.exact(0.0), count: uCount.partialValue, using: &execution)
      }
      for outputV in 0...outputVDegree {
        try execution.consumeWork(1)
        let firstVLower = max(0, outputV - other.vDegree)
        let firstVUpper = min(vDegree, outputV)
        for outputU in 0...outputUDegree {
          try execution.consumeWork(1)
          let firstULower = max(0, outputU - other.uDegree)
          let firstUUpper = min(uDegree, outputU)
          var coefficient = OutwardInterval.exact(0.0)
          for firstV in firstVLower...firstVUpper {
            try execution.consumeWork(1)
            let secondV = outputV - firstV
            let vWeight = try Self.productWeight(
              firstDegree: vDegree,
              firstIndex: firstV,
              secondDegree: other.vDegree,
              secondIndex: secondV, using: &execution
            )
            for firstU in firstULower...firstUUpper {
              try execution.consumeWork(1)
              let secondU = outputU - firstU
              let uWeight = try Self.productWeight(
                firstDegree: uDegree,
                firstIndex: firstU,
                secondDegree: other.uDegree,
                secondIndex: secondU, using: &execution
              )
              coefficient =
                coefficient
                + coefficients[firstV][firstU]
                * other.coefficients[secondV][secondU]
                * uWeight * vWeight
            }
          }
          output[outputV][outputU] = coefficient
        }
      }
      return BernsteinPolynomial2D(output)
    }

    func integral(using execution: inout OriginalQueryExecution) throws -> OutwardInterval {
      try execution.consumeWork(1)
      var total = OutwardInterval.exact(0.0)
      for row in coefficients {
        try execution.consumeWork(1)
        for coefficient in row {
          try execution.consumeWork(1)
          total = total + coefficient
        }
      }
      let count = (uDegree + 1).multipliedReportingOverflow(by: vDegree + 1)
      guard !count.overflow else { throw ExactScalarFailure.countOverflow }
      let denominator = OutwardInterval.exact(Double(count.partialValue))
      return total / denominator
    }

    func trimmed(
      u: ClosedIntervalPair,
      v: ClosedIntervalPair, using execution: inout OriginalQueryExecution
    ) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      let uTrimmed = try Self.trimLines(
        coefficients,
        lower: u.lower,
        upper: u.upper, using: &execution
      )
      let transposed = try Self.transpose(uTrimmed, using: &execution)
      let vTrimmed = try Self.trimLines(
        transposed,
        lower: v.lower,
        upper: v.upper, using: &execution
      )
      return try BernsteinPolynomial2D(Self.transpose(vTrimmed, using: &execution))
    }

    func adding(
      _ other: BernsteinPolynomial2D,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      try validateMatchingDegree(other, tolerance: tolerance, using: &execution)
      return BernsteinPolynomial2D(
        (try OriginalParameterQueryStorage.map(coefficients.indices, using: &execution) { row, execution in
          (try OriginalParameterQueryStorage.map(coefficients[row].indices, using: &execution) { column, execution in
            coefficients[row][column] + other.coefficients[row][column]
          })
        }))
    }

    func subtracting(
      _ other: BernsteinPolynomial2D,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BernsteinPolynomial2D {
      try execution.consumeWork(1)
      try validateMatchingDegree(other, tolerance: tolerance, using: &execution)
      return BernsteinPolynomial2D(
        (try OriginalParameterQueryStorage.map(coefficients.indices, using: &execution) { row, execution in
          (try OriginalParameterQueryStorage.map(coefficients[row].indices, using: &execution) { column, execution in
            coefficients[row][column] - other.coefficients[row][column]
          })
        }))
    }

    private func validateMatchingDegree(
      _ other: BernsteinPolynomial2D,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
      try execution.consumeWork(1)
      guard uDegree == other.uDegree,
        vDegree == other.vDegree
      else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "Certified volume polynomial addition requires matching bidegrees."
        )
      }
    }

    private static func trimLines(
      _ lines: [[OutwardInterval]],
      lower: OutwardInterval,
      upper: OutwardInterval, using execution: inout OriginalQueryExecution
    ) throws -> [[OutwardInterval]] {
      try execution.consumeWork(1)
      return (try OriginalParameterQueryStorage.map(lines, using: &execution) { line, execution in
        var current = line
        if lower.upper > 0.0 {
          current = try split(current, parameter: lower, using: &execution).upper
        }
        if upper.lower < 1.0 {
          let denominator = OutwardInterval.exact(1.0) - lower
          let localUpper = (upper - lower) / denominator
          current = try split(current, parameter: localUpper, using: &execution).lower
        }
        return current
      })
    }

    private static func split(
      _ values: [OutwardInterval],
      parameter: OutwardInterval, using execution: inout OriginalQueryExecution
    ) throws -> (lower: [OutwardInterval], upper: [OutwardInterval]) {
      try execution.consumeWork(1)
      let complement = OutwardInterval.exact(1.0) - parameter
      try execution.retainStorage(bytes: MemoryLayout<[OutwardInterval]>.stride)
      var levels = [values]
      while let previous = levels.last, previous.count > 1 {
        try execution.consumeWork(1)
        try OriginalParameterQueryStorage.append(
          try OriginalParameterQueryStorage.map(0..<(previous.count - 1), using: &execution) { index, execution in
            previous[index] * complement + previous[index + 1] * parameter
          }, to: &levels, using: &execution)
      }
      return (
        (try OriginalParameterQueryStorage.map(levels, using: &execution) { item, execution in item[0] }),
        try OriginalParameterQueryStorage.map(levels.reversed(), using: &execution) { level, execution in level[level.count - 1] }
      )
    }

    private static func transpose(
      _ values: [[OutwardInterval]], using execution: inout OriginalQueryExecution
    ) throws -> [[OutwardInterval]] {
      try execution.consumeWork(1)
      guard let first = values.first else { return [] }
      return (try OriginalParameterQueryStorage.map(first.indices, using: &execution) { column, execution in
        (try OriginalParameterQueryStorage.map(values.indices, using: &execution) { row, execution in values[row][column] })
      })
    }

    private static func productWeight(
      firstDegree: Int,
      firstIndex: Int,
      secondDegree: Int,
      secondIndex: Int, using execution: inout OriginalQueryExecution
    ) throws -> OutwardInterval {
      try execution.consumeWork(1)
      return try binomial(firstDegree, firstIndex, using: &execution)
        * binomial(secondDegree, secondIndex, using: &execution)
        / binomial(firstDegree + secondDegree, firstIndex + secondIndex, using: &execution)
    }

    private static func binomial(_ n: Int, _ k: Int, using execution: inout OriginalQueryExecution) throws -> OutwardInterval {
      try execution.consumeWork(1)
      let reducedK = min(k, n - k)
      guard reducedK > 0 else { return .exact(1.0) }
      var value = OutwardInterval.exact(1.0)
      for index in 1...reducedK {
        try execution.consumeWork(1)
        value =
          value * OutwardInterval.exact(Double(n - reducedK + index))
          / OutwardInterval.exact(Double(index))
      }
      return value
    }
  }

  /// Local mathematical coefficient-operation ceiling; resource work is charged to execution.
  private struct CoefficientOperationCount {
    let limit: Int
    var consumed = 0

    mutating func consume(
      _ count: Int,
      tolerance: ModelingTolerance
    ) throws {
      guard limit >= 0, count >= 0, count <= limit,
        consumed <= limit - count
      else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: Double(consumed) + Double(max(count, 0)),
          tolerance: tolerance,
          message:
            "Certified polynomial B-spline volume exhausted its coefficient-operation budget."
        )
      }
      consumed += count
    }
  }

  private struct ProceduralFluxCell: Sendable, Hashable {
    let uLower: Double
    let uUpper: Double
    let vLower: Double
    let vUpper: Double

    var uWidth: Double { uUpper - uLower }
    var vWidth: Double { vUpper - vLower }

    func split(
      alongU: Bool
    ) -> (first: ProceduralFluxCell, second: ProceduralFluxCell) {
      let uMidpoint = uLower + (uUpper - uLower) * 0.5
      let vMidpoint = vLower + (vUpper - vLower) * 0.5
      if alongU {
        return (
          ProceduralFluxCell(
            uLower: uLower,
            uUpper: uMidpoint,
            vLower: vLower,
            vUpper: vUpper
          ),
          ProceduralFluxCell(
            uLower: uMidpoint,
            uUpper: uUpper,
            vLower: vLower,
            vUpper: vUpper
          )
        )
      }
      return (
        ProceduralFluxCell(
          uLower: uLower,
          uUpper: uUpper,
          vLower: vLower,
          vUpper: vMidpoint
        ),
        ProceduralFluxCell(
          uLower: uLower,
          uUpper: uUpper,
          vLower: vMidpoint,
          vUpper: vUpper
        )
      )
    }

    func parameterBox() throws -> SurfaceParameterBox {
      SurfaceParameterBox(
        u: try ScalarInterval(lower: uLower, upper: uUpper),
        v: try ScalarInterval(lower: vLower, upper: vUpper)
      )
    }

    func midpointBox(
      tolerance: ModelingTolerance,
      relativeWidthMultiplier: Double
    ) throws -> SurfaceParameterBox {
      SurfaceParameterBox(
        u: try enclosingMidpoint(
          lower: uLower,
          upper: uUpper,
          tolerance: tolerance,
          relativeWidthMultiplier: relativeWidthMultiplier
        ),
        v: try enclosingMidpoint(
          lower: vLower,
          upper: vUpper,
          tolerance: tolerance,
          relativeWidthMultiplier: relativeWidthMultiplier
        )
      )
    }

    private func enclosingMidpoint(
      lower: Double,
      upper: Double,
      tolerance: ModelingTolerance,
      relativeWidthMultiplier: Double
    ) throws -> ScalarInterval {
      let midpoint = lower + (upper - lower) * 0.5
      let scale = max(abs(lower), abs(upper), 1.0)
      let preferredHalfWidth = max(
        tolerance.relative * scale * relativeWidthMultiplier,
        Double.ulpOfOne * scale * 4_096.0
      ).nextUp
      let halfWidth = min(
        preferredHalfWidth,
        ((upper - lower) * 0.25).nextDown
      )
      let enclosureLower = max(
        lower,
        (midpoint - halfWidth).nextDown
      )
      let enclosureUpper = min(
        upper,
        (midpoint + halfWidth).nextUp
      )
      guard enclosureUpper > enclosureLower else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: upper - lower,
          tolerance: nil,
          message:
            "Procedural volume midpoint subdivision exhausted representable parameter precision."
        )
      }
      return try ScalarInterval(
        lower: enclosureLower,
        upper: enclosureUpper
      )
    }
  }

  private struct ProceduralFluxWorkItem: Sendable, Hashable {
    let cell: ProceduralFluxCell
    let errorBudget: Double
    let depth: Int
  }

  private struct ProceduralFluxContribution: Sendable, Hashable {
    let interval: OutwardInterval
    let uErrorUpper: Double
    let vErrorUpper: Double
  }

  private struct OutwardInterval: Sendable, Hashable {
    let lower: Double
    let upper: Double

    init(lower: Double, upper: Double) {
      self.lower = lower
      self.upper = upper
    }

    static func exact(_ value: Double) -> OutwardInterval {
      OutwardInterval(lower: value, upper: value)
    }

    var errorRadius: Double {
      (upper - lower) * 0.5
    }

    func intersection(_ other: OutwardInterval) -> OutwardInterval? {
      let lower = max(lower, other.lower)
      let upper = min(upper, other.upper)
      guard lower <= upper else { return nil }
      return OutwardInterval(lower: lower, upper: upper)
    }

    static prefix func - (value: OutwardInterval) -> OutwardInterval {
      OutwardInterval(lower: (-value.upper).nextDown, upper: (-value.lower).nextUp)
    }

    static func + (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
      OutwardInterval(
        lower: (lhs.lower + rhs.lower).nextDown,
        upper: (lhs.upper + rhs.upper).nextUp
      )
    }

    static func - (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
      lhs + (-rhs)
    }

    static func * (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
      let products = [
        lhs.lower * rhs.lower,
        lhs.lower * rhs.upper,
        lhs.upper * rhs.lower,
        lhs.upper * rhs.upper,
      ]
      return OutwardInterval(
        lower: (products.min() ?? -.infinity).nextDown,
        upper: (products.max() ?? .infinity).nextUp
      )
    }

    static func / (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
      guard rhs.lower > 0.0 || rhs.upper < 0.0 else {
        // A zero-containing divisor produces an unbounded enclosure;
        // final volume validation reports it as a typed failure.
        return OutwardInterval(lower: -.infinity, upper: .infinity)
      }
      return lhs
        * OutwardInterval(
          lower: (1.0 / rhs.upper).nextDown,
          upper: (1.0 / rhs.lower).nextUp
        )
    }
  }
}
