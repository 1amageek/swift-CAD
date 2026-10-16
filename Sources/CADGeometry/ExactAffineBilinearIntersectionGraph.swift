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

/// An exact graph certificate for an affine bilinear patch intersecting a rational bilinear patch.
///
/// The certificate is deliberately structural. It is available only when one operand is an exact
/// affine parallelogram and the other operand's plane equation has one sign on each side of a
/// parameter direction. The latter proves one and only one dependent parameter for every free
/// parameter. Exact expansion signs also prove that the resulting rational quadratic curve remains
/// inside the affine patch.
struct ExactAffineBilinearIntersectionGraph: Sendable {
  enum PlaneRelation: Sendable, Equatable {
    case coincident
    case disjoint
    case transverse
  }

  private struct ExpansionVector3 {
    let x: [Double]
    let y: [Double]
    let z: [Double]
  }

  private struct HomogeneousExpansion {
    let x: [Double]
    let y: [Double]
    let z: [Double]
    let weight: [Double]

    func scaled(by scalar: [Double], using execution: inout OriginalQueryExecution) throws
      -> HomogeneousExpansion
    {
      try execution.consumeWork(1)
      return HomogeneousExpansion(
        x: try FloatingPointExpansion.product(x, scalar, using: &execution),
        y: try FloatingPointExpansion.product(y, scalar, using: &execution),
        z: try FloatingPointExpansion.product(z, scalar, using: &execution),
        weight: try FloatingPointExpansion.product(weight, scalar, using: &execution)
      )
    }

    func adding(_ other: HomogeneousExpansion, using execution: inout OriginalQueryExecution) throws
      -> HomogeneousExpansion
    {
      try execution.consumeWork(1)
      return HomogeneousExpansion(
        x: try FloatingPointExpansion.sum(x, other.x, using: &execution),
        y: try FloatingPointExpansion.sum(y, other.y, using: &execution),
        z: try FloatingPointExpansion.sum(z, other.z, using: &execution),
        weight: try FloatingPointExpansion.sum(weight, other.weight, using: &execution)
      )
    }

    func subtracting(_ other: HomogeneousExpansion, using execution: inout OriginalQueryExecution)
      throws -> HomogeneousExpansion
    {
      try execution.consumeWork(1)
      return HomogeneousExpansion(
        x: try FloatingPointExpansion.subtract(x, other.x, using: &execution),
        y: try FloatingPointExpansion.subtract(y, other.y, using: &execution),
        z: try FloatingPointExpansion.subtract(z, other.z, using: &execution),
        weight: try FloatingPointExpansion.subtract(weight, other.weight, using: &execution)
      )
    }
  }

  enum BoundedIntersection: Sendable {
    case disjoint
    case point(SurfaceIntersectionParameterPair)
    case segment(ExactAffineBilinearIntersectionGraph)
  }

  private struct ExactRatio {
    let numerator: [Double]
    let denominator: [Double]

    init?(numerator: [Double], denominator: [Double], using execution: inout OriginalQueryExecution)
      throws
    {
      switch try FloatingPointExpansion.sign(denominator, using: &execution) {
      case .positive:
        self.numerator = numerator
        self.denominator = denominator
      case .negative:
        self.numerator = try OriginalCoefficientAllocation.map(
          elements: numerator, using: &execution
        ) { element, execution in -element }
        self.denominator = try OriginalCoefficientAllocation.map(
          elements: denominator, using: &execution
        ) { element, execution in -element }
      case .zero, .indeterminate:
        return nil
      }
    }

    func compared(to other: ExactRatio, using execution: inout OriginalQueryExecution) throws
      -> RobustSign
    {
      try execution.consumeWork(1)
      return try FloatingPointExpansion.sign(
        try FloatingPointExpansion.subtract(
          try FloatingPointExpansion.product(numerator, other.denominator, using: &execution),
          try FloatingPointExpansion.product(other.numerator, denominator, using: &execution),
          using: &execution), using: &execution)
    }

    func estimate(using execution: inout OriginalQueryExecution) throws -> Double {
      try FloatingPointExpansion.estimate(numerator, using: &execution)
        / FloatingPointExpansion.estimate(denominator, using: &execution)
    }
  }

  private struct SectionEndpoint {
    let point: HomogeneousExpansion
    let coordinate: ExactRatio
  }

  private struct AffinePatch {
    let surface: BSplineSurface3D
    let origin: Point3D
    let u: Vector3D
    let v: Vector3D
    let exactU: ExpansionVector3
    let exactV: ExpansionVector3
    let gramUU: [Double]
    let gramUV: [Double]
    let gramVV: [Double]
    let gramDeterminant: [Double]
  }

  private struct CandidateGraph {
    let affineIsFirst: Bool
    let freeIsU: Bool
    let affine: AffinePatch
    let candidate: BSplineSurface3D
    let lowerPlaneValues: [Double]
    let upperPlaneValues: [Double]
  }

  private enum Mapping: Sendable {
    case candidate(CandidateGraph)
    case affineSegment(
      lower: SurfaceIntersectionParameterPair,
      upper: SurfaceIntersectionParameterPair
    )
  }

  let freeParameter: SurfaceIntersectionParameterCoordinate
  let normalizedBounds: [(lower: Double, upper: Double)]
  private let mapping: Mapping

  var exactAffineSegmentEndpoints:
    (
      lower: SurfaceIntersectionParameterPair,
      upper: SurfaceIntersectionParameterPair
    )?
  {
    guard case .affineSegment(let lower, let upper) = mapping else {
      return nil
    }
    return (lower, upper)
  }

