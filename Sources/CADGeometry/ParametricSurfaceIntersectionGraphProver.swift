import CADCore

/// Reconstructs a full-graph interval proof directly from the public surface
/// parameterizations. This proof path is representation-independent; exact
/// rational Bezier surfaces retain their stronger Bernstein proof path.
struct ParametricSurfaceIntersectionGraphProver: Sendable {
  enum Certificate: Equatable, Sendable {
    case fullGraph
    case rankUnresolved
    case unresolved
  }

  enum GaugeCertificate: Sendable {
    case uniqueRoot(localParameters: [Double])
    case empty
    case unresolved
  }

  enum ParameterizedGraphCertificate: Sendable {
    case fullGraph(localParameterBounds: [(lower: Double, upper: Double)])
    case contracted(localParameterBounds: [(lower: Double, upper: Double)])
    case empty
    case unresolved
  }

  private struct IntervalVector: Sendable {
    let x: OutwardScalarInterval
    let y: OutwardScalarInterval
    let z: OutwardScalarInterval

    static func + (lhs: Self, rhs: Self) -> Self {
      Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
      Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    static prefix func - (value: Self) -> Self {
      Self(x: -value.x, y: -value.y, z: -value.z)
    }

    func scaled(by value: OutwardScalarInterval) -> Self {
      Self(x: x * value, y: y * value, z: z * value)
    }

    var isFinite: Bool {
      x.isFinite && y.isFinite && z.isFinite
    }

    var midpoint: Vector3D {
      Vector3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
    }

    var components: [OutwardScalarInterval] {
      [x, y, z]
    }
  }

  private struct IntervalQuadraticPolynomial: Sendable {
    let constant: OutwardScalarInterval
    let linear: OutwardScalarInterval
    let quadratic: OutwardScalarInterval

    static var zero: Self {
      Self(
        constant: .exact(0.0),
        linear: .exact(0.0),
        quadratic: .exact(0.0)
      )
    }

    static func + (lhs: Self, rhs: Self) -> Self {
      Self(
        constant: lhs.constant + rhs.constant,
        linear: lhs.linear + rhs.linear,
        quadratic: lhs.quadratic + rhs.quadratic
      )
    }

    func scaled(by value: OutwardScalarInterval) -> Self {
      Self(
        constant: constant * value,
        linear: linear * value,
        quadratic: quadratic * value
      )
    }

    /// Convex-hull range of the quadratic Bernstein form on [-0.5, 0.5].
    var range: OutwardScalarInterval {
      range(lower: -0.5, upper: 0.5)
    }

    func range(lower: Double, upper: Double) -> OutwardScalarInterval {
      let lowerValue = value(at: lower)
      let upperValue = value(at: upper)
      let midpoint = lower + (upper - lower) * 0.5
      let midpointValue = value(at: midpoint)
      let middle =
        midpointValue * OutwardScalarInterval.exact(2.0)
        - (lowerValue + upperValue) * OutwardScalarInterval.exact(0.5)
      return .enclosing([lowerValue, middle, upperValue])
    }

    private func value(at parameter: Double) -> OutwardScalarInterval {
      let value = OutwardScalarInterval.exact(parameter)
      return constant + linear * value + quadratic * value * value
    }
  }

  private struct ParameterizedKrawczykModel: Sendable {
    let predictors: [IntervalQuadraticPolynomial]
    let remainders: [OutwardScalarInterval]
    let box: [OutwardScalarInterval]

    func box(
      overFreeParameterBounds bounds: (lower: Double, upper: Double)
    ) -> [OutwardScalarInterval] {
      zip(predictors, remainders).map { predictor, remainder in
        predictor.range(
          lower: bounds.lower - 0.5,
          upper: bounds.upper - 0.5
        ) + remainder
      }
    }
  }

  private struct ParameterizedGraphAnalysis: Sendable {
    let dependentIndexes: [Int]
    let dependentMinor: OutwardScalarInterval
    let box: [OutwardScalarInterval]
    let isStrictContraction: Bool
    let provesEmpty: Bool
    let certifiesFullGraph: Bool
    let freeParameterBounds: (lower: Double, upper: Double)
  }

  private let firstSurface: Surface3D
  private let secondSurface: Surface3D
  private let parameterBox: SurfaceIntersectionParameterBox
  private let firstJet: SurfaceIntervalVectorJet
  private let secondJet: SurfaceIntervalVectorJet

  init(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    parameterBox: SurfaceIntersectionParameterBox,
    tolerance: ModelingTolerance
  ) throws {
    try self.init(
      firstSurface: try PreparedSurfaceDifferentialEncloser(
        surface: firstSurface,
        tolerance: tolerance
      ),
      secondSurface: try PreparedSurfaceDifferentialEncloser(
        surface: secondSurface,
        tolerance: tolerance
      ),
      parameterBox: parameterBox,
      tolerance: tolerance
    )
  }

