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

public struct CertifiedImplicitIntersectionGraphCell: Sendable, Hashable {
  public let parameterBox: SurfaceIntersectionParameterBox
  public let freeParameter: SurfaceIntersectionParameterCoordinate
  public let direction: CertifiedImplicitIntersectionDirection
  public let lowerAnchor: SurfaceIntersectionParameterPair
  public let midpointAnchor: SurfaceIntersectionParameterPair
  public let upperAnchor: SurfaceIntersectionParameterPair

  public init(
    parameterBox: SurfaceIntersectionParameterBox,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    direction: CertifiedImplicitIntersectionDirection,
    lowerAnchor: SurfaceIntersectionParameterPair,
    midpointAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws {
    self.parameterBox = parameterBox
    self.freeParameter = freeParameter
    self.direction = direction
    self.lowerAnchor = lowerAnchor
    self.midpointAnchor = midpointAnchor
    self.upperAnchor = upperAnchor
    try validate(
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance
    )
  }

  package init(
    parameterBox: SurfaceIntersectionParameterBox,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    direction: CertifiedImplicitIntersectionDirection,
    lowerAnchor: SurfaceIntersectionParameterPair,
    midpointAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    firstSurface preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    secondSurface preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws {
    self.parameterBox = parameterBox
    self.freeParameter = freeParameter
    self.direction = direction
    self.lowerAnchor = lowerAnchor
    self.midpointAnchor = midpointAnchor
    self.upperAnchor = upperAnchor
    try validate(
      firstSurface: preparedFirstSurface,
      secondSurface: preparedSecondSurface,
      tolerance: tolerance, admission: admission
    )
  }

  public init(
    parameterBox: SurfaceIntersectionParameterBox,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    direction: CertifiedImplicitIntersectionDirection,
    lowerAnchor: SurfaceIntersectionParameterPair,
    midpointAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    tolerance: ModelingTolerance
  ) throws {
    try self.init(
      parameterBox: parameterBox,
      freeParameter: freeParameter,
      direction: direction,
      lowerAnchor: lowerAnchor,
      midpointAnchor: midpointAnchor,
      upperAnchor: upperAnchor,
      firstSurface: .bSpline(firstSurface),
      secondSurface: .bSpline(secondSurface),
      tolerance: tolerance
    )
  }

  public func validate(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    try firstSurface.validate(tolerance: tolerance)
    try secondSurface.validate(tolerance: tolerance)
    try validateStructure(
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance
    )
    try validateGraphProof(
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      preparedFirstSurface: nil,
      preparedSecondSurface: nil,
      tolerance: tolerance
    )
  }

  package func validate(
    firstSurface preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    secondSurface preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws {
    try tolerance.validate()
    try validateStructure(
      firstSurface: preparedFirstSurface.surface,
      secondSurface: preparedSecondSurface.surface,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface,
      tolerance: tolerance, admission: admission
    )
    try validateGraphProof(
      firstSurface: preparedFirstSurface.surface,
      secondSurface: preparedSecondSurface.surface,
      preparedFirstSurface: preparedFirstSurface,
      preparedSecondSurface: preparedSecondSurface,
      tolerance: tolerance, admission: admission
    )
  }

  private func validateStructure(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws {
    try parameterBox.validate(
      first: firstSurface,
      second: secondSurface,
      tolerance: tolerance
    )
    guard parameterBox.contains(lowerAnchor),
      parameterBox.contains(midpointAnchor),
      parameterBox.contains(upperAnchor)
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "An implicit intersection graph anchor lies outside its certified parameter box."
      )
    }
    let freeInterval = parameterBox.interval(for: freeParameter)
    let freeIndex = freeParameter.rawValue
    let freeValues = [
      lowerAnchor.values[freeIndex],
      midpointAnchor.values[freeIndex],
      upperAnchor.values[freeIndex],
    ]
    let expectedValues = [freeInterval.lower, freeInterval.midpoint, freeInterval.upper]
    guard
      zip(freeValues, expectedValues).allSatisfy({ value, expected in
        abs(value - expected) <= tolerance.relative
      })
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message:
          "Implicit intersection graph anchors do not span the certified free-parameter interval."
      )
    }
    for anchor in [lowerAnchor, midpointAnchor, upperAnchor] {
      try admission.step()
      _ = try verifiedPoint(
        parameters: anchor,
        firstSurface: firstSurface,
        secondSurface: secondSurface,
        tolerance: tolerance, admission: admission,
        preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
      )
    }
  }

  public func validate(
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    tolerance: ModelingTolerance
  ) throws {
    try validate(
      firstSurface: .bSpline(firstSurface),
      secondSurface: .bSpline(secondSurface),
      tolerance: tolerance
    )
  }