  static func planeRelation(
    first: BSplineSurface3D,
    second: BSplineSurface3D, using execution: inout OriginalQueryExecution
  ) throws -> PlaneRelation? {
    try execution.consumeWork(1)
    guard isSingleBilinearBezier(first),
      isSingleBilinearBezier(second),
      let firstAffine = try exactAffinePatch(first, using: &execution),
      let secondAffine = try exactAffinePatch(second, using: &execution)
    else {
      return nil
    }
    let secondUDistance = try sign(
      try exactTriple(
        firstAffine.exactU,
        firstAffine.exactV,
        secondAffine.exactU, using: &execution), using: &execution)
    let secondVDistance = try sign(
      try exactTriple(
        firstAffine.exactU,
        firstAffine.exactV,
        secondAffine.exactV, using: &execution), using: &execution)
    guard secondUDistance != .indeterminate,
      secondVDistance != .indeterminate
    else {
      return nil
    }
    guard secondUDistance == .zero,
      secondVDistance == .zero
    else {
      return .transverse
    }
    let originDistance = try sign(
      try exactTriple(
        firstAffine.exactU,
        firstAffine.exactV,
        try exactDifference(secondAffine.origin, firstAffine.origin, using: &execution),
        using: &execution), using: &execution)
    guard originDistance != .indeterminate else { return nil }
    return originDistance == .zero ? .coincident : .disjoint
  }