  init(
    firstSurface preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    secondSurface preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    parameterBox: SurfaceIntersectionParameterBox,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    let firstSurface = preparedFirstSurface.surface
    let secondSurface = preparedSecondSurface.surface
    try parameterBox.validate(
      first: firstSurface,
      second: secondSurface,
      tolerance: tolerance
    )
    self.firstSurface = firstSurface
    self.secondSurface = secondSurface
    self.parameterBox = parameterBox
    firstJet = try preparedFirstSurface.intervalJet(
      over: SurfaceParameterBox(
        u: parameterBox.firstU,
        v: parameterBox.firstV
      ),
      tolerance: tolerance
    )
    secondJet = try preparedSecondSurface.intervalJet(
      over: SurfaceParameterBox(
        u: parameterBox.secondU,
        v: parameterBox.secondV
      ),
      tolerance: tolerance
    )
  }

  /// The caller owns enclosure admission for both jets over this exact box.
  init(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    parameterBox: SurfaceIntersectionParameterBox,
    firstJet: SurfaceIntervalVectorJet,
    secondJet: SurfaceIntervalVectorJet
  ) {
    self.firstSurface = firstSurface
    self.secondSurface = secondSurface
    self.parameterBox = parameterBox
    self.firstJet = firstJet
    self.secondJet = secondJet
  }

  func excludesIntersection() -> Bool {
    let residual =
      intervalVector(firstJet, at: \SurfaceIntervalJet.value)
      - intervalVector(secondJet, at: \SurfaceIntervalJet.value)
    return residual.components.contains { $0.excludesZero }
  }

  func rankCertifiedFreeParameters() -> [SurfaceIntersectionParameterCoordinate] {
    let columns = normalizedDerivativeColumns()
    guard columns.allSatisfy(\.isFinite) else { return [] }
    return SurfaceIntersectionParameterCoordinate.allCases.filter { coordinate in
      let dependentColumns = columns.indices
        .filter { $0 != coordinate.rawValue }
        .map { columns[$0] }
      let minor = determinant(
        dependentColumns[0],
        dependentColumns[1],
        dependentColumns[2]
      )
      return minor.isFinite && minor.excludesZero
    }
  }