  public func parameterPair(
    atNormalizedFraction fraction: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntersectionParameterPair {
    try boundedParameterPair(atNormalizedFraction: fraction, firstSurface: firstSurface,
      secondSurface: secondSurface, tolerance: tolerance, admission: .legacy)
  }

  package func boundedParameterPair(atNormalizedFraction fraction: Double,
    firstSurface: Surface3D, secondSurface: Surface3D, tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil) throws -> SurfaceIntersectionParameterPair {
    try tolerance.validate()
    guard fraction.isFinite,
      fraction >= -tolerance.relative,
      fraction <= 1.0 + tolerance.relative
    else {
      throw GeometryError.invalidDistance(fraction)
    }
    let clampedFraction = min(max(fraction, 0.0), 1.0)
    let directedFraction =
      direction == .forward
      ? clampedFraction
      : 1.0 - clampedFraction
    let preparedFirst = try preparedFirstSurface ?? admission.prepare(firstSurface, tolerance: tolerance)
    let preparedSecond = try preparedSecondSurface ?? admission.prepare(secondSurface, tolerance: tolerance)
    try admission.reserve(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
    let intervals = parameterBox.intervals
    let freeInterval = intervals[freeParameter.rawValue]
    let freeValue = freeInterval.lower + freeInterval.width * directedFraction
    try admission.reserve(count: 12, stride: MemoryLayout<Double>.stride)
    var values = initialValues(atNormalizedFraction: directedFraction)
    values[freeParameter.rawValue] = freeValue
    try admission.reserve(count: 3, stride: MemoryLayout<Int>.stride)
    let dependentIndexes = (0..<4).filter { $0 != freeParameter.rawValue }
    func isAccurate(_ residual: Double, correction: [Double]) -> Bool {
      residual <= tolerance.distance && dependentIndexes.indices.allSatisfy { index in
        abs(correction[index]) <= tolerance.relative
          * intervals[dependentIndexes[index]].width
      }
    }
    for _ in 0..<32 {
      try admission.step()
      let currentSample = try sample(
        values: values,
        firstSurface: firstSurface,
        secondSurface: secondSurface,
        tolerance: tolerance, admission: admission,
        preparedFirstSurface: preparedFirst, preparedSecondSurface: preparedSecond
      )
      if currentSample.residual == 0 {
        return try SurfaceIntersectionParameterPair(values: values)
      }
      try admission.reserve(count: 3, stride: MemoryLayout<Vector3D>.stride)
      let dependentColumns = dependentIndexes.map { currentSample.columns[$0] }
      try admission.reserve(count: 6, stride: MemoryLayout<Double>.stride)
      guard
        let delta = Self.solve(
          columns: dependentColumns,
          rightHandSide: currentSample.difference * -1.0
        )
      else {
        throw certificateFailure(
          tolerance: tolerance,
          residual: currentSample.residual,
          message:
            "A certified implicit intersection graph produced a singular numerical refinement system."
        )
      }
      var acceptedValues: [Double]?
      var scale = 1.0
      for _ in 0..<12 {
        try admission.step()
        try admission.reserve(count: 4, stride: MemoryLayout<Double>.stride)
        var candidate = values
        for index in dependentIndexes.indices {
          let parameterIndex = dependentIndexes[index]
          let interval = intervals[parameterIndex]
          candidate[parameterIndex] = min(
            max(values[parameterIndex] + delta[index] * scale, interval.lower),
            interval.upper
          )
        }
        candidate[freeParameter.rawValue] = freeValue
        if candidate == values { break }
        let candidateSample = try sample(values: candidate, firstSurface: firstSurface,
          secondSurface: secondSurface, tolerance: tolerance, admission: admission,
          preparedFirstSurface: preparedFirst, preparedSecondSurface: preparedSecond)
        if candidateSample.residual < currentSample.residual {
          acceptedValues = candidate
          break
        }
        scale *= 0.5
      }
      guard let acceptedValues else {
        if isAccurate(currentSample.residual, correction: delta) {
          return try SurfaceIntersectionParameterPair(values: values)
        }
        throw certificateFailure(
          tolerance: tolerance,
          residual: currentSample.residual,
          message: "A certified implicit intersection graph root could not be numerically refined."
        )
      }
      values = acceptedValues
    }
    let finalSample = try sample(
      values: values,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance, admission: admission,
      preparedFirstSurface: preparedFirst, preparedSecondSurface: preparedSecond
    )
    try admission.reserve(count: 3, stride: MemoryLayout<Vector3D>.stride)
    try admission.reserve(count: 6, stride: MemoryLayout<Double>.stride)
    guard let correction = Self.solve(
      columns: dependentIndexes.map { finalSample.columns[$0] },
      rightHandSide: finalSample.difference * -1.0
    ), isAccurate(finalSample.residual, correction: correction) else {
      throw certificateFailure(
        tolerance: tolerance,
        residual: finalSample.residual,
        message:
          "A certified implicit intersection graph exceeded its root-refinement iteration limit."
      )
    }
    return try SurfaceIntersectionParameterPair(values: values)
  }

  public func point(
    atNormalizedFraction fraction: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> Point3D {
    let parameters = try parameterPair(
      atNormalizedFraction: fraction,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance
    )
    return try verifiedPoint(
      parameters: parameters,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance
    )
  }

  package func point(atNormalizedFraction fraction: Double,
    firstSurface first: PreparedSurfaceDifferentialEncloser,
    secondSurface second: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws -> Point3D {
    let parameters = try boundedParameterPair(atNormalizedFraction: fraction,
      firstSurface: first.surface, secondSurface: second.surface,
      tolerance: tolerance, admission: admission,
      preparedFirstSurface: first, preparedSecondSurface: second)
    return try verifiedPoint(parameters: parameters, firstSurface: first.surface,
      secondSurface: second.surface, tolerance: tolerance, admission: admission,
      preparedFirstSurface: first, preparedSecondSurface: second)
  }

  public func differential(
    atNormalizedFraction fraction: Double,
    parameterScale: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionDifferential {
    guard parameterScale.isFinite, parameterScale > 0.0 else {
      throw GeometryError.invalidDistance(parameterScale)
    }
    let parameters = try parameterPair(
      atNormalizedFraction: fraction,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance
    )
    let values = parameters.values
    let firstGeometry = try firstSurface.parameterDerivativesThroughThirdOrder(
      u: values[0],
      v: values[1],
      tolerance: tolerance
    )
    let secondGeometry = try secondSurface.parameterDerivativesThroughThirdOrder(
      u: values[2],
      v: values[3],
      tolerance: tolerance
    )
    let solved = try secondOrderSolution(parameters: parameters,
      firstGeometry: firstGeometry.secondOrder, secondGeometry: secondGeometry.secondOrder,
      parameterScale: parameterScale, tolerance: tolerance)
    let columns = solved.columns
    let dependentIndexes = solved.dependentIndexes
    let firstParameterDerivatives = solved.firstDerivatives
    let secondParameterDerivatives = solved.secondDerivatives
    let firstSurfaceCubic = Self.composedCubicTerm(
      geometry: firstGeometry,
      firstU: firstParameterDerivatives[0],
      firstV: firstParameterDerivatives[1],
      secondU: secondParameterDerivatives[0],
      secondV: secondParameterDerivatives[1]
    )
    let secondSurfaceCubic = Self.composedCubicTerm(
      geometry: secondGeometry,
      firstU: firstParameterDerivatives[2],
      firstV: firstParameterDerivatives[3],
      secondU: secondParameterDerivatives[2],
      secondV: secondParameterDerivatives[3]
    )
    let thirdRightHandSide = (firstSurfaceCubic - secondSurfaceCubic) * -1.0
    guard
      let dependentThirdDerivatives = Self.solve(
        columns: dependentIndexes.map { columns[$0] },
        rightHandSide: thirdRightHandSide
      )
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "A certified implicit intersection graph has no regular third differential."
      )
    }
    var thirdParameterDerivatives = Array(repeating: 0.0, count: 4)
    for index in dependentIndexes.indices {
      thirdParameterDerivatives[dependentIndexes[index]] = dependentThirdDerivatives[index]
    }

    let firstSpatialThirdDerivative =
      firstGeometry.tangentU
      * thirdParameterDerivatives[0]
      + firstGeometry.tangentV * thirdParameterDerivatives[1]
      + firstSurfaceCubic
    let secondSpatialThirdDerivative =
      secondGeometry.tangentU
      * thirdParameterDerivatives[2]
      + secondGeometry.tangentV * thirdParameterDerivatives[3]
      + secondSurfaceCubic
    let thirdDerivativeResidual = (firstSpatialThirdDerivative - secondSpatialThirdDerivative)
      .length
    let thirdDerivativeScale = max(
      max(
        firstSpatialThirdDerivative.length,
        secondSpatialThirdDerivative.length
      ),
      1.0
    )
    guard
      thirdDerivativeResidual
        <= tolerance.relative * thirdDerivativeScale
    else {
      throw certificateFailure(
        tolerance: tolerance,
        residual: thirdDerivativeResidual / thirdDerivativeScale,
        message:
          "A certified implicit intersection differential has inconsistent dual-surface third derivatives."
      )
    }
    return CertifiedImplicitIntersectionDifferential(
      position: solved.differential.position,
      firstDerivative: solved.differential.firstDerivative,
      secondDerivative: solved.differential.secondDerivative,
      thirdDerivative: (firstSpatialThirdDerivative + secondSpatialThirdDerivative) * 0.5,
      parameters: parameters,
      firstParameterDerivatives: solved.differential.firstParameterDerivatives,
      secondParameterDerivatives: solved.differential.secondParameterDerivatives,
      thirdParameterDerivatives: try SurfaceIntersectionParameterVector(values: thirdParameterDerivatives)
    )
  }

  func secondOrderDifferential(
    atNormalizedFraction fraction: Double,
    parameterScale: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionDifferential.SecondOrder {
    guard parameterScale.isFinite, parameterScale > 0 else {
      throw GeometryError.invalidDistance(parameterScale)
    }
    let parameters = try parameterPair(atNormalizedFraction: fraction,
      firstSurface: firstSurface, secondSurface: secondSurface, tolerance: tolerance)
    return try secondOrderSolution(parameters: parameters,
      firstGeometry: firstSurface.parameterDerivatives(
        u: parameters.first.u, v: parameters.first.v, tolerance: tolerance),
      secondGeometry: secondSurface.parameterDerivatives(
        u: parameters.second.u, v: parameters.second.v, tolerance: tolerance),
      parameterScale: parameterScale, tolerance: tolerance).differential
  }

  private func secondOrderSolution(
    parameters: SurfaceIntersectionParameterPair,
    firstGeometry: SurfaceParameterDerivatives,
    secondGeometry: SurfaceParameterDerivatives,
    parameterScale: Double,
    tolerance: ModelingTolerance
  ) throws -> (
    differential: CertifiedImplicitIntersectionDifferential.SecondOrder,
    columns: [Vector3D], dependentIndexes: [Int],
    firstDerivatives: [Double], secondDerivatives: [Double]
  ) {
    let columns = [
      firstGeometry.tangentU,
      firstGeometry.tangentV,
      secondGeometry.tangentU * -1.0,
      secondGeometry.tangentV * -1.0,
    ]
    let freeIndex = freeParameter.rawValue
    let dependentIndexes = SurfaceIntersectionParameterCoordinate.allCases
      .map({ $0.rawValue })
      .filter { $0 != freeIndex }
    var firstParameterDerivatives = Array(repeating: 0.0, count: 4)
    firstParameterDerivatives[freeIndex] =
      parameterBox
      .interval(for: freeParameter).width
      * parameterScale
      * (direction == .forward ? 1.0 : -1.0)
    let firstRightHandSide =
      columns[freeIndex]
      * -firstParameterDerivatives[freeIndex]
    guard
      let dependentFirstDerivatives = Self.solve(
        columns: dependentIndexes.map { columns[$0] },
        rightHandSide: firstRightHandSide
      )
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "A certified implicit intersection graph has no regular first differential."
      )
    }
    for index in dependentIndexes.indices {
      firstParameterDerivatives[dependentIndexes[index]] = dependentFirstDerivatives[index]
    }

    let firstSurfaceQuadratic =
      firstGeometry.secondDerivativeUU
      * (firstParameterDerivatives[0] * firstParameterDerivatives[0])
      + firstGeometry.secondDerivativeUV
      * (2.0 * firstParameterDerivatives[0] * firstParameterDerivatives[1])
      + firstGeometry.secondDerivativeVV
      * (firstParameterDerivatives[1] * firstParameterDerivatives[1])
    let secondSurfaceQuadratic =
      secondGeometry.secondDerivativeUU
      * (firstParameterDerivatives[2] * firstParameterDerivatives[2])
      + secondGeometry.secondDerivativeUV
      * (2.0 * firstParameterDerivatives[2] * firstParameterDerivatives[3])
      + secondGeometry.secondDerivativeVV
      * (firstParameterDerivatives[3] * firstParameterDerivatives[3])
    let secondRightHandSide = (firstSurfaceQuadratic - secondSurfaceQuadratic) * -1.0
    guard
      let dependentSecondDerivatives = Self.solve(
        columns: dependentIndexes.map { columns[$0] },
        rightHandSide: secondRightHandSide
      )
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "A certified implicit intersection graph has no regular second differential."
      )
    }
    var secondParameterDerivatives = Array(repeating: 0.0, count: 4)
    for index in dependentIndexes.indices {
      secondParameterDerivatives[dependentIndexes[index]] = dependentSecondDerivatives[index]
    }

    let firstPoint = firstGeometry.position
    let secondPoint = secondGeometry.position
    let residual = (firstPoint - secondPoint).length
    guard residual <= tolerance.distance else {
      throw certificateFailure(
        tolerance: tolerance,
        residual: residual,
        message:
          "A certified implicit intersection differential failed dual-surface residual verification."
      )
    }
    let firstSpatialDerivative =
      firstGeometry.tangentU * firstParameterDerivatives[0]
      + firstGeometry.tangentV * firstParameterDerivatives[1]
    let secondSpatialFirstDerivative =
      secondGeometry.tangentU * firstParameterDerivatives[2]
      + secondGeometry.tangentV * firstParameterDerivatives[3]
    let firstDerivativeResidual = (firstSpatialDerivative - secondSpatialFirstDerivative).length
    let firstDerivativeScale = max(
      max(firstSpatialDerivative.length, secondSpatialFirstDerivative.length),
      Double.leastNonzeroMagnitude
    )
    guard firstDerivativeResidual <= tolerance.relative * firstDerivativeScale else {
      throw certificateFailure(
        tolerance: tolerance,
        residual: firstDerivativeResidual / firstDerivativeScale,
        message:
          "A certified implicit intersection differential has inconsistent dual-surface tangents."
      )
    }
    let secondSpatialDerivative =
      firstGeometry.tangentU * secondParameterDerivatives[0]
      + firstGeometry.tangentV * secondParameterDerivatives[1]
      + firstSurfaceQuadratic
    let secondSpatialSecondDerivative =
      secondGeometry.tangentU * secondParameterDerivatives[2]
      + secondGeometry.tangentV * secondParameterDerivatives[3]
      + secondSurfaceQuadratic
    let secondDerivativeResidual = (secondSpatialDerivative - secondSpatialSecondDerivative).length
    let secondDerivativeScale = max(
      max(secondSpatialDerivative.length, secondSpatialSecondDerivative.length),
      1.0
    )
    guard secondDerivativeResidual <= tolerance.relative * secondDerivativeScale else {
      throw certificateFailure(
        tolerance: tolerance,
        residual: secondDerivativeResidual / secondDerivativeScale,
        message:
          "A certified implicit intersection differential has inconsistent dual-surface curvature."
      )
    }
    let differential = CertifiedImplicitIntersectionDifferential.SecondOrder(
      position: Point3D(x: (firstPoint.x + secondPoint.x) * 0.5,
        y: (firstPoint.y + secondPoint.y) * 0.5, z: (firstPoint.z + secondPoint.z) * 0.5),
      firstDerivative: (firstSpatialDerivative + secondSpatialFirstDerivative) * 0.5,
      secondDerivative: (secondSpatialDerivative + secondSpatialSecondDerivative) * 0.5,
      parameters: parameters,
      firstParameterDerivatives: try SurfaceIntersectionParameterVector(values: firstParameterDerivatives),
      secondParameterDerivatives: try SurfaceIntersectionParameterVector(values: secondParameterDerivatives))
    return (differential, columns, dependentIndexes, firstParameterDerivatives, secondParameterDerivatives)
  }