  static func certified(
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ExactAffineBilinearIntersectionGraph? {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard isSingleBilinearBezier(first),
      isSingleBilinearBezier(second)
    else {
      return nil
    }
    let firstAffine = try exactAffinePatch(first, using: &execution)
    let secondAffine = try exactAffinePatch(second, using: &execution)
    if let firstAffine, let secondAffine {
      switch try boundedAffineIntersection(
        first: firstAffine,
        second: secondAffine,
        tolerance: tolerance, using: &execution)
      {
      case .segment(let graph):
        return graph
      case .disjoint, .point:
        return nil
      }
    }
    if let affine = firstAffine,
      let graph = try exactCandidateGraph(
        affine: affine,
        candidate: second,
        affineIsFirst: true, using: &execution)
    {
      try OriginalCoefficientAllocation.reserve(
        count: 4, of: (lower: Double, upper: Double).self, using: &execution)
      return ExactAffineBilinearIntersectionGraph(
        freeParameter: graph.freeIsU ? .secondU : .secondV,
        normalizedBounds: Array(
          repeating: (lower: 0.0, upper: 1.0),
          count: 4
        ),
        mapping: .candidate(graph)
      )
    }
    if let affine = secondAffine,
      let graph = try exactCandidateGraph(
        affine: affine,
        candidate: first,
        affineIsFirst: false, using: &execution)
    {
      try OriginalCoefficientAllocation.reserve(
        count: 4, of: (lower: Double, upper: Double).self, using: &execution)
      return ExactAffineBilinearIntersectionGraph(
        freeParameter: graph.freeIsU ? .firstU : .firstV,
        normalizedBounds: Array(
          repeating: (lower: 0.0, upper: 1.0),
          count: 4
        ),
        mapping: .candidate(graph)
      )
    }
    return nil
  }

  static func boundedAffineIntersection(
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> BoundedIntersection? {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard isSingleBilinearBezier(first),
      isSingleBilinearBezier(second),
      let firstAffine = try exactAffinePatch(first, using: &execution),
      let secondAffine = try exactAffinePatch(second, using: &execution),
      try planeRelation(first: first, second: second, using: &execution) == .transverse
    else {
      return nil
    }
    return try boundedAffineIntersection(
      first: firstAffine,
      second: secondAffine,
      tolerance: tolerance, using: &execution)
  }

  func normalizedParameterPair(
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
    switch mapping {
    case .affineSegment(let lower, let upper):
      return try SurfaceIntersectionParameterPair(
        values: try OriginalCoefficientAllocation.map(
          first:
            lower.values, second: upper.values, using: &execution
        ) { pair, execution in
          let (lowerValue, upperValue) = pair
          return lowerValue + (upperValue - lowerValue) * clamped
        })
    case .candidate(let graph):
      return try candidateParameterPair(
        graph: graph,
        free: clamped,
        tolerance: tolerance, using: &execution)
    }
  }

  private func candidateParameterPair(
    graph: CandidateGraph,
    free: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntersectionParameterPair {
    try execution.consumeWork(1)
    let lower = Self.linearBernstein(graph.lowerPlaneValues, at: free)
    let upper = Self.linearBernstein(graph.upperPlaneValues, at: free)
    let denominator = upper - lower
    guard denominator.isFinite,
      denominator > 0.0
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        message: "An exact affine-bilinear graph lost its strictly positive root denominator."
      )
    }
    let dependent = -lower / denominator
    guard dependent.isFinite,
      dependent >= -tolerance.relative,
      dependent <= 1.0 + tolerance.relative
    else {
      throw Self.certificateFailure(
        tolerance: tolerance,
        residual: max(-dependent, dependent - 1.0),
        message: "An exact affine-bilinear graph left the candidate parameter domain."
      )
    }
    let candidateU = graph.freeIsU ? free : dependent
    let candidateV = graph.freeIsU ? dependent : free
    let candidatePoint = try graph.candidate.point(
      u: Self.actualParameter(candidateU, in: graph.candidate.uDomain),
      v: Self.actualParameter(candidateV, in: graph.candidate.vDomain),
      tolerance: tolerance, using: &execution
    )
    let affineParameters = try Self.affineParameters(
      for: candidatePoint,
      on: graph.affine,
      tolerance: tolerance, using: &execution)
    try OriginalCoefficientAllocation.reserve(count: 4, of: Double.self, using: &execution)
    return try SurfaceIntersectionParameterPair(
      values: graph.affineIsFirst
        ? [affineParameters.u, affineParameters.v, candidateU, candidateV]
        : [candidateU, candidateV, affineParameters.u, affineParameters.v])
  }

  func actualParameterPair(
    at fraction: Double,
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntersectionParameterPair {
    try execution.consumeWork(1)
    let normalized = try normalizedParameterPair(
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
    guard freeParameter == self.freeParameter,
      try Self.matches(
        parameterBox: parameterBox,
        normalizedBounds: normalizedBounds,
        first: first,
        second: second,
        tolerance: tolerance, using: &execution)
    else {
      return false
    }
    try OriginalCoefficientAllocation.reserve(count: 3, of: Double.self, using: &execution)
    let expected = try OriginalCoefficientAllocation.map(
      elements: [0.0, 0.5, 1.0], using: &execution
    ) { element, execution in
      try actualParameterPair(
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
          (zip(stored.values, reproduced.values).allSatisfy { value, expectedValue in
            try execution.consumeWork(1)
            return abs(value - expectedValue) <= tolerance.relative
          })
      })
  }

  func certifiedImplicitCurve(
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CertifiedImplicitIntersectionCurve {
    try execution.consumeWork(1)
    let domains = try BoundedSurfaceParameterDomainMap(
      first: first,
      second: second,
      tolerance: tolerance, using: &execution
    )
    let lower = try domains.actual(
      try OriginalCoefficientAllocation.map(elements: normalizedBounds, using: &execution) {
        element, execution in element.lower
      }, using: &execution)
    let upper = try domains.actual(
      try OriginalCoefficientAllocation.map(elements: normalizedBounds, using: &execution) {
        element, execution in element.upper
      }, using: &execution)
    try OriginalCoefficientAllocation.reserve(count: 3, of: Double.self, using: &execution)
    let anchors = try OriginalCoefficientAllocation.map(
      elements: [0.0, 0.5, 1.0], using: &execution
    ) { element, execution in
      try actualParameterPair(
        at: element,
        first: first,
        second: second,
        tolerance: tolerance, using: &execution)
    }
    let cell = try CertifiedImplicitIntersectionGraphCell(
      parameterBox: SurfaceIntersectionParameterBox(
        firstU: try ScalarInterval(lower: lower[0], upper: upper[0]),
        firstV: try ScalarInterval(lower: lower[1], upper: upper[1]),
        secondU: try ScalarInterval(lower: lower[2], upper: upper[2]),
        secondV: try ScalarInterval(lower: lower[3], upper: upper[3])
      ),
      freeParameter: freeParameter,
      direction: .forward,
      lowerAnchor: anchors[0],
      midpointAnchor: anchors[1],
      upperAnchor: anchors[2],
      firstSurface: first,
      secondSurface: second,
      tolerance: tolerance, using: &execution
    )
    try OriginalCoefficientAllocation.reserve(
      count: 1, of: CertifiedImplicitIntersectionGraphCell.self, using: &execution)
    return try CertifiedImplicitIntersectionCurve(
      firstSurface: first,
      secondSurface: second,
      cells: [cell],
      isClosed: false,
      tolerance: tolerance, using: &execution
    )
  }

  private static func exactCandidateGraph(
    affine: AffinePatch,
    candidate: BSplineSurface3D,
    affineIsFirst: Bool, using execution: inout OriginalQueryExecution
  ) throws -> CandidateGraph? {
    try execution.consumeWork(1)
    guard
      try
        (OriginalCoefficientAllocation.flatten(rows: candidate.weights, using: &execution)
        .allSatisfy({
          try execution.consumeWork(1)
          return $0.isFinite && $0 > 0.0
        }))
    else {
      return nil
    }
    for freeIndex in 0..<2 {
      try execution.consumeWork(1)
      let freeIsU = freeIndex == 0
      try OriginalCoefficientAllocation.reserve(
        count: 4, of: (v: Int, u: Int).self, using: &execution)
      let lowCorners =
        freeIsU
        ? [(v: 0, u: 0), (v: 0, u: 1)]
        : [(v: 0, u: 0), (v: 1, u: 0)]
      let highCorners =
        freeIsU
        ? [(v: 1, u: 0), (v: 1, u: 1)]
        : [(v: 0, u: 1), (v: 1, u: 1)]
      var low = try OriginalCoefficientAllocation.map(elements: lowCorners, using: &execution) {
        element, execution in
        try planeValue(
          point: candidate.controlPoints[element.v][element.u],
          weight: candidate.weights[element.v][element.u],
          affine: affine, using: &execution)
      }
      var high = try OriginalCoefficientAllocation.map(elements: highCorners, using: &execution) {
        element, execution in
        try planeValue(
          point: candidate.controlPoints[element.v][element.u],
          weight: candidate.weights[element.v][element.u],
          affine: affine, using: &execution)
      }
      guard
        try
          (low.allSatisfy({
            try execution.consumeWork(1)
            return try sign($0, using: &execution) != .indeterminate
          })),
        try
          (high.allSatisfy({
            try execution.consumeWork(1)
            return try sign($0, using: &execution) != .indeterminate
          }))
      else {
        continue
      }
      if try
        (low.allSatisfy {
          try execution.consumeWork(1)
          return try isNonnegative($0, using: &execution)
        }),
        try
          (high.allSatisfy {
            try execution.consumeWork(1)
            return try isNonpositive($0, using: &execution)
          })
      {
        low = try OriginalCoefficientAllocation.map(elements: low, using: &execution) {
          element, execution in try negated(element, using: &execution)
        }
        high = try OriginalCoefficientAllocation.map(elements: high, using: &execution) {
          element, execution in try negated(element, using: &execution)
        }
      }
      guard
        try
          (low.allSatisfy {
            try execution.consumeWork(1)
            return try isNonpositive($0, using: &execution)
          }),
        try
          (high.allSatisfy {
            try execution.consumeWork(1)
            return try isNonnegative($0, using: &execution)
          }),
        try
          (zip(low, high).allSatisfy({
            try execution.consumeWork(1)
            return try sign(
              try FloatingPointExpansion.subtract($0.1, $0.0, using: &execution), using: &execution)
              == .positive
          }))
      else {
        continue
      }
      let lowHomogeneous = try OriginalCoefficientAllocation.map(
        elements: lowCorners, using: &execution
      ) { element, execution in
        try homogeneous(
          point: candidate.controlPoints[element.v][element.u],
          weight: candidate.weights[element.v][element.u], using: &execution)
      }
      let highHomogeneous = try OriginalCoefficientAllocation.map(
        elements: highCorners, using: &execution
      ) { element, execution in
        try homogeneous(
          point: candidate.controlPoints[element.v][element.u],
          weight: candidate.weights[element.v][element.u], using: &execution)
      }
      let curveControls = try rationalQuadraticControls(
        lowHomogeneous: lowHomogeneous,
        highHomogeneous: highHomogeneous,
        lowPlaneValues: low,
        highPlaneValues: high, using: &execution)
      guard
        try
          (curveControls.allSatisfy({
            try execution.consumeWork(1)
            return try exactAffineParameterBoundsContain(
              homogeneousPoint: $0,
              affine: affine, using: &execution)
          }))
      else {
        continue
      }
      return CandidateGraph(
        affineIsFirst: affineIsFirst,
        freeIsU: freeIsU,
        affine: affine,
        candidate: candidate,
        lowerPlaneValues: try OriginalCoefficientAllocation.map(elements: low, using: &execution) {
          element, execution in try FloatingPointExpansion.estimate(element, using: &execution)
        },
        upperPlaneValues: try OriginalCoefficientAllocation.map(elements: high, using: &execution) {
          element, execution in try FloatingPointExpansion.estimate(element, using: &execution)
        }
      )
    }
    return nil
  }

  private static func exactAffinePatch(
    _ surface: BSplineSurface3D, using execution: inout OriginalQueryExecution
  ) throws -> AffinePatch? {
    try execution.consumeWork(1)
    guard let parameterization = try ExactAffineBSplineSurfacePatch(surface, using: &execution)
    else {
      return nil
    }
    let p00 = parameterization.origin
    let p10 = surface.controlPoints[0][1]
    let p01 = surface.controlPoints[1][0]
    let exactU = try exactDifference(p10, p00, using: &execution)
    let exactV = try exactDifference(p01, p00, using: &execution)
    let gramUU = try exactDot(exactU, exactU, using: &execution)
    let gramUV = try exactDot(exactU, exactV, using: &execution)
    let gramVV = try exactDot(exactV, exactV, using: &execution)
    let determinant = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(gramUU, gramVV, using: &execution),
      try FloatingPointExpansion.product(gramUV, gramUV, using: &execution), using: &execution)
    return AffinePatch(
      surface: surface,
      origin: p00,
      u: parameterization.uDirection,
      v: parameterization.vDirection,
      exactU: exactU,
      exactV: exactV,
      gramUU: gramUU,
      gramUV: gramUV,
      gramVV: gramVV,
      gramDeterminant: determinant
    )
  }

  private static func exactAffineParameterBoundsContain(
    homogeneousPoint: HomogeneousExpansion,
    affine: AffinePatch, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    guard try sign(homogeneousPoint.weight, using: &execution) == .positive else { return false }
    let relative = ExpansionVector3(
      x: try FloatingPointExpansion.subtract(
        homogeneousPoint.x,
        try FloatingPointExpansion.product(
          try OriginalCoefficientAllocation.singleton(affine.origin.x, using: &execution),
          homogeneousPoint.weight, using: &execution), using: &execution),
      y: try FloatingPointExpansion.subtract(
        homogeneousPoint.y,
        try FloatingPointExpansion.product(
          try OriginalCoefficientAllocation.singleton(affine.origin.y, using: &execution),
          homogeneousPoint.weight, using: &execution), using: &execution),
      z: try FloatingPointExpansion.subtract(
        homogeneousPoint.z,
        try FloatingPointExpansion.product(
          try OriginalCoefficientAllocation.singleton(affine.origin.z, using: &execution),
          homogeneousPoint.weight, using: &execution), using: &execution)
    )
    let dotU = try exactDot(relative, affine.exactU, using: &execution)
    let dotV = try exactDot(relative, affine.exactV, using: &execution)
    let uNumerator = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(dotU, affine.gramVV, using: &execution),
      try FloatingPointExpansion.product(dotV, affine.gramUV, using: &execution), using: &execution)
    let vNumerator = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(dotV, affine.gramUU, using: &execution),
      try FloatingPointExpansion.product(dotU, affine.gramUV, using: &execution), using: &execution)
    let denominator = try FloatingPointExpansion.product(
      homogeneousPoint.weight,
      affine.gramDeterminant, using: &execution)
    return try isNonnegative(uNumerator, using: &execution)
      && isNonnegative(
        try FloatingPointExpansion.subtract(denominator, uNumerator, using: &execution),
        using: &execution)
      && isNonnegative(vNumerator, using: &execution)
      && isNonnegative(
        try FloatingPointExpansion.subtract(denominator, vNumerator, using: &execution),
        using: &execution)
  }

  private static func rationalQuadraticControls(
    lowHomogeneous: [HomogeneousExpansion],
    highHomogeneous: [HomogeneousExpansion],
    lowPlaneValues: [[Double]],
    highPlaneValues: [[Double]], using execution: inout OriginalQueryExecution
  ) throws -> [HomogeneousExpansion] {
    try execution.consumeWork(1)
    let first = try lowHomogeneous[0]
      .scaled(by: highPlaneValues[0], using: &execution)
      .subtracting(
        highHomogeneous[0].scaled(by: lowPlaneValues[0], using: &execution), using: &execution)
    let middleSum = try lowHomogeneous[0].scaled(by: highPlaneValues[1], using: &execution)
      .adding(
        lowHomogeneous[1].scaled(by: highPlaneValues[0], using: &execution), using: &execution
      )
      .subtracting(
        highHomogeneous[0].scaled(by: lowPlaneValues[1], using: &execution), using: &execution
      )
      .subtracting(
        highHomogeneous[1].scaled(by: lowPlaneValues[0], using: &execution), using: &execution)
    let middle = try middleSum.scaled(
      by: try OriginalCoefficientAllocation.singleton(0.5, using: &execution), using: &execution)
    let last = try lowHomogeneous[1]
      .scaled(by: highPlaneValues[1], using: &execution)
      .subtracting(
        highHomogeneous[1].scaled(by: lowPlaneValues[1], using: &execution), using: &execution)
    try OriginalCoefficientAllocation.reserve(
      count: 3, of: HomogeneousExpansion.self, using: &execution)
    return [first, middle, last]
  }

  private static func planeValue(
    point: Point3D,
    weight: Double,
    affine: AffinePatch, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    return try FloatingPointExpansion.product(
      try exactTriple(
        affine.exactU,
        affine.exactV,
        try exactDifference(point, affine.origin, using: &execution), using: &execution),
      [weight], using: &execution)
  }

  private static func homogeneous(
    point: Point3D,
    weight: Double, using execution: inout OriginalQueryExecution
  ) throws -> HomogeneousExpansion {
    try execution.consumeWork(1)
    return HomogeneousExpansion(
      x: try FloatingPointExpansion.product(
        try OriginalCoefficientAllocation.singleton(point.x, using: &execution),
        try OriginalCoefficientAllocation.singleton(weight, using: &execution), using: &execution),
      y: try FloatingPointExpansion.product(
        try OriginalCoefficientAllocation.singleton(point.y, using: &execution),
        try OriginalCoefficientAllocation.singleton(weight, using: &execution), using: &execution),
      z: try FloatingPointExpansion.product(
        try OriginalCoefficientAllocation.singleton(point.z, using: &execution),
        try OriginalCoefficientAllocation.singleton(weight, using: &execution), using: &execution),
      weight: try OriginalCoefficientAllocation.singleton(weight, using: &execution)
    )
  }

  private static func affineParameters(
    for point: Point3D,
    on affine: AffinePatch,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: Double, v: Double) {
    try execution.consumeWork(1)
    let offset = point - affine.origin
    let uu = affine.u.dot(affine.u)
    let uv = affine.u.dot(affine.v)
    let vv = affine.v.dot(affine.v)
    let determinant = uu * vv - uv * uv
    guard determinant.isFinite,
      determinant > 0.0
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "An exact affine-bilinear graph lost its affine parameter inverse."
      )
    }
    let offsetU = offset.dot(affine.u)
    let offsetV = offset.dot(affine.v)
    let u = (offsetU * vv - offsetV * uv) / determinant
    let v = (offsetV * uu - offsetU * uv) / determinant
    guard u.isFinite,
      v.isFinite,
      u >= -tolerance.relative,
      u <= 1.0 + tolerance.relative,
      v >= -tolerance.relative,
      v <= 1.0 + tolerance.relative
    else {
      throw certificateFailure(
        tolerance: tolerance,
        residual: max(-u, u - 1.0, -v, v - 1.0),
        message: "An exact affine-bilinear graph left the affine parameter domain."
      )
    }
    return (min(max(u, 0.0), 1.0), min(max(v, 0.0), 1.0))
  }

  private static func matches(
    parameterBox: SurfaceIntersectionParameterBox,
    normalizedBounds: [(lower: Double, upper: Double)],
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    try OriginalCoefficientAllocation.reserve(count: 4, of: ParameterDomain.self, using: &execution)
    let domains = [first.uDomain, first.vDomain, second.uDomain, second.vDomain]
    guard normalizedBounds.count == domains.count else { return false }
    return try
      (zip(
        zip(parameterBox.intervals, normalizedBounds),
        domains
      ).allSatisfy { values, domain in
        try execution.consumeWork(1)
        let (interval, normalized) = values
        guard case .closed(let lower, let upper) = domain else { return false }
        let span = upper - lower
        let expectedLower = lower + span * normalized.lower
        let expectedUpper = lower + span * normalized.upper
        return abs(interval.lower - expectedLower) <= tolerance.relative
          && abs(interval.upper - expectedUpper) <= tolerance.relative
      })
  }

  private static func parameterDomainSpans(
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    try OriginalCoefficientAllocation.reserve(count: 4, of: ParameterDomain.self, using: &execution)
    return try OriginalCoefficientAllocation.map(
      elements: [first.uDomain, first.vDomain, second.uDomain, second.vDomain], using: &execution
    ) { domain, execution in
      guard case .closed(let lower, let upper) = domain,
        upper - lower > tolerance.relative
      else {
        throw certificateFailure(
          tolerance: tolerance,
          message: "An exact affine graph requires non-degenerate closed parameter domains."
        )
      }
      return upper - lower
    }
  }

  private static func boundedAffineIntersection(
    first: AffinePatch,
    second: AffinePatch,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> BoundedIntersection {
    try execution.consumeWork(1)
    let firstSection = try exactSection(
      patch: first,
      cuttingPlane: second,
      tolerance: tolerance, using: &execution)
    let secondSection = try exactSection(
      patch: second,
      cuttingPlane: first,
      tolerance: tolerance, using: &execution)
    guard firstSection.isEmpty == false,
      secondSection.isEmpty == false
    else {
      return .disjoint
    }

    let allPoints = firstSection + secondSection
    let coordinateIndex = try nonconstantFirstPatchCoordinate(
      points: allPoints,
      first: first,
      tolerance: tolerance, using: &execution)
    let firstRange = try sectionRange(
      points: firstSection,
      coordinateIndex: coordinateIndex,
      first: first,
      tolerance: tolerance, using: &execution)
    let secondRange = try sectionRange(
      points: secondSection,
      coordinateIndex: coordinateIndex,
      first: first,
      tolerance: tolerance, using: &execution)
    let lower = try maximumEndpoint(
      firstRange.lower,
      secondRange.lower,
      tolerance: tolerance, using: &execution)
    let upper = try minimumEndpoint(
      firstRange.upper,
      secondRange.upper,
      tolerance: tolerance, using: &execution)
    switch try lower.coordinate.compared(to: upper.coordinate, using: &execution) {
    case .positive:
      return .disjoint
    case .zero:
      return .point(
        try normalizedParameterPair(
          for: lower.point,
          first: first,
          second: second,
          tolerance: tolerance, using: &execution))
    case .negative:
      break
    case .indeterminate:
      throw certificateFailure(
        tolerance: tolerance,
        message: "Exact affine bounded-intersection ordering was indeterminate."
      )
    }

    let lowerValues = try normalizedParameterPair(
      for: lower.point,
      first: first,
      second: second,
      tolerance: tolerance, using: &execution
    ).values
    let upperValues = try normalizedParameterPair(
      for: upper.point,
      first: first,
      second: second,
      tolerance: tolerance, using: &execution
    ).values
    let spans = try OriginalCoefficientAllocation.map(
      first: lowerValues, second: upperValues, using: &execution
    ) { element, execution in abs(element.1 - element.0) }
    let domainSpans = try parameterDomainSpans(
      first: first.surface,
      second: second.surface,
      tolerance: tolerance, using: &execution)
    let actualSpans = try OriginalCoefficientAllocation.map(
      first: spans, second: domainSpans, using: &execution
    ) { element, execution in element.0 * element.1 }
    guard
      let freeIndex = try actualSpans.indices.max(by: {
        try execution.consumeWork(1)
        return actualSpans[$0] < actualSpans[$1]
      }), actualSpans[freeIndex] > 0.0
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "An exact nonzero affine segment could not be represented in Double parameters."
      )
    }
    let orderedLower: [Double]
    let orderedUpper: [Double]
    if lowerValues[freeIndex] <= upperValues[freeIndex] {
      orderedLower = lowerValues
      orderedUpper = upperValues
    } else {
      orderedLower = upperValues
      orderedUpper = lowerValues
    }
    try OriginalCoefficientAllocation.reserve(
      count: 2, of: BSplineSurface3D.self, using: &execution)
    let normalizedBounds = try certifiedBounds(
      lower: orderedLower,
      upper: orderedUpper,
      surfaces: [first.surface, second.surface],
      freeIndex: freeIndex,
      tolerance: tolerance, using: &execution)
    guard
      let freeParameter = SurfaceIntersectionParameterCoordinate(
        rawValue: freeIndex
      )
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "An exact affine segment selected an invalid free parameter."
      )
    }
    return .segment(
      ExactAffineBilinearIntersectionGraph(
        freeParameter: freeParameter,
        normalizedBounds: normalizedBounds,
        mapping: .affineSegment(
          lower: try SurfaceIntersectionParameterPair(values: orderedLower),
          upper: try SurfaceIntersectionParameterPair(values: orderedUpper)
        )
      ))
  }

  private static func exactSection(
    patch: AffinePatch,
    cuttingPlane: AffinePatch,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [HomogeneousExpansion] {
    try execution.consumeWork(1)
    let p00 = patch.surface.controlPoints[0][0]
    let p10 = patch.surface.controlPoints[0][1]
    let p01 = patch.surface.controlPoints[1][0]
    let p11 = patch.surface.controlPoints[1][1]
    try OriginalCoefficientAllocation.reserve(count: 4, of: Point3D.self, using: &execution)
    let corners = [p00, p10, p11, p01]
    let values = try OriginalCoefficientAllocation.map(elements: corners, using: &execution) {
      element, execution in
      try planeValue(point: element, weight: 1.0, affine: cuttingPlane, using: &execution)
    }
    guard
      try
        (values.allSatisfy({
          try execution.consumeWork(1)
          return try sign($0, using: &execution) != .indeterminate
        }))
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "Exact affine boundary signs were indeterminate."
      )
    }
    var endpoints: [HomogeneousExpansion] = []
    for index in corners.indices {
      try execution.consumeWork(1)
      let next = (index + 1) % corners.count
      let firstSign = try sign(values[index], using: &execution)
      let secondSign = try sign(values[next], using: &execution)
      if firstSign == .zero {
        try appendUnique(
          try homogeneous(point: corners[index], weight: 1.0, using: &execution), to: &endpoints,
          using: &execution)
      }
      if secondSign == .zero {
        try appendUnique(
          try homogeneous(point: corners[next], weight: 1.0, using: &execution), to: &endpoints,
          using: &execution)
      }
      if (firstSign == .negative && secondSign == .positive)
        || (firstSign == .positive && secondSign == .negative)
      {
        let denominator = try FloatingPointExpansion.subtract(
          values[next],
          values[index], using: &execution)
        var root = HomogeneousExpansion(
          x: try FloatingPointExpansion.subtract(
            try FloatingPointExpansion.product([corners[index].x], values[next], using: &execution),
            try FloatingPointExpansion.product([corners[next].x], values[index], using: &execution),
            using: &execution),
          y: try FloatingPointExpansion.subtract(
            try FloatingPointExpansion.product([corners[index].y], values[next], using: &execution),
            try FloatingPointExpansion.product([corners[next].y], values[index], using: &execution),
            using: &execution),
          z: try FloatingPointExpansion.subtract(
            try FloatingPointExpansion.product([corners[index].z], values[next], using: &execution),
            try FloatingPointExpansion.product([corners[next].z], values[index], using: &execution),
            using: &execution),
          weight: denominator
        )
        if try sign(root.weight, using: &execution) == .negative {
          root = try root.scaled(
            by: try OriginalCoefficientAllocation.singleton(-1.0, using: &execution),
            using: &execution)
        }
        guard try sign(root.weight, using: &execution) == .positive else {
          throw certificateFailure(
            tolerance: tolerance,
            message: "Exact affine edge interpolation lost its positive denominator."
          )
        }
        try appendUnique(root, to: &endpoints, using: &execution)
      }
    }
    guard endpoints.count <= 2 else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "A transverse plane produced more than two affine section endpoints."
      )
    }
    return endpoints
  }

  private static func appendUnique(
    _ candidate: HomogeneousExpansion,
    to endpoints: inout [HomogeneousExpansion], using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)
    guard
      try
        (endpoints.contains(where: {
          try execution.consumeWork(1)
          return try exactlyEqual($0, candidate, using: &execution)
        })) == false
    else {
      return
    }
    if endpoints.count == endpoints.capacity {
      let doubled = endpoints.capacity.multipliedReportingOverflow(by: 2)
      guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
      let capacity = max(1, doubled.partialValue)
      try OriginalCoefficientAllocation.reserve(
        count: capacity, of: HomogeneousExpansion.self, using: &execution)
      endpoints.reserveCapacity(capacity)
    }
    endpoints.append(candidate)
  }

  private static func exactlyEqual(
    _ first: HomogeneousExpansion,
    _ second: HomogeneousExpansion, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    try OriginalCoefficientAllocation.reserve(
      count: 4, of: ([Double], [Double]).self, using: &execution)
    return try
      ([
        (first.x, second.x),
        (first.y, second.y),
        (first.z, second.z),
      ].allSatisfy { firstCoordinate, secondCoordinate in
        try execution.consumeWork(1)
        return try sign(
          try FloatingPointExpansion.subtract(
            try FloatingPointExpansion.product(firstCoordinate, second.weight, using: &execution),
            try FloatingPointExpansion.product(secondCoordinate, first.weight, using: &execution),
            using: &execution), using: &execution) == .zero
      })
  }

  private static func affineParameterRatios(
    for point: HomogeneousExpansion,
    on patch: AffinePatch,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (u: ExactRatio, v: ExactRatio) {
    try execution.consumeWork(1)
    guard try sign(point.weight, using: &execution) == .positive else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "An exact affine endpoint had a nonpositive homogeneous weight."
      )
    }
    let relative = ExpansionVector3(
      x: try FloatingPointExpansion.subtract(
        point.x,
        try FloatingPointExpansion.product(
          try OriginalCoefficientAllocation.singleton(patch.origin.x, using: &execution),
          point.weight, using: &execution), using: &execution),
      y: try FloatingPointExpansion.subtract(
        point.y,
        try FloatingPointExpansion.product(
          try OriginalCoefficientAllocation.singleton(patch.origin.y, using: &execution),
          point.weight, using: &execution), using: &execution),
      z: try FloatingPointExpansion.subtract(
        point.z,
        try FloatingPointExpansion.product(
          try OriginalCoefficientAllocation.singleton(patch.origin.z, using: &execution),
          point.weight, using: &execution), using: &execution)
    )
    let dotU = try exactDot(relative, patch.exactU, using: &execution)
    let dotV = try exactDot(relative, patch.exactV, using: &execution)
    let uNumerator = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(dotU, patch.gramVV, using: &execution),
      try FloatingPointExpansion.product(dotV, patch.gramUV, using: &execution), using: &execution)
    let vNumerator = try FloatingPointExpansion.subtract(
      try FloatingPointExpansion.product(dotV, patch.gramUU, using: &execution),
      try FloatingPointExpansion.product(dotU, patch.gramUV, using: &execution), using: &execution)
    let denominator = try FloatingPointExpansion.product(
      point.weight,
      patch.gramDeterminant, using: &execution)
    guard
      let u = try ExactRatio(numerator: uNumerator, denominator: denominator, using: &execution),
      let v = try ExactRatio(numerator: vNumerator, denominator: denominator, using: &execution)
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "An exact affine endpoint lost its parameter denominator."
      )
    }
    return (u, v)
  }

  private static func nonconstantFirstPatchCoordinate(
    points: [HomogeneousExpansion],
    first: AffinePatch,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    try execution.consumeWork(1)
    let parameters = try OriginalCoefficientAllocation.map(elements: points, using: &execution) {
      element, execution in
      try affineParameterRatios(for: element, on: first, tolerance: tolerance, using: &execution)
    }
    for coordinateIndex in 0...1 {
      try execution.consumeWork(1)
      let values = try OriginalCoefficientAllocation.map(elements: parameters, using: &execution) {
        element, execution in coordinateIndex == 0 ? element.u : element.v
      }
      guard let reference = values.first else { continue }
      if try
        (values.dropFirst().contains(where: {
          try execution.consumeWork(1)
          return try reference.compared(to: $0, using: &execution) != .zero
        }))
      {
        return coordinateIndex
      }
    }
    return 0
  }

  private static func sectionRange(
    points: [HomogeneousExpansion],
    coordinateIndex: Int,
    first: AffinePatch,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (lower: SectionEndpoint, upper: SectionEndpoint) {
    try execution.consumeWork(1)
    let endpoints = try OriginalCoefficientAllocation.map(elements: points, using: &execution) {
      point, execution in
      let parameters = try affineParameterRatios(
        for: point,
        on: first,
        tolerance: tolerance, using: &execution)
      return SectionEndpoint(
        point: point,
        coordinate: coordinateIndex == 0 ? parameters.u : parameters.v
      )
    }
    guard let firstEndpoint = endpoints.first else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "An exact affine section unexpectedly had no endpoints."
      )
    }
    guard endpoints.count == 2 else {
      return (firstEndpoint, firstEndpoint)
    }
    switch try endpoints[0].coordinate.compared(to: endpoints[1].coordinate, using: &execution) {
    case .negative, .zero:
      return (endpoints[0], endpoints[1])
    case .positive:
      return (endpoints[1], endpoints[0])
    case .indeterminate:
      throw certificateFailure(
        tolerance: tolerance,
        message: "Exact affine section ordering was indeterminate."
      )
    }
  }

  private static func maximumEndpoint(
    _ first: SectionEndpoint,
    _ second: SectionEndpoint,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SectionEndpoint {
    try execution.consumeWork(1)
    switch try first.coordinate.compared(to: second.coordinate, using: &execution) {
    case .negative:
      return second
    case .zero, .positive:
      return first
    case .indeterminate:
      throw certificateFailure(
        tolerance: tolerance,
        message: "Exact affine lower-bound comparison was indeterminate."
      )
    }
  }

  private static func minimumEndpoint(
    _ first: SectionEndpoint,
    _ second: SectionEndpoint,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SectionEndpoint {
    try execution.consumeWork(1)
    switch try first.coordinate.compared(to: second.coordinate, using: &execution) {
    case .negative, .zero:
      return first
    case .positive:
      return second
    case .indeterminate:
      throw certificateFailure(
        tolerance: tolerance,
        message: "Exact affine upper-bound comparison was indeterminate."
      )
    }
  }

  private static func normalizedParameterPair(
    for point: HomogeneousExpansion,
    first: AffinePatch,
    second: AffinePatch,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntersectionParameterPair {
    try execution.consumeWork(1)
    let firstParameters = try affineParameterRatios(
      for: point,
      on: first,
      tolerance: tolerance, using: &execution)
    let secondParameters = try affineParameterRatios(
      for: point,
      on: second,
      tolerance: tolerance, using: &execution)
    try OriginalCoefficientAllocation.reserve(count: 4, of: ExactRatio.self, using: &execution)
    return try SurfaceIntersectionParameterPair(
      values: try OriginalCoefficientAllocation.map(
        elements: [
          firstParameters.u,
          firstParameters.v,
          secondParameters.u,
          secondParameters.v,
        ], using: &execution
      ) { element, execution in
        try normalizedEstimate(element, tolerance: tolerance, using: &execution)
      })
  }

  private static func normalizedEstimate(
    _ ratio: ExactRatio,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    guard try isNonnegative(ratio.numerator, using: &execution),
      try isNonnegative(
        try FloatingPointExpansion.subtract(
          ratio.denominator,
          ratio.numerator, using: &execution), using: &execution)
    else {
      throw certificateFailure(
        tolerance: tolerance,
        message: "An exact affine intersection endpoint left a bounded patch."
      )
    }
    let value = try ratio.estimate(using: &execution)
    guard value.isFinite,
      value >= -tolerance.relative * 8.0,
      value <= 1.0 + tolerance.relative * 8.0
    else {
      throw certificateFailure(
        tolerance: tolerance,
        residual: max(-value, value - 1.0),
        message: "An exact affine endpoint could not be materialized in Double parameters."
      )
    }
    return min(max(value, 0.0), 1.0)
  }

  private static func certifiedBounds(
    lower: [Double],
    upper: [Double],
    surfaces: [BSplineSurface3D],
    freeIndex: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [(lower: Double, upper: Double)] {
    try execution.consumeWork(1)
    let domainSpans = try parameterDomainSpans(
      first: surfaces[0],
      second: surfaces[1],
      tolerance: tolerance, using: &execution)
    return try OriginalCoefficientAllocation.map(elements: lower.indices, using: &execution) {
      index, execution in
      var boundLower = min(lower[index], upper[index])
      var boundUpper = max(lower[index], upper[index])
      if index != freeIndex {
        let minimumWidth = max(
          tolerance.relative * 4.0 / domainSpans[index],
          Double.ulpOfOne * 1_024.0
        )
        if boundUpper - boundLower <= minimumWidth {
          if boundLower <= minimumWidth {
            boundLower = 0.0
            boundUpper = max(boundUpper, minimumWidth)
          } else if boundUpper >= 1.0 - minimumWidth {
            boundLower = min(boundLower, 1.0 - minimumWidth)
            boundUpper = 1.0
          } else {
            let midpoint = (boundLower + boundUpper) * 0.5
            boundLower = midpoint - minimumWidth * 0.5
            boundUpper = midpoint + minimumWidth * 0.5
          }
        }
      }
      guard boundLower >= 0.0,
        boundUpper <= 1.0,
        boundUpper > boundLower
      else {
        throw certificateFailure(
          tolerance: tolerance,
          message: "An exact affine graph produced invalid certified bounds."
        )
      }
      return (boundLower, boundUpper)
    }
  }

  private static func actualParameter(
    _ normalized: Double,
    in domain: ParameterDomain
  ) -> Double {
    guard case .closed(let lower, let upper) = domain else { return .nan }
    return lower + (upper - lower) * normalized
  }

  private static func linearBernstein(
    _ coefficients: [Double],
    at parameter: Double
  ) -> Double {
    coefficients[0] * (1.0 - parameter) + coefficients[1] * parameter
  }

  private static func isSingleBilinearBezier(
    _ surface: BSplineSurface3D
  ) -> Bool {
    surface.uDegree == 1
      && surface.vDegree == 1
      && surface.uControlPointCount == 2
      && surface.vControlPointCount == 2
      && isSingleBezierKnotVector(surface.uKnots)
      && isSingleBezierKnotVector(surface.vKnots)
  }

  private static func isSingleBezierKnotVector(_ knots: [Double]) -> Bool {
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

  private static func sign(_ value: [Double], using execution: inout OriginalQueryExecution) throws
    -> RobustSign
  {
    try execution.consumeWork(1)
    return try FloatingPointExpansion.sign(value, using: &execution)
  }

  private static func isNonnegative(
    _ value: [Double], using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    let valueSign = try sign(value, using: &execution)
    return valueSign == .positive || valueSign == .zero
  }

  private static func isNonpositive(
    _ value: [Double], using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)
    let valueSign = try sign(value, using: &execution)
    return valueSign == .negative || valueSign == .zero
  }

  private static func negated(_ value: [Double], using execution: inout OriginalQueryExecution)
    throws -> [Double]
  {
    try execution.consumeWork(1)
    return try OriginalCoefficientAllocation.map(elements: value, using: &execution) {
      element, execution in -element
    }
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