  func gaugeCertificate(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> GaugeCertificate {
    guard fraction.isFinite, fraction >= 0.0, fraction <= 1.0 else {
      return .unresolved
    }
    let columns = normalizedDerivativeColumns()
    let freeIndex = freeParameter.rawValue
    guard columns.indices.contains(freeIndex),
      columns.allSatisfy(\.isFinite)
    else {
      return .unresolved
    }
    let dependentIndexes = columns.indices.filter { $0 != freeIndex }
    let dependentColumns = dependentIndexes.map { columns[$0] }
    let minor = determinant(
      dependentColumns[0],
      dependentColumns[1],
      dependentColumns[2]
    )
    guard minor.isFinite, minor.excludesZero,
      let inverse = inverseRows(columns: dependentColumns.map(\.midpoint))
    else {
      return .unresolved
    }

    var localParameters = Array(repeating: 0.5, count: 4)
    localParameters[freeIndex] = fraction
    if let numericalCenter = try numericalGaugeCenter(
      freeParameterIndex: freeIndex,
      fraction: fraction,
      tolerance: tolerance
    ) {
      localParameters = numericalCenter
    }
    let actualParameters = zip(localParameters, parameterBox.intervals).map {
      local, interval in interval.lower + interval.width * local
    }
    let firstPoint = try firstSurface.point(
      u: actualParameters[0],
      v: actualParameters[1],
      tolerance: tolerance
    )
    let secondPoint = try secondSurface.point(
      u: actualParameters[2],
      v: actualParameters[3],
      tolerance: tolerance
    )
    let residual = firstPoint - secondPoint
    let functionValue = IntervalVector(
      x: OutwardScalarInterval(residual.x),
      y: OutwardScalarInterval(residual.y),
      z: OutwardScalarInterval(residual.z)
    )
    let centers = dependentIndexes.map {
      OutwardScalarInterval.exact(localParameters[$0])
    }
    let jacobian = jacobianRows(dependentColumns)
    let box = affinePredictorKrawczykBox(
      inverse: inverse,
      jacobian: jacobian,
      functionValue: functionValue,
      centerBounds: centers
    )
    if box.contains(where: { $0.upper < 0.0 || $0.lower > 1.0 }) {
      return .empty
    }
    let certifiesUniqueRoot =
      isStrictlyInsideUnitCube(box)
      || (isInsideUnitCubeWithinRounding(box)
        && krawczykMapIsStrictContraction(
          inverse: inverse,
          jacobian: jacobian
        ))
    guard certifiesUniqueRoot else { return .unresolved }
    for localIndex in dependentIndexes.indices {
      localParameters[dependentIndexes[localIndex]] = min(
        max(box[localIndex].midpoint, 0.0),
        1.0
      )
    }
    return .uniqueRoot(localParameters: localParameters)
  }

  private func numericalGaugeCenter(
    freeParameterIndex: Int,
    fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> [Double]? {
    let domains = try BoundedSurfaceParameterDomainMap(
      first: firstSurface,
      second: secondSurface,
      tolerance: tolerance
    )
    let actualLower = parameterBox.intervals.map(\.lower)
    let actualUpper = parameterBox.intervals.map(\.upper)
    let constraints = zip(
      domains.normalized(actualLower),
      domains.normalized(actualUpper)
    ).map { (lower: $0.0, upper: $0.1) }
    var actualSeed = parameterBox.intervals.map(\.midpoint)
    actualSeed[freeParameterIndex] =
      parameterBox
      .intervals[freeParameterIndex].lower
      + parameterBox.intervals[freeParameterIndex].width * fraction
    let normalizedSeed = domains.normalized(actualSeed)
    guard
      let root = try ParametricSurfaceIntersectionRootRefiner(
        first: firstSurface,
        second: secondSurface,
        domains: domains,
        maximumIterations: 32,
        tolerance: tolerance
      ).gaugeRoot(
        seed: normalizedSeed,
        fixedParameterIndex: freeParameterIndex,
        constraints: constraints
      )
    else {
      return nil
    }
    return zip(root.actual, parameterBox.intervals).map { value, interval in
      min(max((value - interval.lower) / interval.width, 0.0), 1.0)
    }
  }

  /// Applies a parameterized Krawczyk operator while leaving one coordinate
  /// free. Every zero in the current four-dimensional box is retained by the
  /// returned dependent-coordinate contraction. Strict inclusion proves one
  /// regular graph value for every value of the free coordinate.
  func parameterizedGraphCertificate(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    tolerance: ModelingTolerance
  ) throws -> ParameterizedGraphCertificate {
    guard
      let analysis = try parameterizedGraphAnalysis(
        freeParameter: freeParameter,
        tolerance: tolerance
      )
    else {
      return .unresolved
    }
    if analysis.provesEmpty { return .empty }
    let unit = OutwardScalarInterval(lower: 0.0, upper: 1.0)
    var localBounds = Array(
      repeating: (lower: 0.0, upper: 1.0),
      count: 4
    )
    localBounds[freeParameter.rawValue] = analysis.freeParameterBounds
    for localIndex in analysis.dependentIndexes.indices {
      guard let contracted = analysis.box[localIndex].intersection(with: unit) else {
        return .empty
      }
      localBounds[analysis.dependentIndexes[localIndex]] = (
        lower: contracted.lower,
        upper: contracted.upper
      )
    }
    if analysis.certifiesFullGraph {
      return .fullGraph(localParameterBounds: localBounds)
    }
    let reduction = localBounds.indices.reduce(0.0) { partial, index in
      partial + 1.0 - (localBounds[index].upper - localBounds[index].lower)
    }
    guard reduction.isFinite, reduction > Double.ulpOfOne * 4_096.0 else {
      return .unresolved
    }
    return .contracted(localParameterBounds: localBounds)
  }

  func parameterizedGraphDiagnostic(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    tolerance: ModelingTolerance
  ) throws -> String {
    guard
      let analysis = try parameterizedGraphAnalysis(
        freeParameter: freeParameter,
        tolerance: tolerance
      )
    else {
      return "parameterized Krawczyk analysis unavailable"
    }
    return
      "dependent minor=[\(analysis.dependentMinor.lower), \(analysis.dependentMinor.upper)], contracted box=\(analysis.box.map { [$0.lower, $0.upper] }), free bounds=[\(analysis.freeParameterBounds.lower), \(analysis.freeParameterBounds.upper)], strict contraction=\(analysis.isStrictContraction), full graph=\(analysis.certifiesFullGraph), proves empty=\(analysis.provesEmpty)"
  }

  func affinePredictorCertificate(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    lowerAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    tolerance: ModelingTolerance
  ) throws -> Certificate {
    let columns = normalizedDerivativeColumns()
    let freeIndex = freeParameter.rawValue
    guard columns.indices.contains(freeIndex),
      columns.allSatisfy(\.isFinite)
    else {
      return .rankUnresolved
    }
    let dependentIndexes = columns.indices.filter { $0 != freeIndex }
    let dependentColumns = dependentIndexes.map { columns[$0] }
    let minor = determinant(
      dependentColumns[0],
      dependentColumns[1],
      dependentColumns[2]
    )
    guard minor.isFinite, minor.excludesZero else {
      return .rankUnresolved
    }
    guard let inverse = inverseRows(columns: dependentColumns.map(\.midpoint)) else {
      return .unresolved
    }
    let normalizedLower = normalized(anchor: lowerAnchor)
    let normalizedUpper = normalized(anchor: upperAnchor)
    guard normalizedLower.count == columns.count,
      normalizedUpper.count == columns.count,
      normalizedLower.allSatisfy({ $0.isFinite && $0 >= 0.0 && $0 <= 1.0 }),
      normalizedUpper.allSatisfy({ $0.isFinite && $0 >= 0.0 && $0 <= 1.0 })
    else {
      return .unresolved
    }
    let functionValue = try affinePredictorResidualBounds(
      lowerAnchor: lowerAnchor,
      upperAnchor: upperAnchor,
      tolerance: tolerance
    )
    let jacobian = jacobianRows(dependentColumns)
    let centerBounds = dependentIndexes.map { index in
      OutwardScalarInterval.enclosing([
        normalizedLower[index],
        normalizedUpper[index],
      ])
    }
    if affinePredictorProvesFullGraph(
      inverse: inverse,
      jacobian: jacobian,
      functionValue: functionValue,
      centerBounds: centerBounds
    ) {
      return .fullGraph
    }
    let box = affinePredictorKrawczykBox(
      inverse: inverse,
      jacobian: jacobian,
      functionValue: functionValue,
      centerBounds: centerBounds
    )
    if isStrictlyInsideUnitCube(box) {
      return .fullGraph
    }
    if isInsideUnitCubeWithinRounding(box),
      krawczykMapIsStrictContraction(inverse: inverse, jacobian: jacobian)
    {
      return .fullGraph
    }
    return .unresolved
  }

  func normalizedGraphParameterDerivativeBounds(
    freeParameter: SurfaceIntersectionParameterCoordinate
  ) throws -> [ScalarInterval]? {
    let columns = normalizedDerivativeColumns()
    let freeIndex = freeParameter.rawValue
    guard columns.indices.contains(freeIndex),
      columns.allSatisfy(\.isFinite)
    else {
      return nil
    }
    let dependentIndexes = columns.indices.filter { $0 != freeIndex }
    let dependentColumns = dependentIndexes.map { columns[$0] }
    let denominator = determinant(
      dependentColumns[0],
      dependentColumns[1],
      dependentColumns[2]
    )
    guard denominator.isFinite, denominator.excludesZero else {
      return nil
    }
    let rightHandSide = -columns[freeIndex]
    var result = Array(
      repeating: try ScalarInterval(lower: 0.0, upper: 0.0),
      count: columns.count
    )
    result[freeIndex] = try ScalarInterval(lower: 1.0, upper: 1.0)
    for dependentIndex in dependentColumns.indices {
      var numeratorColumns = dependentColumns
      numeratorColumns[dependentIndex] = rightHandSide
      let numerator = determinant(
        numeratorColumns[0],
        numeratorColumns[1],
        numeratorColumns[2]
      )
      guard numerator.isFinite,
        let quotient = numerator.divided(by: denominator),
        quotient.isFinite
      else {
        return nil
      }
      result[dependentIndexes[dependentIndex]] = try ScalarInterval(
        lower: quotient.lower,
        upper: quotient.upper
      )
    }
    return result
  }

  func diagnostic(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    lowerAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    tolerance: ModelingTolerance
  ) throws -> String {
    let columns = normalizedDerivativeColumns()
    let freeIndex = freeParameter.rawValue
    guard columns.indices.contains(freeIndex) else {
      return "invalid free parameter"
    }
    let dependentIndexes = columns.indices.filter { $0 != freeIndex }
    let dependentColumns = dependentIndexes.map { columns[$0] }
    let minor = determinant(
      dependentColumns[0],
      dependentColumns[1],
      dependentColumns[2]
    )
    guard let inverse = inverseRows(columns: dependentColumns.map(\.midpoint)) else {
      return "dependent minor=[\(minor.lower), \(minor.upper)]; midpoint inverse unavailable"
    }
    let functionValue = try affinePredictorResidualBounds(
      lowerAnchor: lowerAnchor,
      upperAnchor: upperAnchor,
      tolerance: tolerance
    )
    let normalizedLower = normalized(anchor: lowerAnchor)
    let normalizedUpper = normalized(anchor: upperAnchor)
    let centerBounds = dependentIndexes.map { index in
      OutwardScalarInterval.enclosing([
        normalizedLower[index],
        normalizedUpper[index],
      ])
    }
    let box = affinePredictorKrawczykBox(
      inverse: inverse,
      jacobian: jacobianRows(dependentColumns),
      functionValue: functionValue,
      centerBounds: centerBounds
    )
    return
      "dependent minor=[\(minor.lower), \(minor.upper)], predictor residual=\(functionValue.components.map { [$0.lower, $0.upper] }), Krawczyk box=\(box.map { [$0.lower, $0.upper] })"
  }

  private func normalizedDerivativeColumns() -> [IntervalVector] {
    [
      intervalVector(firstJet, at: \SurfaceIntervalJet.derivativeU)
        .scaled(by: OutwardScalarInterval(parameterBox.firstU.width)),
      intervalVector(firstJet, at: \SurfaceIntervalJet.derivativeV)
        .scaled(by: OutwardScalarInterval(parameterBox.firstV.width)),
      -intervalVector(secondJet, at: \SurfaceIntervalJet.derivativeU)
        .scaled(by: OutwardScalarInterval(parameterBox.secondU.width)),
      -intervalVector(secondJet, at: \SurfaceIntervalJet.derivativeV)
        .scaled(by: OutwardScalarInterval(parameterBox.secondV.width)),
    ]
  }

  private func parameterizedGraphAnalysis(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    tolerance: ModelingTolerance
  ) throws -> ParameterizedGraphAnalysis? {
    let columns = normalizedDerivativeColumns()
    let freeIndex = freeParameter.rawValue
    guard columns.indices.contains(freeIndex),
      columns.allSatisfy(\.isFinite)
    else {
      return nil
    }
    let dependentIndexes = columns.indices.filter { $0 != freeIndex }
    let dependentColumns = dependentIndexes.map { columns[$0] }
    let minor = determinant(
      dependentColumns[0],
      dependentColumns[1],
      dependentColumns[2]
    )
    guard minor.isFinite,
      minor.excludesZero,
      let inverse = inverseRows(columns: dependentColumns.map(\.midpoint))
    else {
      return nil
    }
    let actualCenter = parameterBox.intervals.map(\.midpoint)
    let functionModel = try parameterizedCenterTaylorModel(
      freeIndex: freeIndex,
      actualCenter: actualCenter,
      tolerance: tolerance
    )
    let functionRanges = functionModel.map(\.range)
    let functionValue = IntervalVector(
      x: functionRanges[0],
      y: functionRanges[1],
      z: functionRanges[2]
    )
    let jacobian = jacobianRows(dependentColumns)
    let krawczykModel = parameterizedKrawczykModel(
      inverse: inverse,
      jacobian: jacobian,
      functionModel: functionModel
    )
    let krawczykBox = krawczykModel.box
    let freeParameterBounds = feasibleFreeParameterBounds(
      model: krawczykModel,
      maximumDepth: 8
    )
    let gaussSeidelBox = hansenSenguptaBox(
      inverse: inverse,
      jacobian: jacobian,
      functionValue: functionValue
    )
    var provesEmpty =
      gaussSeidelBox?.isEmpty == true
      || freeParameterBounds == nil
    let box: [OutwardScalarInterval]
    if let gaussSeidelBox, gaussSeidelBox.isEmpty == false {
      var combined: [OutwardScalarInterval] = []
      combined.reserveCapacity(3)
      var intersectionIsEmpty = false
      for index in 0..<3 {
        guard
          let intersection = krawczykBox[index].intersection(
            with: gaussSeidelBox[index]
          )
        else {
          intersectionIsEmpty = true
          break
        }
        combined.append(intersection)
      }
      if intersectionIsEmpty {
        provesEmpty = true
        box = krawczykBox
      } else {
        box = combined
      }
    } else {
      box = krawczykBox
    }
    return ParameterizedGraphAnalysis(
      dependentIndexes: dependentIndexes,
      dependentMinor: minor,
      box: box,
      isStrictContraction: krawczykMapIsStrictContraction(
        inverse: inverse,
        jacobian: jacobian
      ),
      provesEmpty: provesEmpty,
      certifiesFullGraph: isStrictlyInsideUnitCube(krawczykBox)
        || (isInsideUnitCubeWithinRounding(krawczykBox)
          && krawczykMapIsStrictContraction(
            inverse: inverse,
            jacobian: jacobian
          )),
      freeParameterBounds: freeParameterBounds
        ?? (lower: 0.0, upper: 1.0)
    )
  }

  private func feasibleFreeParameterBounds(
    model: ParameterizedKrawczykModel,
    maximumDepth: Int
  ) -> (lower: Double, upper: Double)? {
    let unit = OutwardScalarInterval(lower: 0.0, upper: 1.0)
    var pending: [(lower: Double, upper: Double, depth: Int)] = [
      (lower: 0.0, upper: 1.0, depth: 0)
    ]
    var retained: [(lower: Double, upper: Double)] = []
    while let candidate = pending.popLast() {
      let boxes = model.box(
        overFreeParameterBounds: (
          lower: candidate.lower,
          upper: candidate.upper
        ))
      if boxes.contains(where: { $0.intersects(unit) == false }) {
        continue
      }
      let isEntirelyFeasible = boxes.allSatisfy {
        $0.lower >= 0.0 && $0.upper <= 1.0
      }
      if isEntirelyFeasible || candidate.depth >= maximumDepth {
        retained.append(
          (
            lower: candidate.lower,
            upper: candidate.upper
          ))
        continue
      }
      let middle =
        candidate.lower
        + (candidate.upper - candidate.lower) * 0.5
      guard middle > candidate.lower, middle < candidate.upper else {
        retained.append(
          (
            lower: candidate.lower,
            upper: candidate.upper
          ))
        continue
      }
      pending.append(
        (
          lower: middle,
          upper: candidate.upper,
          depth: candidate.depth + 1
        ))
      pending.append(
        (
          lower: candidate.lower,
          upper: middle,
          depth: candidate.depth + 1
        ))
    }
    guard let lower = retained.map(\.lower).min(),
      let upper = retained.map(\.upper).max()
    else {
      return nil
    }
    return (
      lower: max(0.0, lower.nextDown),
      upper: min(1.0, upper.nextUp)
    )
  }

  private func hansenSenguptaBox(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]],
    functionValue: IntervalVector
  ) -> [OutwardScalarInterval]? {
    let functionComponents = functionValue.components
    var preconditionedFunction = Array(
      repeating: OutwardScalarInterval.exact(0.0),
      count: 3
    )
    var preconditionedJacobian = Array(
      repeating: Array(
        repeating: OutwardScalarInterval.exact(0.0),
        count: 3
      ),
      count: 3
    )
    for row in 0..<3 {
      for inner in 0..<3 {
        let coefficient = OutwardScalarInterval(
          vectorComponent(inverse[row], index: inner)
        )
        preconditionedFunction[row] =
          preconditionedFunction[row]
          + coefficient * functionComponents[inner]
        for column in 0..<3 {
          preconditionedJacobian[row][column] =
            preconditionedJacobian[row][column]
            + coefficient * jacobian[inner][column]
        }
      }
    }
    var offsets = Array(
      repeating: OutwardScalarInterval(lower: -0.5, upper: 0.5),
      count: 3
    )
    for _ in 0..<8 {
      var changed = false
      for row in 0..<3 {
        var numerator = -preconditionedFunction[row]
        for column in 0..<3 where column != row {
          numerator =
            numerator
            - preconditionedJacobian[row][column] * offsets[column]
        }
        guard
          let candidate = numerator.divided(
            by: preconditionedJacobian[row][row]
          )
        else {
          return nil
        }
        guard let contracted = offsets[row].intersection(with: candidate) else {
          return []
        }
        if contracted.width < offsets[row].width {
          changed = true
        }
        offsets[row] = contracted
      }
      if changed == false { break }
    }
    let center = OutwardScalarInterval.exact(0.5)
    return offsets.map { center + $0 }
  }

