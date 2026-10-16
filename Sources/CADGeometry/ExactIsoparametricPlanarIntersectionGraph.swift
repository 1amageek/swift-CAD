import CADCore

#if !hasFeature(Embedded)
  import Foundation
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#else
  #error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// A complete graph certificate for an internal isocurve that is the unique intersection with a
/// rational affine-plane patch.
///
/// The source surface contract is intentionally strict: a quadratic two-span parameter direction
/// has one exactly coplanar middle control layer, the two lower layers are strictly on one side,
/// and the two upper layers are strictly on the other side. Nonnegative B-spline basis functions
/// then prove that the middle knot is the entire zero locus. The planar patch contract requires an
/// exact parallelogram and positive rational weights. Its Jacobian numerator has four strictly
/// positive Bernstein coefficients, proving a bijection between its parameter square and affine
/// plane coordinates.
struct ExactIsoparametricPlanarIntersectionGraph: Sendable {
  struct Cell: Sendable {
    let normalizedBounds: [(lower: Double, upper: Double)]
    let freeParameter: SurfaceIntersectionParameterCoordinate
    fileprivate let sourceULower: Double
    fileprivate let sourceUUpper: Double
  }

  private struct ExpansionVector3 {
    let x: [Double]
    let y: [Double]
    let z: [Double]
  }

  private struct ExactPlanePatch {
    let origin: Point3D
    let u: Vector3D
    let v: Vector3D
    let exactU: ExpansionVector3
    let exactV: ExpansionVector3
    let gramUU: [Double]
    let gramUV: [Double]
    let gramVV: [Double]
    let gramDeterminant: [Double]
    let weights: [[Double]]
  }

  private struct SourceSurface {
    let surface: BSplineSurface3D
    let fixedV: Double
    let lowerV: Double
    let uSpans: [(lower: Double, upper: Double)]
  }

  let cells: [Cell]
  private let sourceIsFirst: Bool
  private let source: SourceSurface
  private let plane: ExactPlanePatch