  package func parameterDerivativeBounds(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws -> [ScalarInterval] {
    try resolvedParameterDerivativeBounds(
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      preparedFirstSurface: nil,
      preparedSecondSurface: nil,
      tolerance: tolerance, admission: admission
    )
  }

  package func parameterDerivativeBounds(
    firstSurface preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    secondSurface preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws -> [ScalarInterval] {
    try resolvedParameterDerivativeBounds(
      firstSurface: preparedFirstSurface.surface,
      secondSurface: preparedSecondSurface.surface,
      preparedFirstSurface: preparedFirstSurface,
      preparedSecondSurface: preparedSecondSurface,
      tolerance: tolerance, admission: admission
    )
  }

  private func resolvedParameterDerivativeBounds(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser?,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser?,
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws -> [ScalarInterval] {
    try tolerance.validate(); try admission.step()
    // Structural certificates own their derivative contract. Resolving one
    // before constructing the generic difference patch avoids rebuilding
    // and decomposing both source surfaces for every restricted subcell.
    let normalizedBounds: [ScalarInterval]?
    if !admission.usesCallerAccounting, case .bSpline(let firstBSpline) = firstSurface,
      case .bSpline(let secondBSpline) = secondSurface
    {
      if let exactGraph = try ExactIsoparametricPlanarIntersectionGraph.certified(
        first: firstBSpline,
        second: secondBSpline,
        tolerance: tolerance
      ),
        let exactBounds = try exactGraph.parameterDerivativeBounds(
          parameterBox: parameterBox,
          freeParameter: freeParameter,
          direction: direction,
          lowerAnchor: lowerAnchor,
          midpointAnchor: midpointAnchor,
          upperAnchor: upperAnchor,
          first: firstBSpline,
          second: secondBSpline,
          tolerance: tolerance
        )
      {
        return exactBounds
      }
      normalizedBounds = try differencePatch(
        firstSurface: firstBSpline,
        secondSurface: secondBSpline,
        tolerance: tolerance
      ).normalizedGraphParameterDerivativeBounds(
        freeParameterIndex: freeParameter.rawValue
      )
    } else {
      let prover: ParametricSurfaceIntersectionGraphProver
      if let preparedFirstSurface, let preparedSecondSurface {
        prover = try ParametricSurfaceIntersectionGraphProver(
          firstSurface: preparedFirstSurface,
          secondSurface: preparedSecondSurface,
          parameterBox: parameterBox,
          tolerance: tolerance, admission: admission
        )
      } else {
        prover = try ParametricSurfaceIntersectionGraphProver(
          firstSurface: firstSurface,
          secondSurface: secondSurface,
          parameterBox: parameterBox,
          tolerance: tolerance, admission: admission
        )
      }
      normalizedBounds = try prover.normalizedGraphParameterDerivativeBounds(
        freeParameter: freeParameter
      )
    }
    guard let normalizedBounds else {
      throw certificateFailure(
        tolerance: tolerance,
        message:
          "An implicit intersection graph has no finite interval parameter derivative enclosure."
      )
    }
    let traversalSign = OutwardScalarInterval.exact(direction == .forward ? 1.0 : -1.0)
    try admission.reserve(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
    let intervals = parameterBox.intervals
    guard normalizedBounds.count == intervals.count else {
      throw certificateFailure(tolerance: tolerance, message: "Original graph derivative coordinate count is invalid.")
    }
    try admission.reserve(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
    return try zip(normalizedBounds, intervals).map { normalized, parameterInterval in
      try admission.step()
      let width = OutwardScalarInterval.exact(parameterInterval.upper) - .exact(parameterInterval.lower)
      let result = OutwardScalarInterval(lower: normalized.lower, upper: normalized.upper)
        * width * traversalSign
      guard result.isFinite else {
        throw certificateFailure(tolerance: tolerance,
          message: "Original intersection parameter derivative has no finite outward enclosure.")
      }
      return try ScalarInterval(lower: result.lower, upper: result.upper)
    }
  }

  private func validateGraphProof(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser?,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser?,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws {
    try admission.step()
    if !admission.usesCallerAccounting, case .bSpline(let firstBSpline) = firstSurface,
      case .bSpline(let secondBSpline) = secondSurface
    {
      if let exactGraph = try ExactAffineBilinearIntersectionGraph.certified(
        first: firstBSpline,
        second: secondBSpline,
        tolerance: tolerance
      ),
        try exactGraph.certifies(
          parameterBox: parameterBox,
          freeParameter: freeParameter,
          lowerAnchor: lowerAnchor,
          midpointAnchor: midpointAnchor,
          upperAnchor: upperAnchor,
          first: firstBSpline,
          second: secondBSpline,
          tolerance: tolerance
        )
      {
        return
      }
      if let exactGraphs = try ExactIsoparametricPlanarIntersectionGraph.certified(
        first: firstBSpline,
        second: secondBSpline,
        tolerance: tolerance
      ),
        try exactGraphs.certifies(
          parameterBox: parameterBox,
          freeParameter: freeParameter,
          lowerAnchor: lowerAnchor,
          midpointAnchor: midpointAnchor,
          upperAnchor: upperAnchor,
          first: firstBSpline,
          second: secondBSpline,
          tolerance: tolerance
        )
      {
        return
      }
      let difference = try differencePatch(
        firstSurface: firstBSpline,
        secondSurface: secondBSpline,
        tolerance: tolerance
      )
      if difference.gaugeRootCertificate(
        freeParameterIndex: freeParameter.rawValue
      ) == .fullGraph(freeParameterIndex: freeParameter.rawValue) {
        return
      }
      let intervals = parameterBox.intervals
      let normalizedLowerAnchor = zip(lowerAnchor.values, intervals).map {
        value, interval in
        (value - interval.lower) / interval.width
      }
      let normalizedUpperAnchor = zip(upperAnchor.values, intervals).map {
        value, interval in
        (value - interval.lower) / interval.width
      }
      let reproducedCertificate = difference.affinePredictorGaugeRootCertificate(
        freeParameterIndex: freeParameter.rawValue,
        lowerAnchor: normalizedLowerAnchor,
        upperAnchor: normalizedUpperAnchor
      )
      if reproducedCertificate
        == .fullGraph(freeParameterIndex: freeParameter.rawValue)
      {
        return
      }
      let predictorDiagnostic = difference.affinePredictorProofDiagnostic(
        freeParameterIndex: freeParameter.rawValue,
        lowerAnchor: normalizedLowerAnchor,
        upperAnchor: normalizedUpperAnchor
      )
      throw certificateFailure(
        tolerance: tolerance,
        message:
          "The stored implicit intersection cell reproduced \(reproducedCertificate) instead of a full-graph Krawczyk or exact structural proof. Parameter widths: \(parameterBox.intervals.map({ $0.width })). Predictor: \(predictorDiagnostic)."
      )
    }
    let prover: ParametricSurfaceIntersectionGraphProver
    if let preparedFirstSurface, let preparedSecondSurface {
      prover = try ParametricSurfaceIntersectionGraphProver(
        firstSurface: preparedFirstSurface,
        secondSurface: preparedSecondSurface,
        parameterBox: parameterBox,
        tolerance: tolerance, admission: admission
      )
    } else {
      prover = try ParametricSurfaceIntersectionGraphProver(
        firstSurface: firstSurface,
        secondSurface: secondSurface,
        parameterBox: parameterBox,
        tolerance: tolerance, admission: admission
      )
    }
    if case .fullGraph = try prover.parameterizedGraphCertificate(
      freeParameter: freeParameter,
      tolerance: tolerance
    ) {
      return
    }
    let reproducedCertificate = try prover.affinePredictorCertificate(
      freeParameter: freeParameter,
      lowerAnchor: lowerAnchor,
      upperAnchor: upperAnchor,
      tolerance: tolerance
    )
    if reproducedCertificate == .fullGraph {
      return
    }
    let predictorDiagnostic = try prover.diagnostic(
      freeParameter: freeParameter,
      lowerAnchor: lowerAnchor,
      upperAnchor: upperAnchor,
      tolerance: tolerance
    )
    throw certificateFailure(
      tolerance: tolerance,
      message:
        "The stored parametric-surface intersection cell reproduced \(reproducedCertificate) instead of a full-graph interval Krawczyk proof. Parameter widths: \(parameterBox.intervals.map({ $0.width })). Predictor: \(predictorDiagnostic)."
    )
  }

  private func differencePatch(
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    tolerance: ModelingTolerance
  ) throws -> RationalBezierSurfaceSurfaceDifferencePatch {
    let trimmedFirst = try firstSurface.trimmed(
      uFrom: parameterBox.firstU.lower,
      uTo: parameterBox.firstU.upper,
      vFrom: parameterBox.firstV.lower,
      vTo: parameterBox.firstV.upper,
      tolerance: tolerance
    )
    let trimmedSecond = try secondSurface.trimmed(
      uFrom: parameterBox.secondU.lower,
      uTo: parameterBox.secondU.upper,
      vFrom: parameterBox.secondV.lower,
      vTo: parameterBox.secondV.upper,
      tolerance: tolerance
    )
    let decomposer = BSplineSurfaceBezierDecomposer()
    let firstPatches = try decomposer.surfacePatches(
      surface: trimmedFirst,
      tolerance: tolerance
    )
    let secondPatches = try decomposer.surfacePatches(
      surface: trimmedSecond,
      tolerance: tolerance
    )
    guard firstPatches.count == 1,
      secondPatches.count == 1
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message:
          "An implicit intersection graph cell must remain inside one Bezier span on each surface."
      )
    }
    return try RationalBezierSurfaceSurfaceDifferencePatch(
      first: firstPatches[0],
      second: secondPatches[0],
      tolerance: tolerance
    )
  }

  public var startAnchor: SurfaceIntersectionParameterPair {
    direction == .forward ? lowerAnchor : upperAnchor
  }

  public var endAnchor: SurfaceIntersectionParameterPair {
    direction == .forward ? upperAnchor : lowerAnchor
  }

  private func verifiedPoint(
    parameters: SurfaceIntersectionParameterPair,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission = .legacy,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil
  ) throws -> Point3D {
    let first = try admission.positionBounds(preparedFirstSurface ?? admission.prepare(firstSurface, tolerance: tolerance),
      at: parameters.first, tolerance: tolerance)
    let second = try admission.positionBounds(preparedSecondSurface ?? admission.prepare(secondSurface, tolerance: tolerance),
      at: parameters.second, tolerance: tolerance)
    func midpoint(_ a: OutwardScalarInterval, _ b: OutwardScalarInterval) throws -> Double {
      try ScalarInterval(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper)).midpoint
    }
    let candidate = try Point3D(x: midpoint(first.x, second.x),
      y: midpoint(first.y, second.y), z: midpoint(first.z, second.z))
    try candidate.validate()
    let original = IntervalVector3DBounds(x: .exact(candidate.x),
      y: .exact(candidate.y), z: .exact(candidate.z))
    let residual = max((first - second).lengthUpperBound,
      (first - original).lengthUpperBound, (second - original).lengthUpperBound)
    guard residual.isFinite, residual <= tolerance.distance else {
      throw certificateFailure(tolerance: tolerance, residual: residual,
        message: "Original closed support positions cannot certify the implicit point residual.")
    }
    return candidate
  }

  private func initialValues(atNormalizedFraction fraction: Double) -> [Double] {
    if fraction <= 0.5 {
      return Self.interpolate(
        lowerAnchor.values,
        midpointAnchor.values,
        fraction: fraction * 2.0
      )
    }
    return Self.interpolate(
      midpointAnchor.values,
      upperAnchor.values,
      fraction: (fraction - 0.5) * 2.0
    )
  }

  private func sample(
    values: [Double],
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission = .legacy,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil
  ) throws -> (difference: Vector3D, residual: Double, columns: [Vector3D]) {
    let firstGeometry = try admission.numericalSample(preparedFirstSurface ?? admission.prepare(firstSurface, tolerance: tolerance),
      at: SurfaceParameter(u: values[0], v: values[1]), tolerance: tolerance)
    let secondGeometry = try admission.numericalSample(preparedSecondSurface ?? admission.prepare(secondSurface, tolerance: tolerance),
      at: SurfaceParameter(u: values[2], v: values[3]), tolerance: tolerance)
    let difference = firstGeometry.position - secondGeometry.position
    try admission.reserve(count: 4, stride: MemoryLayout<Vector3D>.stride)
    return (difference, difference.length, [firstGeometry.derivativeU, firstGeometry.derivativeV,
      secondGeometry.derivativeU * -1, secondGeometry.derivativeV * -1])
  }

  package func connectionSource(atEnd: Bool, first: PreparedSurfaceDifferentialEncloser,
    second: PreparedSurfaceDifferentialEncloser, tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission) throws -> (first: IntervalVector3DBounds,
      second: IntervalVector3DBounds, tangent: IntervalVector3DBounds,
      parameters: [ScalarInterval]) {
    try admission.step()
    let prover = try ParametricSurfaceIntersectionGraphProver(firstSurface: first,
      secondSurface: second, parameterBox: parameterBox, tolerance: tolerance, admission: admission)
    let fraction = (atEnd == (direction == .forward)) ? 1.0 : 0.0
    guard let root = try prover.gaugeParameterBounds(freeParameter: freeParameter,
      atNormalizedFraction: fraction, tolerance: tolerance) else {
      throw certificateFailure(tolerance: tolerance,
        message: "Original graph endpoint requires its unique closed gauge root enclosure.")
    }
    let a = try admission.intervalJet(first,
      over: .init(u: root[0], v: root[1]), tolerance: tolerance)
    let b = try admission.intervalJet(second,
      over: .init(u: root[2], v: root[3]), tolerance: tolerance)
    let endpointProver = ParametricSurfaceIntersectionGraphProver(firstSurface: first.surface,
      secondSurface: second.surface, parameterBox: parameterBox, firstJet: a, secondJet: b,
      admission: admission, preparedFirstSurface: first, preparedSecondSurface: second)
    guard let velocity = try endpointProver.normalizedGraphParameterDerivativeBounds(freeParameter: freeParameter) else {
      throw certificateFailure(tolerance: tolerance,
        message: "Original graph endpoint tangent has no regular closed derivative enclosure.")
    }
    func component(_ jet: SurfaceIntervalVectorJet,
      _ key: (SurfaceIntervalJet) -> OutwardScalarInterval) -> IntervalVector3DBounds {
      .init(x: key(jet.x), y: key(jet.y), z: key(jet.z))
    }
    let sign = OutwardScalarInterval.exact(direction == .forward ? 1 : -1)
    let uScale = (OutwardScalarInterval.exact(parameterBox.firstU.upper) - .exact(parameterBox.firstU.lower)) * sign
    let vScale = (OutwardScalarInterval.exact(parameterBox.firstV.upper) - .exact(parameterBox.firstV.lower)) * sign
    let du = OutwardScalarInterval(lower: velocity[0].lower, upper: velocity[0].upper) * uScale
    let dv = OutwardScalarInterval(lower: velocity[1].lower, upper: velocity[1].upper) * vScale
    return (component(a, { $0.value }), component(b, { $0.value }),
      component(a, { $0.derivativeU }) * du + component(a, { $0.derivativeV }) * dv,
      root)
  }

  package func connectionTangent(atEnd: Bool, first: PreparedSurfaceDifferentialEncloser,
    second: PreparedSurfaceDifferentialEncloser, tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission) throws -> Vector3D {
    let parameters = try boundedParameterPair(atNormalizedFraction: atEnd ? 1 : 0,
      firstSurface: first.surface, secondSurface: second.surface, tolerance: tolerance,
      admission: admission, preparedFirstSurface: first, preparedSecondSurface: second)
    let source = try sample(values: parameters.values, firstSurface: first.surface,
      secondSurface: second.surface, tolerance: tolerance, admission: admission,
      preparedFirstSurface: first, preparedSecondSurface: second)
    let free = freeParameter.rawValue
    let dependent = (0..<4).filter { $0 != free }
    guard let solution = Self.solve(columns: dependent.map { source.columns[$0] },
      rightHandSide: source.columns[free] * -1) else {
      throw certificateFailure(tolerance: tolerance, message: "Original graph connection has a singular candidate derivative system.")
    }
    var velocities = Array(repeating: 0.0, count: 4); velocities[free] = 1
    for index in dependent.indices { try admission.step(); velocities[dependent[index]] = solution[index] }
    return (source.columns[0] * velocities[0] + source.columns[1] * velocities[1])
      * (parameterBox.interval(for: freeParameter).width * (direction == .forward ? 1 : -1))
  }

  private static func solve(
    columns: [Vector3D],
    rightHandSide: Vector3D
  ) -> [Double]? {
    guard columns.count == 3 else { return nil }
    let cross = columns[1].cross(columns[2])
    let determinant = columns[0].dot(cross)
    let scale = columns.map({ $0.length }).max() ?? .infinity
    let floor = max(
      scale * scale * scale * Double.ulpOfOne * 1_024.0,
      Double.leastNonzeroMagnitude
    )
    guard determinant.isFinite,
      scale.isFinite,
      abs(determinant) > floor
    else {
      return nil
    }
    return [
      rightHandSide.dot(cross) / determinant,
      columns[0].dot(rightHandSide.cross(columns[2])) / determinant,
      columns[0].dot(columns[1].cross(rightHandSide)) / determinant,
    ]
  }

  private static func composedCubicTerm(
    geometry: SurfaceParameterThirdOrderDerivatives,
    firstU: Double,
    firstV: Double,
    secondU: Double,
    secondV: Double
  ) -> Vector3D {
    geometry.thirdDerivativeUUU * (firstU * firstU * firstU)
      + geometry.thirdDerivativeUUV
      * (3.0 * firstU * firstU * firstV)
      + geometry.thirdDerivativeUVV
      * (3.0 * firstU * firstV * firstV)
      + geometry.thirdDerivativeVVV * (firstV * firstV * firstV)
      + geometry.secondDerivativeUU * (3.0 * firstU * secondU)
      + geometry.secondDerivativeUV
      * (3.0 * (secondU * firstV + firstU * secondV))
      + geometry.secondDerivativeVV * (3.0 * firstV * secondV)
  }

  private static func interpolate(
    _ lower: [Double],
    _ upper: [Double],
    fraction: Double
  ) -> [Double] {
    zip(lower, upper).map { lowerValue, upperValue in
      lowerValue + (upperValue - lowerValue) * fraction
    }
  }

  private func certificateFailure(
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

extension CertifiedImplicitIntersectionGraphCell {
  public func parameterPair(
    atNormalizedFraction fraction: Double,
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntersectionParameterPair {
    try parameterPair(
      atNormalizedFraction: fraction,
      firstSurface: .bSpline(firstSurface),
      secondSurface: .bSpline(secondSurface),
      tolerance: tolerance
    )
  }

  public func point(
    atNormalizedFraction fraction: Double,
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    tolerance: ModelingTolerance
  ) throws -> Point3D {
    try point(
      atNormalizedFraction: fraction,
      firstSurface: .bSpline(firstSurface),
      secondSurface: .bSpline(secondSurface),
      tolerance: tolerance
    )
  }

  public func differential(
    atNormalizedFraction fraction: Double,
    parameterScale: Double,
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionDifferential {
    try differential(
      atNormalizedFraction: fraction,
      parameterScale: parameterScale,
      firstSurface: .bSpline(firstSurface),
      secondSurface: .bSpline(secondSurface),
      tolerance: tolerance
    )
  }
}

extension CertifiedImplicitIntersectionGraphCell {
  package func parameterDerivativeBounds(
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    tolerance: ModelingTolerance
  ) throws -> [ScalarInterval] {
    try parameterDerivativeBounds(
      firstSurface: .bSpline(firstSurface),
      secondSurface: .bSpline(secondSurface),
      tolerance: tolerance
    )
  }
}