  private func parameterizedCenterTaylorModel(
    freeIndex: Int,
    actualCenter: [Double],
    tolerance: ModelingTolerance
  ) throws -> [IntervalQuadraticPolynomial] {
    let firstDerivatives = try firstSurface.parameterDerivatives(
      atU: actualCenter[0],
      v: actualCenter[1],
      tolerance: tolerance
    )
    let secondDerivatives = try secondSurface.parameterDerivatives(
      atU: actualCenter[2],
      v: actualCenter[3],
      tolerance: tolerance
    )
    let centerResidual =
      firstDerivatives.position
      - secondDerivatives.position
    let parameterWidth = parameterBox.intervals[freeIndex].width
    let firstDerivative: Vector3D
    let secondDerivative: IntervalVector
    switch freeIndex {
    case 0:
      firstDerivative = firstDerivatives.tangentU * parameterWidth
      secondDerivative = intervalVector(
        firstJet,
        at: \SurfaceIntervalJet.secondDerivativeUU
      ).scaled(by: OutwardScalarInterval(parameterWidth * parameterWidth))
    case 1:
      firstDerivative = firstDerivatives.tangentV * parameterWidth
      secondDerivative = intervalVector(
        firstJet,
        at: \SurfaceIntervalJet.secondDerivativeVV
      ).scaled(by: OutwardScalarInterval(parameterWidth * parameterWidth))
    case 2:
      firstDerivative = secondDerivatives.tangentU * -parameterWidth
      secondDerivative = -intervalVector(
        secondJet,
        at: \SurfaceIntervalJet.secondDerivativeUU
      ).scaled(by: OutwardScalarInterval(parameterWidth * parameterWidth))
    default:
      firstDerivative = secondDerivatives.tangentV * -parameterWidth
      secondDerivative = -intervalVector(
        secondJet,
        at: \SurfaceIntervalJet.secondDerivativeVV
      ).scaled(by: OutwardScalarInterval(parameterWidth * parameterWidth))
    }
    let constants = [centerResidual.x, centerResidual.y, centerResidual.z]
    let linears = [firstDerivative.x, firstDerivative.y, firstDerivative.z]
    let quadratics = secondDerivative.components.map {
      $0 * OutwardScalarInterval.exact(0.5)
    }
    return (0..<3).map { index in
      IntervalQuadraticPolynomial(
        constant: OutwardScalarInterval(constants[index]),
        linear: OutwardScalarInterval(linears[index]),
        quadratic: quadratics[index]
      )
    }
  }