  /// The sealed V-middle theorem retains this original U law without Cartesian contraction.
  func originalMiddleCurve(
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> BSplineCurve3D {
    try execution.consumeWork(1)
    let surface = source.surface
    let curve = BSplineCurve3D(
      degree: surface.uDegree, knots: surface.uKnots,
      controlPoints: surface.controlPoints[2], weights: surface.weights[2],
      isPeriodic: surface.isUPeriodic, periodicOrigin: surface.uPeriodicOrigin)
    try curve.validate(tolerance: tolerance, using: &execution)
    return curve
  }

  static func certified(
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ExactIsoparametricPlanarIntersectionGraph? {
    try execution.consumeWork(1)
    try tolerance.validate()
    if let plane = try exactPlanePatch(second, using: &execution),
      let source = try exactSourceSurface(first, intersecting: plane, using: &execution)
    {
      return try make(source: source, plane: plane, sourceIsFirst: true, using: &execution)
    }
    if let plane = try exactPlanePatch(first, using: &execution),
      let source = try exactSourceSurface(second, intersecting: plane, using: &execution)
    {
      return try make(source: source, plane: plane, sourceIsFirst: false, using: &execution)
    }
    return nil
  }

  /// Establishes the original closed domain for this factory's surface pair.
  /// Tolerated box or anchor matches do not authorize inherited root existence.
  func certifiesExactDomain(
    parameterBox: SurfaceIntersectionParameterBox,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    first: BSplineSurface3D,
    second: BSplineSurface3D, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    let sourceU = sourceIsFirst ? parameterBox.firstU : parameterBox.secondU
    let sourceV = sourceIsFirst ? parameterBox.firstV : parameterBox.secondV
    let planeU = sourceIsFirst ? parameterBox.secondU : parameterBox.firstU
    let planeV = sourceIsFirst ? parameterBox.secondV : parameterBox.firstV
    let planeSurface = sourceIsFirst ? second : first
    guard case .closed(let planeULower, let planeUUpper) = planeSurface.uDomain,
      case .closed(let planeVLower, let planeVUpper) = planeSurface.vDomain,
      sourceV.lower == source.lowerV,
      sourceV.upper == source.fixedV,
      planeU.lower == planeULower,
      planeU.upper == planeUUpper,
      planeV.lower == planeVLower,
      planeV.upper == planeVUpper
    else {
      return false
    }
    for cell in cells where cell.freeParameter == freeParameter {
      try execution.consumeWork(1)
      if sourceU.lower == cell.sourceULower,
        sourceU.upper == cell.sourceUUpper
      {
        return true
      }
    }
    return false
  }

  func normalizedParameterPair(
    in cell: Cell,
    at fraction: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntersectionParameterPair {
    try execution.consumeWork(1)
    guard fraction.isFinite,
      fraction >= -tolerance.relative,
      fraction <= 1.0 + tolerance.relative
    else {
      throw GeometryError.invalidDistance(fraction)
    }
    let clamped = min(max(fraction, 0.0), 1.0)
    let sourceU =
      cell.sourceULower
      + (cell.sourceUUpper - cell.sourceULower) * clamped
    let point = try source.surface.point(
      u: sourceU,
      v: source.fixedV,
      tolerance: tolerance, using: &execution
    )
    let planeParameters = try planarParameters(
      for: point,
      tolerance: tolerance, using: &execution)
    let sourceNormalizedU = Self.normalizedParameter(sourceU, in: source.surface.uDomain)
    let sourceNormalizedV = Self.normalizedParameter(source.fixedV, in: source.surface.vDomain)
    try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
    return try SurfaceIntersectionParameterPair(
      values: sourceIsFirst
        ? [sourceNormalizedU, sourceNormalizedV, planeParameters.u, planeParameters.v]
        : [planeParameters.u, planeParameters.v, sourceNormalizedU, sourceNormalizedV])
  }

  func actualParameterPair(
    in cell: Cell,
    at fraction: Double,
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntersectionParameterPair {
    try execution.consumeWork(1)
    let normalized = try normalizedParameterPair(
      in: cell,
      at: fraction,
      tolerance: tolerance, using: &execution
    ).values
    try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
    return try SurfaceIntersectionParameterPair(values: [
      Self.actualParameter(normalized[0], in: first.uDomain),
      Self.actualParameter(normalized[1], in: first.vDomain),
      Self.actualParameter(normalized[2], in: second.uDomain),
      Self.actualParameter(normalized[3], in: second.vDomain),
    ])
  }

  func certifies(
    parameterBox: SurfaceIntersectionParameterBox,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    lowerAnchor: SurfaceIntersectionParameterPair,
    midpointAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    for cell in cells where cell.freeParameter == freeParameter {
      try execution.consumeWork(1)
      guard
        try Self.matches(
          parameterBox,
          normalizedBounds: cell.normalizedBounds,
          first: first,
          second: second,
          tolerance: tolerance, using: &execution)
      else {
        continue
      }
      try OriginalCoefficientAllocation.reserve(count: 3, of: Double.self, using: &execution)
      let expected = try OriginalCoefficientAllocation.map(
        elements: [0.0, 0.5, 1.0], using: &execution
      ) { element, execution in
        try actualParameterPair(
          in: cell,
          at: element,
          first: first,
          second: second,
          tolerance: tolerance, using: &execution)
      }
      try OriginalCoefficientAllocation.reserve(
        count: 3, of: SurfaceIntersectionParameterPair.self, using: &execution)
      return try
        (zip([lowerAnchor, midpointAnchor, upperAnchor], expected)
        .allSatisfy { stored, reproduced in
          try execution.consumeWork(1)
          return try
            (zip(stored.values, reproduced.values).allSatisfy {
              try execution.consumeWork(1)
              return abs($0.0 - $0.1) <= tolerance.relative
            })
        })
    }
    return false
  }

  func parameterDerivativeBounds(
    parameterBox: SurfaceIntersectionParameterBox,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    direction: CertifiedImplicitIntersectionDirection,
    lowerAnchor: SurfaceIntersectionParameterPair,
    midpointAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [ScalarInterval]? {
    try execution.consumeWork(1)
    guard
      try certifies(
        parameterBox: parameterBox,
        freeParameter: freeParameter,
        lowerAnchor: lowerAnchor,
        midpointAnchor: midpointAnchor,
        upperAnchor: upperAnchor,
        first: first,
        second: second,
        tolerance: tolerance, using: &execution),
      let cell = try cells.first(where: {
        try $0.freeParameter == freeParameter
          && Self.matches(
            parameterBox,
            normalizedBounds: $0.normalizedBounds,
            first: first,
            second: second,
            tolerance: tolerance, using: &execution)
      })
    else {
      return nil
    }

    let sourceCurve = try originalMiddleCurve(tolerance: tolerance, using: &execution)
    let sourceInterval = try ScalarInterval(
      lower: cell.sourceULower,
      upper: cell.sourceUUpper
    )
    let patches = try BSplineCurveBezierDecomposer().curvePatches(
      curve: sourceCurve,
      intersecting: sourceInterval,
      tolerance: tolerance, using: &execution
    )
    guard patches.count == 1,
      let sourcePatch = patches.first,
      sourcePatch.lower == cell.sourceULower,
      sourcePatch.upper == cell.sourceUUpper
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact isoparametric-planar graph lost its source Bezier span."
      )
    }
    let sourceJet = try RationalBezierCurveJetEncloser().enclosure(
      of: sourcePatch,
      tolerance: tolerance, using: &execution
    )
    let sourceScale = OutwardScalarInterval(
      try parameterBox.interval(for: freeParameter).width
    )
    let tangent = IntervalVector3DBounds(
      x: sourceJet.x.derivativeU * sourceScale,
      y: sourceJet.y.derivativeU * sourceScale,
      z: sourceJet.z.derivativeU * sourceScale
    )
    let affineDerivative = try affineCoordinateDerivativeBounds(
      tangent: tangent,
      tolerance: tolerance, using: &execution)
    let planarJacobian = try planarMapJacobianBounds(tolerance: tolerance, using: &execution)
    guard
      let planeUNormalized =
        (affineDerivative.u * planarJacobian.dv.y
        - affineDerivative.v * planarJacobian.dv.x).divided(by: planarJacobian.determinant),
      let planeVNormalized =
        (affineDerivative.v * planarJacobian.du.x
        - affineDerivative.u * planarJacobian.du.y).divided(by: planarJacobian.determinant)
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact isoparametric-planar graph lost its certified planar inverse derivative."
      )
    }

    let sourceU = sourceScale
    let zero = OutwardScalarInterval(lower: 0.0, upper: 0.0)
    let planeUCoordinate: SurfaceIntersectionParameterCoordinate =
      sourceIsFirst
      ? .secondU
      : .firstU
    let planeVCoordinate: SurfaceIntersectionParameterCoordinate =
      sourceIsFirst
      ? .secondV
      : .firstV
    let planeU =
      planeUNormalized
      * OutwardScalarInterval(
        try parameterBox.interval(for: planeUCoordinate).width
      )
    let planeV =
      planeVNormalized
      * OutwardScalarInterval(
        try parameterBox.interval(for: planeVCoordinate).width
      )
    try OriginalCoefficientAllocation.reserve(
      count: 4, of: OutwardScalarInterval.self, using: &execution)
    let forward =
      sourceIsFirst
      ? [sourceU, zero, planeU, planeV]
      : [planeU, planeV, sourceU, zero]
    let directed =
      direction == .forward
      ? forward
      : try OriginalCoefficientAllocation.map(elements: forward, using: &execution) {
        element, execution in Self.negated(element)
      }
    guard
      try
        (directed.allSatisfy({
          try execution.consumeWork(1)
          return $0.isFinite
        }))
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message:
          "An exact isoparametric-planar graph derivative exceeded finite interval arithmetic."
      )
    }
    return try OriginalCoefficientAllocation.map(elements: directed, using: &execution) {
      element, execution in
      try ScalarInterval(lower: element.lower, upper: element.upper)
    }
  }

  func restrictedBounds(
    parameterBox: SurfaceIntersectionParameterBox,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    direction: CertifiedImplicitIntersectionDirection,
    lowerAnchor: SurfaceIntersectionParameterPair,
    midpointAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CertifiedImplicitIntersectionGraphSubcell? {
    try execution.consumeWork(1)
    guard lowerFraction.isFinite,
      upperFraction.isFinite,
      lowerFraction >= 0.0,
      upperFraction <= 1.0,
      upperFraction - lowerFraction > tolerance.relative,
      try certifies(
        parameterBox: parameterBox,
        freeParameter: freeParameter,
        lowerAnchor: lowerAnchor,
        midpointAnchor: midpointAnchor,
        upperAnchor: upperAnchor,
        first: first,
        second: second,
        tolerance: tolerance, using: &execution),
      let cell = try cells.first(where: {
        try $0.freeParameter == freeParameter
          && Self.matches(
            parameterBox,
            normalizedBounds: $0.normalizedBounds,
            first: first,
            second: second,
            tolerance: tolerance, using: &execution)
      })
    else {
      return nil
    }

    let directedLower =
      direction == .forward
      ? lowerFraction
      : 1.0 - upperFraction
    let directedUpper =
      direction == .forward
      ? upperFraction
      : 1.0 - lowerFraction
    let sourceLower =
      cell.sourceULower
      + (cell.sourceUUpper - cell.sourceULower) * directedLower
    let sourceUpper =
      cell.sourceULower
      + (cell.sourceUUpper - cell.sourceULower) * directedUpper
    let sourceCurve = try originalMiddleCurve(tolerance: tolerance, using: &execution)
    let sourceInterval = try ScalarInterval(
      lower: sourceLower,
      upper: sourceUpper
    )
    let patches = try BSplineCurveBezierDecomposer().curvePatches(
      curve: sourceCurve,
      intersecting: sourceInterval,
      tolerance: tolerance, using: &execution
    )
    guard patches.count == 1, let sourcePatch = patches.first else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact isoparametric-planar subcell crossed a source Bezier span."
      )
    }
    let sourceJet = try RationalBezierCurveJetEncloser().enclosure(
      of: sourcePatch,
      over: sourceInterval,
      tolerance: tolerance, using: &execution
    )
    let affine = try affineCoordinateBounds(
      position: IntervalVector3DBounds(
        x: sourceJet.x.value,
        y: sourceJet.y.value,
        z: sourceJet.z.value
      ),
      tolerance: tolerance, using: &execution)
    let normalizedPlane = try inversePlanarMapBounds(
      affineU: affine.u,
      affineV: affine.v,
      tolerance: tolerance, using: &execution)
    let normalizedPlaneU = normalizedPlane.u
    let normalizedPlaneV = normalizedPlane.v
    let sourceU = try containingInterval(
      sourceLower,
      sourceUpper,
      in: source.surface.uDomain,
      tolerance: tolerance, using: &execution)
    let sourceV = try containingInterval(
      source.fixedV,
      source.fixedV,
      in: source.surface.vDomain,
      tolerance: tolerance, using: &execution)
    let planeSurface = sourceIsFirst ? second : first
    let planeU = try actualInterval(
      normalizedPlaneU,
      in: planeSurface.uDomain,
      tolerance: tolerance, using: &execution)
    let planeV = try actualInterval(
      normalizedPlaneV,
      in: planeSurface.vDomain,
      tolerance: tolerance, using: &execution)
    try OriginalCoefficientAllocation.reserve(count: 4, of: ScalarInterval.self, using: &execution)
    let intervals =
      sourceIsFirst
      ? [sourceU, sourceV, planeU, planeV]
      : [planeU, planeV, sourceU, sourceV]

    let sourceSpan = sourceUpper - sourceLower
    let traversalSign = direction == .forward ? 1.0 : -1.0
    let tangentScale = OutwardScalarInterval(sourceSpan * traversalSign)
    let tangent = IntervalVector3DBounds(
      x: sourceJet.x.derivativeU * tangentScale,
      y: sourceJet.y.derivativeU * tangentScale,
      z: sourceJet.z.derivativeU * tangentScale
    )
    let affineDerivative = try affineCoordinateDerivativeBounds(
      tangent: tangent,
      tolerance: tolerance, using: &execution)
    let planarJacobian = try planarMapJacobianBounds(
      u: normalizedPlaneU,
      v: normalizedPlaneV,
      tolerance: tolerance, using: &execution)
    guard
      let planeUNormalized =
        (affineDerivative.u * planarJacobian.dv.y
        - affineDerivative.v * planarJacobian.dv.x).divided(by: planarJacobian.determinant),
      let planeVNormalized =
        (affineDerivative.v * planarJacobian.du.x
        - affineDerivative.u * planarJacobian.du.y).divided(by: planarJacobian.determinant)
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact isoparametric-planar subcell lost its local inverse derivative."
      )
    }
    let zero = OutwardScalarInterval(0.0)
    let planeUDomainWidth = Self.domainWidth(planeSurface.uDomain)
    let planeVDomainWidth = Self.domainWidth(planeSurface.vDomain)
    try OriginalCoefficientAllocation.reserve(
      count: 8, of: OutwardScalarInterval.self, using: &execution)
    let sourceDerivatives = [
      OutwardScalarInterval(sourceSpan * traversalSign),
      zero,
    ]
    let planeDerivatives = [
      planeUNormalized * OutwardScalarInterval(planeUDomainWidth),
      planeVNormalized * OutwardScalarInterval(planeVDomainWidth),
    ]
    let derivativeIntervals =
      sourceIsFirst
      ? sourceDerivatives + planeDerivatives
      : planeDerivatives + sourceDerivatives
    guard
      try
        (derivativeIntervals.allSatisfy({
          try execution.consumeWork(1)
          return $0.isFinite
        }))
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact isoparametric-planar subcell derivative exceeded finite arithmetic."
      )
    }
    return CertifiedImplicitIntersectionGraphSubcell(
      parameterBox: SurfaceIntersectionParameterBox(
        firstU: intervals[0],
        firstV: intervals[1],
        secondU: intervals[2],
        secondV: intervals[3]
      ),
      parameterDerivativeBounds: try OriginalCoefficientAllocation.map(
        elements: derivativeIntervals, using: &execution
      ) { element, execution in
        try ScalarInterval(lower: element.lower, upper: element.upper)
      }
    )
  }

  func planarAffineFluxTraversal(
    curve: CertifiedImplicitSurfaceParameterCurve,
    surface: BSplineSurface3D,
    reference: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CertifiedPlanarAffineFluxTraversal? {
    try execution.consumeWork(1)
    let planeSurface =
      sourceIsFirst
      ? curve.intersection.secondSurface
      : curve.intersection.firstSurface
    let planeRole: SurfaceIntersectionSurfaceRole =
      sourceIsFirst
      ? .second
      : .first
    guard curve.role == planeRole,
      Surface3D.bSpline(surface) == planeSurface
    else {
      return nil
    }

    let sourceCurve = try originalMiddleCurve(tolerance: tolerance, using: &execution)
    let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
      curve: sourceCurve,
      tolerance: tolerance, using: &execution
    )
    guard sourcePatches.count == cells.count,
      try
        (zip(sourcePatches, cells).allSatisfy({ patch, cell in
          try execution.consumeWork(1)
          return patch.lower == cell.sourceULower
            && patch.upper == cell.sourceUUpper
        }))
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact planar flux traversal lost its source Bezier spans."
      )
    }

    let traversalSegments = try curve.canonicalTraversalSegments(
      tolerance: tolerance, using: &execution
    )
    let cellCount = Double(cells.count)
    var resultPatches: [CertifiedPlanarAffineFluxTraversal.Patch] = []
    for traversal in traversalSegments {
      try execution.consumeWork(1)
      for index in cells.indices {
        try execution.consumeWork(1)
        let cellLower = Double(index) / cellCount
        let cellUpper = Double(index + 1) / cellCount
        let overlapLower = max(
          traversal.canonicalLowerFraction,
          cellLower
        )
        let overlapUpper = min(
          traversal.canonicalUpperFraction,
          cellUpper
        )
        guard overlapUpper > overlapLower else { continue }
        let localLower = min(
          max((overlapLower - cellLower) * cellCount, 0.0),
          1.0
        )
        let localUpper = min(
          max((overlapUpper - cellLower) * cellCount, 0.0),
          1.0
        )
        let patch = sourcePatches[index]
        let controls = try OriginalCoefficientAllocation.map(
          elements: patch.controlPoints.indices, using: &execution
        ) { controlIndex, execution in
          let affine = try affineCoordinates(
            of: patch.controlPoints[controlIndex],
            tolerance: tolerance, using: &execution)
          let weight = OutwardScalarInterval(patch.weights[controlIndex])
          return AffineHomogeneousControl(
            x: affine.u * weight,
            y: affine.v * weight,
            weight: weight
          )
        }
        var restricted = try restrictedControls(
          controls,
          lower: localLower,
          upper: localUpper,
          tolerance: tolerance, using: &execution)
        if traversal.direction == .reversed {
          restricted.reverse()
        }
        if resultPatches.count == resultPatches.capacity {
          let doubled = resultPatches.capacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
          let capacity = max(1, doubled.partialValue)
          try OriginalCoefficientAllocation.reserve(
            count: capacity, of: CertifiedPlanarAffineFluxTraversal.Patch.self, using: &execution)
          resultPatches.reserveCapacity(capacity)
        }
        resultPatches.append(
          CertifiedPlanarAffineFluxTraversal.Patch(
            controls: try OriginalCoefficientAllocation.map(elements: restricted, using: &execution)
            { element, execution in
              CertifiedPlanarAffineFluxTraversal.HomogeneousControl(
                x: try ScalarInterval(
                  lower: element.x.lower,
                  upper: element.x.upper
                ),
                y: try ScalarInterval(
                  lower: element.y.lower,
                  upper: element.y.upper
                ),
                weight: try ScalarInterval(
                  lower: element.weight.lower,
                  upper: element.weight.upper
                )
              )
            }
          ))
      }
    }
    guard resultPatches.isEmpty == false else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact planar flux traversal produced no active curve patches."
      )
    }
    let relative = try Self.exactDifference(plane.origin, reference, using: &execution)
    let scaleNumerator = try Self.interval(
      try Self.exactTriple(
        plane.exactU,
        plane.exactV,
        relative, using: &execution), using: &execution)
    guard
      let scale = scaleNumerator.divided(
        by: OutwardScalarInterval(3.0)
      ), scale.isFinite
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact planar flux traversal lost its finite flux scale."
      )
    }
    return CertifiedPlanarAffineFluxTraversal(
      patches: resultPatches,
      fluxScale: try ScalarInterval(lower: scale.lower, upper: scale.upper)
    )
  }

  private struct AffineHomogeneousControl {
    let x: OutwardScalarInterval
    let y: OutwardScalarInterval
    let weight: OutwardScalarInterval

    func interpolated(
      to other: AffineHomogeneousControl,
      parameter: OutwardScalarInterval
    ) -> AffineHomogeneousControl {
      let complement = OutwardScalarInterval(1.0) - parameter
      return AffineHomogeneousControl(
        x: x * complement + other.x * parameter,
        y: y * complement + other.y * parameter,
        weight: weight * complement + other.weight * parameter
      )
    }
  }

  private func affineCoordinates(
    of point: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: OutwardScalarInterval, v: OutwardScalarInterval) {
    try execution.consumeWork(1)
    let relative = try Self.exactDifference(point, plane.origin, using: &execution)
    let dotU = try Self.exactDot(relative, plane.exactU, using: &execution)
    let dotV = try Self.exactDot(relative, plane.exactV, using: &execution)
    let uNumerator = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(dotU, plane.gramVV, using: &execution),
      try FloatingPointExpansion.product(dotV, plane.gramUV, using: &execution), using: &execution)
    let vNumerator = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(dotV, plane.gramUU, using: &execution),
      try FloatingPointExpansion.product(dotU, plane.gramUV, using: &execution), using: &execution)
    let determinant = try Self.interval(plane.gramDeterminant, using: &execution)
    guard let u = try Self.interval(uNumerator, using: &execution).divided(by: determinant),
      let v = try Self.interval(vNumerator, using: &execution).divided(by: determinant),
      u.isFinite,
      v.isFinite
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact planar flux traversal lost its affine control coordinates."
      )
    }
    return (u, v)
  }

  private func restrictedControls(
    _ controls: [AffineHomogeneousControl],
    lower: Double,
    upper: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [AffineHomogeneousControl] {
    try execution.consumeWork(1)
    guard controls.count >= 2,
      lower >= 0.0,
      upper <= 1.0,
      upper > lower
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact planar flux traversal received an invalid Bezier restriction."
      )
    }
    let upperControls =
      upper == 1.0
      ? controls
      : try splitControls(
        controls,
        parameter: OutwardScalarInterval(lower: upper, upper: upper), using: &execution
      ).lower
    guard lower > 0.0 else { return upperControls }
    guard
      let normalizedLower = OutwardScalarInterval(
        lower: lower,
        upper: lower
      ).divided(by: OutwardScalarInterval(lower: upper, upper: upper))
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact planar flux traversal could not normalize its Bezier restriction."
      )
    }
    return try splitControls(
      upperControls,
      parameter: normalizedLower, using: &execution
    ).upper
  }

  private func splitControls(
    _ controls: [AffineHomogeneousControl],
    parameter: OutwardScalarInterval, using execution: inout OriginalQueryExecution
  ) throws -> (
    lower: [AffineHomogeneousControl],
    upper: [AffineHomogeneousControl]
  ) {
    try execution.consumeWork(1)
    try OriginalCoefficientAllocation.reserve(
      count: controls.count, of: [AffineHomogeneousControl].self, using: &execution)
    var levels: [[AffineHomogeneousControl]] = []
    levels.reserveCapacity(controls.count)
    levels.append(controls)
    while let previous = levels.last, previous.count > 1 {
      try execution.consumeWork(1)
      levels.append(
        try OriginalCoefficientAllocation.map(
          elements: (0..<(previous.count - 1)), using: &execution
        ) { index, execution in
          previous[index].interpolated(
            to: previous[index + 1],
            parameter: parameter
          )
        })
    }
    return (
      try OriginalCoefficientAllocation.map(elements: levels, using: &execution) {
        element, execution in element[0]
      },
      try OriginalCoefficientAllocation.map(elements: levels.reversed(), using: &execution) {
        element, execution in element[element.count - 1]
      }
    )
  }

  private static func make(
    source: SourceSurface,
    plane: ExactPlanePatch,
    sourceIsFirst: Bool, using execution: inout OriginalQueryExecution
  ) throws -> ExactIsoparametricPlanarIntersectionGraph {
    try execution.consumeWork(1)
    let fixedV = normalizedParameter(source.fixedV, in: source.surface.vDomain)
    let lowerV = normalizedParameter(source.lowerV, in: source.surface.vDomain)
    let cells = try OriginalCoefficientAllocation.map(elements: source.uSpans, using: &execution) {
      span, execution in
      try OriginalCoefficientAllocation.reserve(
        count: 8, of: (lower: Double, upper: Double).self, using: &execution)
      let sourceBounds = [
        (
          lower: normalizedParameter(span.lower, in: source.surface.uDomain),
          upper: normalizedParameter(span.upper, in: source.surface.uDomain)
        ),
        (lower: lowerV, upper: fixedV),
      ]
      let planeBounds = [
        (lower: 0.0, upper: 1.0),
        (lower: 0.0, upper: 1.0),
      ]
      return Cell(
        normalizedBounds: sourceIsFirst
          ? sourceBounds + planeBounds
          : planeBounds + sourceBounds,
        freeParameter: sourceIsFirst ? .firstU : .secondU,
        sourceULower: span.lower,
        sourceUUpper: span.upper
      )
    }
    return ExactIsoparametricPlanarIntersectionGraph(
      cells: cells,
      sourceIsFirst: sourceIsFirst,
      source: source,
      plane: plane
    )
  }

  private static func exactSourceSurface(
    _ surface: BSplineSurface3D,
    intersecting plane: ExactPlanePatch, using execution: inout OriginalQueryExecution
  ) throws -> SourceSurface? {
    try execution.consumeWork(1)
    guard surface.vDegree == 2,
      surface.vControlPointCount == 5,
      surface.vKnots.count == 8,
      try
        (OriginalCoefficientAllocation.flatten(rows: surface.weights, using: &execution).allSatisfy(
          {
            try execution.consumeWork(1)
            return $0.isFinite && $0 > 0.0
          }))
    else {
      return nil
    }
    let knots = surface.vKnots
    let lower = knots[0]
    let middle = knots[3]
    let upper = knots[5]
    guard lower.isFinite,
      middle.isFinite,
      upper.isFinite,
      lower < middle,
      middle < upper,
      knots[0] == lower,
      knots[1] == lower,
      knots[2] == lower,
      knots[3] == middle,
      knots[4] == middle,
      knots[5] == upper,
      knots[6] == upper,
      knots[7] == upper
    else {
      return nil
    }
    let signs = try OriginalCoefficientAllocation.map(
      elements: surface.controlPoints, using: &execution
    ) { row, execution in
      try OriginalCoefficientAllocation.map(elements: row, using: &execution) {
        element, execution in
        try FloatingPointExpansion.sign(
          try planeValue(element, plane: plane, using: &execution), using: &execution)
      }
    }
    let crossesForward =
      try
      (signs[0].allSatisfy({
        try execution.consumeWork(1)
        return $0 == .negative
      }))
      && (signs[1].allSatisfy({
          try execution.consumeWork(1)
          return $0 == .negative
        }))
      && (signs[3].allSatisfy({
          try execution.consumeWork(1)
          return $0 == .positive
        }))
      && (signs[4].allSatisfy({
          try execution.consumeWork(1)
          return $0 == .positive
        }))
    let crossesReverse =
      try
      (signs[0].allSatisfy({
        try execution.consumeWork(1)
        return $0 == .positive
      }))
      && (signs[1].allSatisfy({
          try execution.consumeWork(1)
          return $0 == .positive
        }))
      && (signs[3].allSatisfy({
          try execution.consumeWork(1)
          return $0 == .negative
        }))
      && (signs[4].allSatisfy({
          try execution.consumeWork(1)
          return $0 == .negative
        }))
    guard
      try
        (signs[2].allSatisfy({
          try execution.consumeWork(1)
          return $0 == .zero
        })),
      crossesForward || crossesReverse
    else {
      return nil
    }
    guard
      try
        (surface.controlPoints[2].allSatisfy({
          try execution.consumeWork(1)
          return try exactAffineCoordinatesContain($0, plane: plane, using: &execution)
        }))
    else {
      return nil
    }
    let uSpans = try nonzeroSpans(
      knots: surface.uKnots,
      degree: surface.uDegree, using: &execution)
    guard uSpans.isEmpty == false else { return nil }
    return SourceSurface(
      surface: surface,
      fixedV: middle,
      lowerV: lower,
      uSpans: uSpans
    )
  }

  private static func exactPlanePatch(
    _ surface: BSplineSurface3D, using execution: inout OriginalQueryExecution
  ) throws -> ExactPlanePatch? {
    try execution.consumeWork(1)
    guard surface.uDegree == 1,
      surface.vDegree == 1,
      surface.uControlPointCount == 2,
      surface.vControlPointCount == 2,
      isSingleLinearBezier(surface.uKnots),
      isSingleLinearBezier(surface.vKnots)
    else {
      return nil
    }
    let weights = surface.weights
    let flatWeights = try OriginalCoefficientAllocation.flatten(rows: weights, using: &execution)
    try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
    let jacobianCoefficients = [
      flatWeights[0] * flatWeights[1] * flatWeights[2],
      flatWeights[0] * flatWeights[1] * flatWeights[3],
      flatWeights[0] * flatWeights[2] * flatWeights[3],
      flatWeights[1] * flatWeights[2] * flatWeights[3],
    ]
    guard
      try
        (flatWeights.allSatisfy({
          try execution.consumeWork(1)
          return $0.isFinite && $0 > 0.0
        })),
      try
        (jacobianCoefficients.allSatisfy({
          try execution.consumeWork(1)
          return $0.isFinite && $0 > 0.0
        }))
    else {
      return nil
    }
    let p00 = surface.controlPoints[0][0]
    let p10 = surface.controlPoints[0][1]
    let p01 = surface.controlPoints[1][0]
    let p11 = surface.controlPoints[1][1]
    let exactU = try exactDifference(p10, p00, using: &execution)
    let exactV = try exactDifference(p01, p00, using: &execution)
    let parallelogramResidual = try exactDifference(
      try exactDifference(p11, p10, using: &execution),
      try exactDifference(p01, p00, using: &execution), using: &execution)
    try OriginalCoefficientAllocation.reserve(count: 3, of: [Double].self, using: &execution)
    guard
      try
        ([parallelogramResidual.x, parallelogramResidual.y, parallelogramResidual.z]
        .allSatisfy({
          try execution.consumeWork(1)
          return try FloatingPointExpansion.sign($0, using: &execution) == .zero
        }))
    else {
      return nil
    }
    let gramUU = try exactDot(exactU, exactU, using: &execution)
    let gramUV = try exactDot(exactU, exactV, using: &execution)
    let gramVV = try exactDot(exactV, exactV, using: &execution)
    let determinant = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(gramUU, gramVV, using: &execution),
      try FloatingPointExpansion.product(gramUV, gramUV, using: &execution), using: &execution)
    guard try FloatingPointExpansion.sign(determinant, using: &execution) == .positive else {
      return nil
    }
    return ExactPlanePatch(
      origin: p00,
      u: p10 - p00,
      v: p01 - p00,
      exactU: exactU,
      exactV: exactV,
      gramUU: gramUU,
      gramUV: gramUV,
      gramVV: gramVV,
      gramDeterminant: determinant,
      weights: weights
    )
  }

  private func planarParameters(
    for point: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: Double, v: Double) {
    try execution.consumeWork(1)
    let offset = point - plane.origin
    let uu = plane.u.dot(plane.u)
    let uv = plane.u.dot(plane.v)
    let vv = plane.v.dot(plane.v)
    let determinant = uu * vv - uv * uv
    guard determinant.isFinite,
      determinant > 0.0
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact isoparametric-planar graph lost its affine inverse."
      )
    }
    let offsetU = offset.dot(plane.u)
    let offsetV = offset.dot(plane.v)
    let affineU = (offsetU * vv - offsetV * uv) / determinant
    let affineV = (offsetV * uu - offsetU * uv) / determinant
    let parameters = try inversePlanarMap(
      affineU: affineU,
      affineV: affineV,
      tolerance: tolerance, using: &execution)
    let u = parameters.u
    let v = parameters.v
    guard u.isFinite,
      v.isFinite,
      u >= -tolerance.relative,
      u <= 1.0 + tolerance.relative,
      v >= -tolerance.relative,
      v <= 1.0 + tolerance.relative
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        residual: max(-u, u - 1.0, -v, v - 1.0),
        message: "An exact isoparametric-planar graph left the planar patch."
      )
    }
    return (min(max(u, 0.0), 1.0), min(max(v, 0.0), 1.0))
  }

  private func inversePlanarMap(
    affineU: Double,
    affineV: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: Double, v: Double) {
    try execution.consumeWork(1)
    var u = min(max(affineU, 0.0), 1.0)
    var v = min(max(affineV, 0.0), 1.0)
    var previousResidual = Double.infinity
    for _ in 0..<32 {
      try execution.consumeWork(1)
      let evaluation = try Self.planarMap(
        u: u,
        v: v,
        weights: plane.weights, using: &execution)
      let residualU = evaluation.u - affineU
      let residualV = evaluation.v - affineV
      let residual = hypot(residualU, residualV)
      if residual <= tolerance.relative {
        return (u, v)
      }
      let determinant =
        evaluation.du.x * evaluation.dv.y
        - evaluation.dv.x * evaluation.du.y
      guard determinant.isFinite,
        determinant > Double.leastNonzeroMagnitude
      else {
        throw Self.certificateFailure(
          tolerance: tolerance,
          residual: residual,
          message: "An exact rational planar inverse encountered a singular Jacobian."
        )
      }
      let deltaU =
        (-residualU * evaluation.dv.y
          + residualV * evaluation.dv.x) / determinant
      let deltaV =
        (-evaluation.du.x * residualV
          + evaluation.du.y * residualU) / determinant
      var accepted: (u: Double, v: Double, residual: Double)?
      var scale = 1.0
      for _ in 0..<16 {
        try execution.consumeWork(1)
        let candidateU = min(max(u + deltaU * scale, 0.0), 1.0)
        let candidateV = min(max(v + deltaV * scale, 0.0), 1.0)
        let candidate = try Self.planarMap(
          u: candidateU,
          v: candidateV,
          weights: plane.weights, using: &execution)
        let candidateResidual = hypot(
          candidate.u - affineU,
          candidate.v - affineV
        )
        if candidateResidual < residual {
          accepted = (candidateU, candidateV, candidateResidual)
          break
        }
        scale *= 0.5
      }
      guard let accepted else {
        throw Self.certificateFailure(
          tolerance: tolerance,
          residual: residual,
          message: "An exact rational planar inverse did not decrease its residual."
        )
      }
      u = accepted.u
      v = accepted.v
      previousResidual = accepted.residual
    }
    throw Self.certificateFailure(
      tolerance: tolerance,
      residual: previousResidual,
      message: "An exact rational planar inverse exceeded its iteration limit."
    )
  }

  private static func planarMap(
    u: Double,
    v: Double,
    weights: [[Double]], using execution: inout OriginalQueryExecution
  ) throws -> (u: Double, v: Double, du: Point2D, dv: Point2D) {
    try execution.consumeWork(1)
    let a = weights[0][0]
    let b = weights[0][1]
    let c = weights[1][0]
    let d = weights[1][1]
    let lowerUWeight = a * (1.0 - v) + c * v
    let upperUWeight = b * (1.0 - v) + d * v
    let lowerVWeight = a * (1.0 - u) + b * u
    let upperVWeight = c * (1.0 - u) + d * u
    let denominator = (1.0 - u) * lowerUWeight + u * upperUWeight
    let numeratorU = u * upperUWeight
    let numeratorV = v * upperVWeight
    let denominatorU = upperUWeight - lowerUWeight
    let denominatorV = upperVWeight - lowerVWeight
    let numeratorUU = upperUWeight
    let numeratorUV = u * (d - b)
    let numeratorVU = v * (d - c)
    let numeratorVV = upperVWeight
    let denominatorSquared = denominator * denominator
    return (
      numeratorU / denominator,
      numeratorV / denominator,
      Point2D(
        x: (numeratorUU * denominator - numeratorU * denominatorU)
          / denominatorSquared,
        y: (numeratorVU * denominator - numeratorV * denominatorU)
          / denominatorSquared
      ),
      Point2D(
        x: (numeratorUV * denominator - numeratorU * denominatorV)
          / denominatorSquared,
        y: (numeratorVV * denominator - numeratorV * denominatorV)
          / denominatorSquared
      )
    )
  }

  private func affineCoordinateDerivativeBounds(
    tangent: IntervalVector3DBounds,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: OutwardScalarInterval, v: OutwardScalarInterval) {
    try execution.consumeWork(1)
    let exactU = try Self.intervalVector(plane.exactU, using: &execution)
    let exactV = try Self.intervalVector(plane.exactV, using: &execution)
    let dotU =
      tangent.x * exactU.x
      + tangent.y * exactU.y
      + tangent.z * exactU.z
    let dotV =
      tangent.x * exactV.x
      + tangent.y * exactV.y
      + tangent.z * exactV.z
    let gramUU = try Self.interval(plane.gramUU, using: &execution)
    let gramUV = try Self.interval(plane.gramUV, using: &execution)
    let gramVV = try Self.interval(plane.gramVV, using: &execution)
    let determinant = try Self.interval(plane.gramDeterminant, using: &execution)
    guard determinant.lower > 0.0,
      let u = (dotU * gramVV - dotV * gramUV).divided(by: determinant),
      let v = (dotV * gramUU - dotU * gramUV).divided(by: determinant)
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact isoparametric-planar graph lost its certified affine derivative inverse."
      )
    }
    return (u, v)
  }

  private func affineCoordinateBounds(
    position: IntervalVector3DBounds,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: OutwardScalarInterval, v: OutwardScalarInterval) {
    try execution.consumeWork(1)
    let relative = IntervalVector3DBounds(
      x: position.x - OutwardScalarInterval(plane.origin.x),
      y: position.y - OutwardScalarInterval(plane.origin.y),
      z: position.z - OutwardScalarInterval(plane.origin.z)
    )
    return try affineCoordinateDerivativeBounds(
      tangent: relative,
      tolerance: tolerance, using: &execution)
  }

  private func inversePlanarMapBounds(
    affineU: OutwardScalarInterval,
    affineV: OutwardScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: OutwardScalarInterval, v: OutwardScalarInterval) {
    try execution.consumeWork(1)
    let targetU = OutwardScalarInterval(
      lower: max(0.0, affineU.lower),
      upper: min(1.0, affineU.upper)
    )
    let targetV = OutwardScalarInterval(
      lower: max(0.0, affineV.lower),
      upper: min(1.0, affineV.upper)
    )
    guard targetU.lower <= targetU.upper,
      targetV.lower <= targetV.upper
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact isoparametric-planar subcell left the affine plane domain."
      )
    }
    let targetMidpointU =
      targetU.lower
      + (targetU.upper - targetU.lower) * 0.5
    let targetMidpointV =
      targetV.lower
      + (targetV.upper - targetV.lower) * 0.5
    let center = try inversePlanarMap(
      affineU: targetMidpointU,
      affineV: targetMidpointV,
      tolerance: tolerance, using: &execution)
    let centerMap = try Self.planarMap(
      u: center.u,
      v: center.v,
      weights: plane.weights, using: &execution)
    let centerDeterminant =
      centerMap.du.x * centerMap.dv.y
      - centerMap.dv.x * centerMap.du.y
    guard centerDeterminant.isFinite,
      centerDeterminant > Double.leastNonzeroMagnitude
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact planar inverse enclosure encountered a singular midpoint Jacobian."
      )
    }
    let inverse00 = centerMap.dv.y / centerDeterminant
    let inverse01 = -centerMap.dv.x / centerDeterminant
    let inverse10 = -centerMap.du.y / centerDeterminant
    let inverse11 = centerMap.du.x / centerDeterminant
    // The positive-weight bilinear patch is a bijection from the parameter
    // square onto the affine square. Along the inverse image of the line
    // from the computed center to any target point, the inverse derivative
    // is J^-1. A global interval bound for J^-1 therefore gives a certified
    // Lipschitz box without a resolution-dependent two-dimensional search.
    let weights = try OriginalCoefficientAllocation.flatten(rows: plane.weights, using: &execution)
    let weightHull = OutwardScalarInterval.enclosing(weights)
    let a = OutwardScalarInterval(plane.weights[0][0])
    let b = OutwardScalarInterval(plane.weights[0][1])
    let c = OutwardScalarInterval(plane.weights[1][0])
    let d = OutwardScalarInterval(plane.weights[1][1])
    try OriginalCoefficientAllocation.reserve(
      count: 4, of: OutwardScalarInterval.self, using: &execution)
    let determinantNumerator = OutwardScalarInterval.enclosing([
      a * b * c,
      a * b * d,
      a * c * d,
      b * c * d,
    ])
    let maximumWeightProduct = weightHull * weightHull * weightHull
    let crossWeight = a * d - b * c
    guard determinantNumerator.lower > 0.0,
      let diagonalMagnitude = maximumWeightProduct.divided(
        by: OutwardScalarInterval(
          lower: determinantNumerator.lower,
          upper: determinantNumerator.lower.nextUp
        )
      ),
      let crossMagnitude =
        (OutwardScalarInterval(
          max(abs(crossWeight.lower), abs(crossWeight.upper))
        ) * weightHull * OutwardScalarInterval(0.25)).divided(
          by: OutwardScalarInterval(
            lower: determinantNumerator.lower,
            upper: determinantNumerator.lower.nextUp
          )
        )
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact planar inverse lost its global inverse-Jacobian bound."
      )
    }
    let targetRadiusU = max(
      abs(targetU.lower - centerMap.u),
      abs(targetU.upper - centerMap.u)
    ).nextUp
    let targetRadiusV = max(
      abs(targetV.lower - centerMap.v),
      abs(targetV.upper - centerMap.v)
    ).nextUp
    let diagonalBound = max(
      abs(diagonalMagnitude.lower),
      abs(diagonalMagnitude.upper)
    ).nextUp
    let crossBound = max(
      abs(crossMagnitude.lower),
      abs(crossMagnitude.upper)
    ).nextUp
    let uRadius =
      (diagonalBound * targetRadiusU
      + crossBound * targetRadiusV).nextUp
    let vRadius =
      (crossBound * targetRadiusU
      + diagonalBound * targetRadiusV).nextUp
    var u = OutwardScalarInterval(
      lower: max(0.0, (center.u - uRadius).nextDown),
      upper: min(1.0, (center.u + uRadius).nextUp)
    )
    var v = OutwardScalarInterval(
      lower: max(0.0, (center.v - vRadius).nextDown),
      upper: min(1.0, (center.v + vRadius).nextUp)
    )
    let one = OutwardScalarInterval(lower: 1.0, upper: 1.0)
    for _ in 0..<16 {
      try execution.consumeWork(1)
      let jacobian = try planarMapJacobianBounds(
        u: u,
        v: v,
        tolerance: tolerance, using: &execution)
      let residualU = OutwardScalarInterval(centerMap.u) - targetU
      let residualV = OutwardScalarInterval(centerMap.v) - targetV
      let baseU =
        OutwardScalarInterval(center.u)
        - OutwardScalarInterval(inverse00) * residualU
        - OutwardScalarInterval(inverse01) * residualV
      let baseV =
        OutwardScalarInterval(center.v)
        - OutwardScalarInterval(inverse10) * residualU
        - OutwardScalarInterval(inverse11) * residualV
      let remainder00 =
        one
        - OutwardScalarInterval(inverse00) * jacobian.du.x
        - OutwardScalarInterval(inverse01) * jacobian.du.y
      let remainder01 =
        -OutwardScalarInterval(inverse00) * jacobian.dv.x
        - OutwardScalarInterval(inverse01) * jacobian.dv.y
      let remainder10 =
        -OutwardScalarInterval(inverse10) * jacobian.du.x
        - OutwardScalarInterval(inverse11) * jacobian.du.y
      let remainder11 =
        one
        - OutwardScalarInterval(inverse10) * jacobian.dv.x
        - OutwardScalarInterval(inverse11) * jacobian.dv.y
      let deltaU = u - OutwardScalarInterval(center.u)
      let deltaV = v - OutwardScalarInterval(center.v)
      let candidateU = baseU + remainder00 * deltaU + remainder01 * deltaV
      let candidateV = baseV + remainder10 * deltaU + remainder11 * deltaV
      let nextU = OutwardScalarInterval(
        lower: max(u.lower, candidateU.lower, 0.0),
        upper: min(u.upper, candidateU.upper, 1.0)
      )
      let nextV = OutwardScalarInterval(
        lower: max(v.lower, candidateV.lower, 0.0),
        upper: min(v.upper, candidateV.upper, 1.0)
      )
      guard nextU.lower <= nextU.upper,
        nextV.lower <= nextV.upper
      else {
        throw Self.certificateFailure(
          tolerance: tolerance,
          message: "An exact planar inverse interval excluded its certified source curve."
        )
      }
      let improvement = max(
        (u.upper - u.lower) - (nextU.upper - nextU.lower),
        (v.upper - v.lower) - (nextV.upper - nextV.lower)
      )
      u = nextU
      v = nextV
      if improvement <= tolerance.relative { break }
    }
    return (u, v)
  }

  private func actualInterval(
    _ normalized: OutwardScalarInterval,
    in domain: ParameterDomain,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    try execution.consumeWork(1)
    guard case .closed(let lower, let upper) = domain else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact planar subcell requires a closed parameter domain."
      )
    }
    return try containingInterval(
      lower + (upper - lower) * normalized.lower,
      lower + (upper - lower) * normalized.upper,
      in: domain,
      tolerance: tolerance, using: &execution)
  }

  private func containingInterval(
    _ requestedLower: Double,
    _ requestedUpper: Double,
    in domain: ParameterDomain,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    try execution.consumeWork(1)
    guard case .closed(let domainLower, let domainUpper) = domain else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact isoparametric-planar subcell requires a closed parameter domain."
      )
    }
    let scale = max(1.0, abs(domainLower), abs(domainUpper))
    let minimumWidth = min(
      domainUpper - domainLower,
      max(
        tolerance.relative * scale * 4.0,
        Double.ulpOfOne * scale * 4_096.0
      )
    )
    var lower = max(domainLower, min(requestedLower, requestedUpper).nextDown)
    var upper = min(domainUpper, max(requestedLower, requestedUpper).nextUp)
    if upper - lower < minimumWidth {
      let midpoint = lower + (upper - lower) * 0.5
      lower = max(domainLower, midpoint - minimumWidth * 0.5)
      upper = min(domainUpper, lower + minimumWidth)
      lower = max(domainLower, upper - minimumWidth)
    }
    guard upper > lower else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message:
          "An exact isoparametric-planar subcell could not construct a positive parameter interval."
      )
    }
    return try ScalarInterval(lower: lower, upper: upper)
  }

  private func planarMapJacobianBounds(
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (
    du: (x: OutwardScalarInterval, y: OutwardScalarInterval),
    dv: (x: OutwardScalarInterval, y: OutwardScalarInterval),
    determinant: OutwardScalarInterval
  ) {
    try execution.consumeWork(1)
    return try planarMapJacobianBounds(
      u: OutwardScalarInterval(lower: 0.0, upper: 1.0),
      v: OutwardScalarInterval(lower: 0.0, upper: 1.0),
      tolerance: tolerance, using: &execution)
  }

  private func planarMapJacobianBounds(
    u: OutwardScalarInterval,
    v: OutwardScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (
    du: (x: OutwardScalarInterval, y: OutwardScalarInterval),
    dv: (x: OutwardScalarInterval, y: OutwardScalarInterval),
    determinant: OutwardScalarInterval
  ) {
    try execution.consumeWork(1)
    let one = OutwardScalarInterval(lower: 1.0, upper: 1.0)
    let a = OutwardScalarInterval(plane.weights[0][0])
    let b = OutwardScalarInterval(plane.weights[0][1])
    let c = OutwardScalarInterval(plane.weights[1][0])
    let d = OutwardScalarInterval(plane.weights[1][1])
    let lowerUWeight = a * (one - v) + c * v
    let upperUWeight = b * (one - v) + d * v
    let lowerVWeight = a * (one - u) + b * u
    let upperVWeight = c * (one - u) + d * u
    let evaluatedDenominator = (one - u) * lowerUWeight + u * upperUWeight
    let weightHull = OutwardScalarInterval.enclosing(
      try OriginalCoefficientAllocation.flatten(rows: plane.weights, using: &execution)
    )
    let denominator = OutwardScalarInterval(
      lower: max(evaluatedDenominator.lower, weightHull.lower),
      upper: min(evaluatedDenominator.upper, weightHull.upper)
    )
    let numeratorU = u * upperUWeight
    let numeratorV = v * upperVWeight
    let denominatorU = upperUWeight - lowerUWeight
    let denominatorV = upperVWeight - lowerVWeight
    let numeratorUU = upperUWeight
    let numeratorUV = u * (d - b)
    let numeratorVU = v * (d - c)
    let numeratorVV = upperVWeight
    let denominatorSquared = denominator * denominator
    guard denominator.lower > 0.0,
      let duX = (numeratorUU * denominator - numeratorU * denominatorU).divided(
        by: denominatorSquared),
      let duY = (numeratorVU * denominator - numeratorV * denominatorU).divided(
        by: denominatorSquared),
      let dvX = (numeratorUV * denominator - numeratorU * denominatorV).divided(
        by: denominatorSquared),
      let dvY = (numeratorVV * denominator - numeratorV * denominatorV).divided(
        by: denominatorSquared)
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact rational planar map lost its positive weight enclosure."
      )
    }

    try OriginalCoefficientAllocation.reserve(
      count: 4, of: OutwardScalarInterval.self, using: &execution)
    let jacobianNumerator = OutwardScalarInterval.enclosing([
      a * b * c,
      a * b * d,
      a * c * d,
      b * c * d,
    ])
    let denominatorCubed = denominatorSquared * denominator
    guard jacobianNumerator.lower > 0.0,
      let determinant = jacobianNumerator.divided(by: denominatorCubed),
      determinant.lower > 0.0
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact rational planar map lost its positive Jacobian enclosure."
      )
    }
    return (
      du: (x: duX, y: duY),
      dv: (x: dvX, y: dvY),
      determinant: determinant
    )
  }

  private static func intervalVector(
    _ value: ExpansionVector3, using execution: inout OriginalQueryExecution
  ) throws -> (
    x: OutwardScalarInterval,
    y: OutwardScalarInterval,
    z: OutwardScalarInterval
  ) {
    try execution.consumeWork(1)
    return (
      x: try interval(value.x, using: &execution),
      y: try interval(value.y, using: &execution),
      z: try interval(value.z, using: &execution)
    )
  }

  private static func interval(_ expansion: [Double], using execution: inout OriginalQueryExecution)
    throws -> OutwardScalarInterval
  {
    try execution.consumeWork(1)
    var result = OutwardScalarInterval(lower: 0.0, upper: 0.0)
    for component in expansion {
      try execution.consumeWork(1)
      result = result + OutwardScalarInterval(component)
    }
    return result
  }

  private static func domainWidth(_ domain: ParameterDomain) -> Double {
    guard case .closed(let lower, let upper) = domain else { return .nan }
    return upper - lower
  }

  private static func negated(
    _ interval: OutwardScalarInterval
  ) -> OutwardScalarInterval {
    OutwardScalarInterval(
      lower: (-interval.upper).nextDown,
      upper: (-interval.lower).nextUp
    )
  }

  private static func exactAffineCoordinatesContain(
    _ point: Point3D,
    plane: ExactPlanePatch, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    let relative = try exactDifference(point, plane.origin, using: &execution)
    let dotU = try exactDot(relative, plane.exactU, using: &execution)
    let dotV = try exactDot(relative, plane.exactV, using: &execution)
    let uNumerator = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(dotU, plane.gramVV, using: &execution),
      try FloatingPointExpansion.product(dotV, plane.gramUV, using: &execution), using: &execution)
    let vNumerator = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(dotV, plane.gramUU, using: &execution),
      try FloatingPointExpansion.product(dotU, plane.gramUV, using: &execution), using: &execution)
    return try isNonnegative(uNumerator, using: &execution)
      && isNonnegative(
        try FloatingPointExpansion.subtract(
          plane.gramDeterminant,
          uNumerator, using: &execution), using: &execution)
      && isNonnegative(vNumerator, using: &execution)
      && isNonnegative(
        try FloatingPointExpansion.subtract(
          plane.gramDeterminant,
          vNumerator, using: &execution), using: &execution)
  }

  private static func planeValue(
    _ point: Point3D,
    plane: ExactPlanePatch, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    return try exactTriple(
      plane.exactU,
      plane.exactV,
      try exactDifference(point, plane.origin, using: &execution), using: &execution)
  }

  private static func nonzeroSpans(
    knots: [Double],
    degree: Int, using execution: inout OriginalQueryExecution
  ) throws -> [(lower: Double, upper: Double)] {
    try execution.consumeWork(1)
    guard degree >= 0,
      knots.count >= 2 * (degree + 1)
    else {
      return []
    }
    let capacity = knots.count - 2 * degree - 1
    try OriginalCoefficientAllocation.reserve(
      count: capacity, of: (lower: Double, upper: Double).self, using: &execution)
    var result: [(lower: Double, upper: Double)] = []
    result.reserveCapacity(capacity)
    for index in degree..<(knots.count - degree - 1) {
      try execution.consumeWork(1)
      let lower = knots[index]
      let upper = knots[index + 1]
      if lower.isFinite,
        upper.isFinite,
        upper > lower
      {
        result.append((lower, upper))
      }
    }
    return result
  }

  private static func isSingleLinearBezier(_ knots: [Double]) -> Bool {
    guard knots.count == 4,
      let lower = knots.first,
      let upper = knots.last,
      lower.isFinite,
      upper.isFinite,
      upper > lower
    else {
      return false
    }
    return knots[0] == lower
      && knots[1] == lower
      && knots[2] == upper
      && knots[3] == upper
  }

  private static func matches(
    _ parameterBox: SurfaceIntersectionParameterBox,
    normalizedBounds: [(lower: Double, upper: Double)],
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    try OriginalCoefficientAllocation.reserve(count: 4, of: ParameterDomain.self, using: &execution)
    let domains = [first.uDomain, first.vDomain, second.uDomain, second.vDomain]
    return try
      (zip(
        parameterBox.intervals,
        zip(normalizedBounds, domains)
      ).allSatisfy { interval, expectedAndDomain in
        try execution.consumeWork(1)
        let expected = expectedAndDomain.0
        let domain = expectedAndDomain.1
        let lower = actualParameter(expected.lower, in: domain)
        let upper = actualParameter(expected.upper, in: domain)
        return abs(interval.lower - lower) <= tolerance.relative
          && abs(interval.upper - upper) <= tolerance.relative
      })
  }

  private static func normalizedParameter(
    _ actual: Double,
    in domain: ParameterDomain
  ) -> Double {
    guard case .closed(let lower, let upper) = domain else { return .nan }
    return (actual - lower) / (upper - lower)
  }

  private static func actualParameter(
    _ normalized: Double,
    in domain: ParameterDomain
  ) -> Double {
    guard case .closed(let lower, let upper) = domain else { return .nan }
    return lower + (upper - lower) * normalized
  }

  private static func exactDifference(
    _ lhs: Point3D,
    _ rhs: Point3D, using execution: inout OriginalQueryExecution
  ) throws -> ExpansionVector3 {
    try execution.consumeWork(1)
    return ExpansionVector3(
      x: try FloatingPointExpansion.difference(lhs.x, rhs.x, using: &execution),
      y: try FloatingPointExpansion.difference(lhs.y, rhs.y, using: &execution),
      z: try FloatingPointExpansion.difference(lhs.z, rhs.z, using: &execution)
    )
  }

  private static func exactDifference(
    _ lhs: ExpansionVector3,
    _ rhs: ExpansionVector3, using execution: inout OriginalQueryExecution
  ) throws -> ExpansionVector3 {
    try execution.consumeWork(1)
    return ExpansionVector3(
      x: try FloatingPointExpansion.subtract(lhs.x, rhs.x, using: &execution),
      y: try FloatingPointExpansion.subtract(lhs.y, rhs.y, using: &execution),
      z: try FloatingPointExpansion.subtract(lhs.z, rhs.z, using: &execution)
    )
  }

  private static func exactDot(
    _ lhs: ExpansionVector3,
    _ rhs: ExpansionVector3, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    return try FloatingPointExpansion.sum(
      try FloatingPointExpansion.sum(
        try FloatingPointExpansion.product(lhs.x, rhs.x, using: &execution),
        try FloatingPointExpansion.product(lhs.y, rhs.y, using: &execution), using: &execution),
      try FloatingPointExpansion.product(lhs.z, rhs.z, using: &execution), using: &execution)
  }

  private static func exactTriple(
    _ first: ExpansionVector3,
    _ second: ExpansionVector3,
    _ third: ExpansionVector3, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    let crossX = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(second.y, third.z, using: &execution),
      try FloatingPointExpansion.product(second.z, third.y, using: &execution), using: &execution)
    let crossY = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(second.z, third.x, using: &execution),
      try FloatingPointExpansion.product(second.x, third.z, using: &execution), using: &execution)
    let crossZ = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(second.x, third.y, using: &execution),
      try FloatingPointExpansion.product(second.y, third.x, using: &execution), using: &execution)
    return try FloatingPointExpansion.sum(
      try FloatingPointExpansion.sum(
        try FloatingPointExpansion.product(first.x, crossX, using: &execution),
        try FloatingPointExpansion.product(first.y, crossY, using: &execution), using: &execution),
      try FloatingPointExpansion.product(first.z, crossZ, using: &execution), using: &execution)
  }

  private static func isNonnegative(
    _ value: [Double], using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    let sign = try FloatingPointExpansion.sign(value, using: &execution)
    return sign == .positive || sign == .zero
  }

  private static func certificateFailure(
    tolerance: ModelingTolerance,
    residual: Double? = nil,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .intersectionFailure,
      residual: residual,
      tolerance: tolerance,
      message: message
    )
  }
}