  private func affinePredictorResidualBounds(
    lowerAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    tolerance: ModelingTolerance
  ) throws -> IntervalVector {
    let lowerResidual = try residual(at: lowerAnchor, tolerance: tolerance)
    let upperResidual = try residual(at: upperAnchor, tolerance: tolerance)
    let delta = zip(upperAnchor.values, lowerAnchor.values).map {
      upper, lower in upper - lower
    }
    let firstSecond = secondDirectionalDerivative(
      jet: firstJet,
      deltaU: delta[0],
      deltaV: delta[1]
    )
    let secondSecond = secondDirectionalDerivative(
      jet: secondJet,
      deltaU: delta[2],
      deltaV: delta[3]
    )
    let secondResidual = firstSecond - secondSecond
    return IntervalVector(
      x: interpolationErrorBound(
        lower: lowerResidual.x,
        upper: upperResidual.x,
        secondDerivative: secondResidual.x
      ),
      y: interpolationErrorBound(
        lower: lowerResidual.y,
        upper: upperResidual.y,
        secondDerivative: secondResidual.y
      ),
      z: interpolationErrorBound(
        lower: lowerResidual.z,
        upper: upperResidual.z,
        secondDerivative: secondResidual.z
      )
    )
  }

  private func residual(
    at parameters: SurfaceIntersectionParameterPair,
    tolerance: ModelingTolerance
  ) throws -> IntervalVector {
    let first = try firstSurface.point(
      u: parameters.first.u,
      v: parameters.first.v,
      tolerance: tolerance
    )
    let second = try secondSurface.point(
      u: parameters.second.u,
      v: parameters.second.v,
      tolerance: tolerance
    )
    let difference = first - second
    return IntervalVector(
      x: OutwardScalarInterval(difference.x),
      y: OutwardScalarInterval(difference.y),
      z: OutwardScalarInterval(difference.z)
    )
  }

  private func secondDirectionalDerivative(
    jet: SurfaceIntervalVectorJet,
    deltaU: Double,
    deltaV: Double
  ) -> IntervalVector {
    let uu = intervalVector(jet, at: \SurfaceIntervalJet.secondDerivativeUU)
    let uv = intervalVector(jet, at: \SurfaceIntervalJet.secondDerivativeUV)
    let vv = intervalVector(jet, at: \SurfaceIntervalJet.secondDerivativeVV)
    return uu.scaled(by: OutwardScalarInterval(deltaU * deltaU))
      + uv.scaled(by: OutwardScalarInterval(2.0 * deltaU * deltaV))
      + vv.scaled(by: OutwardScalarInterval(deltaV * deltaV))
  }

  private func interpolationErrorBound(
    lower: OutwardScalarInterval,
    upper: OutwardScalarInterval,
    secondDerivative: OutwardScalarInterval
  ) -> OutwardScalarInterval {
    let linearRange = OutwardScalarInterval.enclosing([lower, upper])
    let error = (secondDerivative.absoluteUpperBound / 8.0).nextUp
    return linearRange + OutwardScalarInterval(lower: -error, upper: error)
  }

  private func normalized(anchor: SurfaceIntersectionParameterPair) -> [Double] {
    zip(anchor.values, parameterBox.intervals).map { value, interval in
      (value - interval.lower) / interval.width
    }
  }

  private func intervalVector(
    _ jet: SurfaceIntervalVectorJet,
    at keyPath: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>
  ) -> IntervalVector {
    IntervalVector(
      x: jet.x[keyPath: keyPath],
      y: jet.y[keyPath: keyPath],
      z: jet.z[keyPath: keyPath]
    )
  }

  private func jacobianRows(_ columns: [IntervalVector]) -> [[OutwardScalarInterval]] {
    [columns.map(\.x), columns.map(\.y), columns.map(\.z)]
  }

  private func affinePredictorKrawczykBox(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]],
    functionValue: IntervalVector,
    centerBounds: [OutwardScalarInterval]
  ) -> [OutwardScalarInterval] {
    let functionComponents = functionValue.components
    let unit = OutwardScalarInterval(lower: 0.0, upper: 1.0)
    return (0..<3).map { row in
      var component = centerBounds[row]
      for inner in 0..<3 {
        component =
          component
          - OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
          * functionComponents[inner]
      }
      for column in 0..<3 {
        var preconditioned = OutwardScalarInterval.exact(0.0)
        for inner in 0..<3 {
          preconditioned =
            preconditioned
            + OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
            * jacobian[inner][column]
        }
        let identity = OutwardScalarInterval.exact(row == column ? 1.0 : 0.0)
        component =
          component
          + (identity - preconditioned) * (unit - centerBounds[column])
      }
      return component
    }
  }

  private func parameterizedKrawczykModel(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]],
    functionModel: [IntervalQuadraticPolynomial]
  ) -> ParameterizedKrawczykModel {
    let radius = OutwardScalarInterval(lower: -0.5, upper: 0.5)
    var predictors: [IntervalQuadraticPolynomial] = []
    var remainders: [OutwardScalarInterval] = []
    predictors.reserveCapacity(3)
    remainders.reserveCapacity(3)
    for row in 0..<3 {
      var preconditionedFunction = IntervalQuadraticPolynomial.zero
      for inner in 0..<3 {
        preconditionedFunction =
          preconditionedFunction
          + functionModel[inner].scaled(
            by: OutwardScalarInterval(
              vectorComponent(inverse[row], index: inner)
            )
          )
      }
      let predictor = IntervalQuadraticPolynomial(
        constant: OutwardScalarInterval.exact(0.5)
          - preconditionedFunction.constant,
        linear: -preconditionedFunction.linear,
        quadratic: -preconditionedFunction.quadratic
      )
      var remainder = OutwardScalarInterval.exact(0.0)
      for column in 0..<3 {
        var preconditioned = OutwardScalarInterval.exact(0.0)
        for inner in 0..<3 {
          preconditioned =
            preconditioned
            + OutwardScalarInterval(
              vectorComponent(inverse[row], index: inner)
            ) * jacobian[inner][column]
        }
        let identity = OutwardScalarInterval.exact(
          row == column ? 1.0 : 0.0
        )
        remainder = remainder + (identity - preconditioned) * radius
      }
      predictors.append(predictor)
      remainders.append(remainder)
    }
    let box = zip(predictors, remainders).map { predictor, remainder in
      predictor.range + remainder
    }
    return ParameterizedKrawczykModel(
      predictors: predictors,
      remainders: remainders,
      box: box
    )
  }

  private func affinePredictorProvesFullGraph(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]],
    functionValue: IntervalVector,
    centerBounds: [OutwardScalarInterval]
  ) -> Bool {
    let functionComponents = functionValue.components
    var corrections = Array(repeating: 0.0, count: 3)
    var contraction = Array(
      repeating: Array(repeating: 0.0, count: 3),
      count: 3
    )
    for row in 0..<3 {
      var correction = OutwardScalarInterval.exact(0.0)
      for inner in 0..<3 {
        correction =
          correction
          + OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
          * functionComponents[inner]
      }
      corrections[row] = correction.absoluteUpperBound
      for column in 0..<3 {
        var preconditioned = OutwardScalarInterval.exact(0.0)
        for inner in 0..<3 {
          preconditioned =
            preconditioned
            + OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
            * jacobian[inner][column]
        }
        let identity = OutwardScalarInterval.exact(row == column ? 1.0 : 0.0)
        contraction[row][column] =
          (identity - preconditioned)
          .absoluteUpperBound
      }
    }
    let availableRadii = centerBounds.map {
      min($0.lower, 1.0 - $0.upper)
    }
    guard corrections.allSatisfy({ $0.isFinite && $0 >= 0.0 }),
      contraction.flatMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0.0 }),
      availableRadii.allSatisfy({ $0.isFinite && $0 > 0.0 })
    else {
      return false
    }
    var radii = corrections.map { max($0, Double.leastNonzeroMagnitude) }
    for _ in 0..<128 {
      let mapped = (0..<3).map { row in
        contraction[row].indices.reduce(corrections[row]) {
          partial, column in
          (partial + contraction[row][column] * radii[column]).nextUp
        }
      }
      guard
        zip(mapped, availableRadii).allSatisfy({ value, available in
          value.isFinite && value < available
        })
      else {
        return false
      }
      let trial = mapped.map {
        ($0 * (1.0 + 1.0e-10)).nextUp
          + Double.ulpOfOne * 1_024.0
      }
      let remapped = (0..<3).map { row in
        contraction[row].indices.reduce(corrections[row]) {
          partial, column in
          (partial + contraction[row][column] * trial[column]).nextUp
        }
      }
      if zip(remapped, trial).allSatisfy({ $0 < $1 }),
        zip(trial, availableRadii).allSatisfy({ $0 < $1 })
      {
        return true
      }
      radii = mapped
    }
    return false
  }

  private func krawczykMapIsStrictContraction(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]]
  ) -> Bool {
    (0..<3).allSatisfy { row in
      let rowSum = (0..<3).reduce(0.0) { sum, column in
        var preconditioned = OutwardScalarInterval.exact(0.0)
        for inner in 0..<3 {
          preconditioned =
            preconditioned
            + OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
            * jacobian[inner][column]
        }
        let identity = OutwardScalarInterval.exact(row == column ? 1.0 : 0.0)
        return (sum + (identity - preconditioned).absoluteUpperBound).nextUp
      }
      return rowSum.isFinite && rowSum < 1.0
    }
  }

  private func isStrictlyInsideUnitCube(
    _ box: [OutwardScalarInterval]
  ) -> Bool {
    box.allSatisfy { $0.lower > 0.0 && $0.upper < 1.0 }
  }

  private func isInsideUnitCubeWithinRounding(
    _ box: [OutwardScalarInterval]
  ) -> Bool {
    let slack = Double.ulpOfOne * 4_096.0
    return box.allSatisfy {
      $0.lower >= -slack && $0.upper <= 1.0 + slack
    }
  }

  private func inverseRows(columns: [Vector3D]) -> [Vector3D]? {
    guard columns.count == 3 else { return nil }
    let firstCross = columns[1].cross(columns[2])
    let determinant = columns[0].dot(firstCross)
    let scale = columns.map(\.length).max() ?? .infinity
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
      firstCross / determinant,
      columns[2].cross(columns[0]) / determinant,
      columns[0].cross(columns[1]) / determinant,
    ]
  }

  private func determinant(
    _ first: IntervalVector,
    _ second: IntervalVector,
    _ third: IntervalVector
  ) -> OutwardScalarInterval {
    let crossX = second.y * third.z - second.z * third.y
    let crossY = second.z * third.x - second.x * third.z
    let crossZ = second.x * third.y - second.y * third.x
    return first.x * crossX + first.y * crossY + first.z * crossZ
  }

  private func vectorComponent(_ vector: Vector3D, index: Int) -> Double {
    switch index {
    case 0: vector.x
    case 1: vector.y
    default: vector.z
    }
  }
}
