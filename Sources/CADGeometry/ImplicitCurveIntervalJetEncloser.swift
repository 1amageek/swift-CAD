import CADCore

package struct ImplicitCurveIntervalJetEncloser: Sendable {
  private struct PreparedSurfaces: Sendable {
    let intersection: CertifiedImplicitIntersectionCurve
    let tolerance: ModelingTolerance
    let first: PreparedSurfaceDifferentialEncloser
    let second: PreparedSurfaceDifferentialEncloser
    let parameterDerivativeBounds: [[ScalarInterval]]
    let exactIsoparametricGraph: ExactIsoparametricPlanarIntersectionGraph?
    let maximumSpanCount: Int?
    let maximumSubdivisionDepth: Int?
    let remainingSourceDepth: Int?
    let admission: SurfaceSurfaceQueryAdmission?

    init(intersection: CertifiedImplicitIntersectionCurve, tolerance: ModelingTolerance,
      first: PreparedSurfaceDifferentialEncloser, second: PreparedSurfaceDifferentialEncloser,
      parameterDerivativeBounds: [[ScalarInterval]],
      exactIsoparametricGraph: ExactIsoparametricPlanarIntersectionGraph?,
      maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
      remainingSourceDepth: Int? = nil, admission: SurfaceSurfaceQueryAdmission? = nil) {
      self.intersection = intersection; self.tolerance = tolerance
      self.first = first; self.second = second
      self.parameterDerivativeBounds = parameterDerivativeBounds
      self.exactIsoparametricGraph = exactIsoparametricGraph
      self.maximumSpanCount = maximumSpanCount
      self.maximumSubdivisionDepth = maximumSubdivisionDepth
      self.remainingSourceDepth = remainingSourceDepth
      self.admission = admission
    }
  }

  fileprivate enum ParameterEnclosurePhase: Sendable {
    case range
    case lowerEndpoint(CertifiedImplicitParameterIntervalJet, SurfaceIntersectionParameterBox)
    case upperEndpoint(CertifiedImplicitParameterIntervalJet, SurfaceIntersectionParameterBox,
                       CertifiedImplicitParameterIntervalJet)
  }

  /// Opaque root ownership for one original cell and one closed query interval.
  /// Endpoint phases hold a subset; only the final jet encloses the whole query.
  package struct ParameterEnclosureState: Sendable {
    fileprivate let intersection: CertifiedImplicitIntersectionCurve
    fileprivate let cellIndex: Int
    fileprivate let parameterBox: SurfaceIntersectionParameterBox
    fileprivate let tolerance: ModelingTolerance
    fileprivate let originalInterval: ScalarInterval
    fileprivate let phase: ParameterEnclosurePhase

    fileprivate init(intersection: CertifiedImplicitIntersectionCurve, cellIndex: Int,
                     parameterBox: SurfaceIntersectionParameterBox, tolerance: ModelingTolerance,
                     originalInterval: ScalarInterval, phase: ParameterEnclosurePhase) {
      self.intersection = intersection
      self.cellIndex = cellIndex
      self.parameterBox = parameterBox
      self.tolerance = tolerance
      self.originalInterval = originalInterval
      self.phase = phase
    }
  }

  package enum ParameterEnclosureStep: Sendable {
    case enclosed(CertifiedImplicitParameterIntervalJet)
    /// A root-box contraction or bounded endpoint-phase transition, charged by the caller.
    case contracted(ParameterEnclosureState)
    case subdivisionRequired
  }

  private struct IntervalVector: Sendable {
    let x: OutwardScalarInterval
    let y: OutwardScalarInterval
    let z: OutwardScalarInterval

    static let zero = IntervalVector(
      x: OutwardScalarInterval(0.0),
      y: OutwardScalarInterval(0.0),
      z: OutwardScalarInterval(0.0)
    )

    static func + (lhs: IntervalVector, rhs: IntervalVector) -> IntervalVector {
      IntervalVector(
        x: lhs.x + rhs.x,
        y: lhs.y + rhs.y,
        z: lhs.z + rhs.z
      )
    }

    static func - (lhs: IntervalVector, rhs: IntervalVector) -> IntervalVector {
      IntervalVector(
        x: lhs.x - rhs.x,
        y: lhs.y - rhs.y,
        z: lhs.z - rhs.z
      )
    }

    static prefix func - (value: IntervalVector) -> IntervalVector {
      IntervalVector(x: -value.x, y: -value.y, z: -value.z)
    }

    static func * (
      lhs: IntervalVector,
      rhs: OutwardScalarInterval
    ) -> IntervalVector {
      IntervalVector(
        x: lhs.x * rhs,
        y: lhs.y * rhs,
        z: lhs.z * rhs
      )
    }

    func cross(_ other: IntervalVector) -> IntervalVector {
      IntervalVector(
        x: y * other.z - z * other.y,
        y: z * other.x - x * other.z,
        z: x * other.y - y * other.x
      )
    }

    func dot(_ other: IntervalVector) -> OutwardScalarInterval {
      x * other.x + y * other.y + z * other.z
    }

    func union(_ other: IntervalVector) -> IntervalVector {
      IntervalVector(
        x: x.union(other.x),
        y: y.union(other.y),
        z: z.union(other.z)
      )
    }

    var isFinite: Bool {
      x.isFinite && y.isFinite && z.isFinite
    }
  }

  private struct CurveIntervalJet: Sendable {
    let position: IntervalVector
    let firstDerivative: IntervalVector
    let secondDerivative: IntervalVector
    let thirdDerivative: IntervalVector
    let parameters: [ParameterCoordinateIntervalJet]

    func union(_ other: CurveIntervalJet) -> CurveIntervalJet {
      CurveIntervalJet(
        position: position.union(other.position),
        firstDerivative: firstDerivative.union(other.firstDerivative),
        secondDerivative: secondDerivative.union(other.secondDerivative),
        thirdDerivative: thirdDerivative.union(other.thirdDerivative),
        parameters: zip(parameters, other.parameters).map { $0.union($1) }
      )
    }

    var isFinite: Bool {
      position.isFinite
        && firstDerivative.isFinite
        && secondDerivative.isFinite
        && thirdDerivative.isFinite
        && parameters.allSatisfy({ $0.isFinite })
    }
  }

  private struct ParameterCoordinateIntervalJet: Sendable {
    let value: OutwardScalarInterval
    let firstDerivative: OutwardScalarInterval
    let secondDerivative: OutwardScalarInterval
    let thirdDerivative: OutwardScalarInterval

    func union(
      _ other: ParameterCoordinateIntervalJet
    ) -> ParameterCoordinateIntervalJet {
      ParameterCoordinateIntervalJet(
        value: value.union(other.value),
        firstDerivative: firstDerivative.union(other.firstDerivative),
        secondDerivative: secondDerivative.union(other.secondDerivative),
        thirdDerivative: thirdDerivative.union(other.thirdDerivative)
      )
    }

    var isFinite: Bool {
      value.isFinite
        && firstDerivative.isFinite
        && secondDerivative.isFinite
        && thirdDerivative.isFinite
    }
  }

  private let preparedSurfaces: PreparedSurfaces?

  package init() {
    preparedSurfaces = nil
  }

  package init(
    intersection: CertifiedImplicitIntersectionCurve,
    tolerance: ModelingTolerance
  ) throws {
    let exactIsoparametricGraph: ExactIsoparametricPlanarIntersectionGraph?
    if case .bSpline(let firstSurface) = intersection.firstSurface,
      case .bSpline(let secondSurface) = intersection.secondSurface
    {
      exactIsoparametricGraph =
        try ExactIsoparametricPlanarIntersectionGraph
        .certified(
          first: firstSurface,
          second: secondSurface,
          tolerance: tolerance
        )
    } else {
      exactIsoparametricGraph = nil
    }
    let preparedFirstSurface = try PreparedSurfaceDifferentialEncloser(
      surface: intersection.firstSurface,
      tolerance: tolerance
    )
    let preparedSecondSurface = try PreparedSurfaceDifferentialEncloser(
      surface: intersection.secondSurface,
      tolerance: tolerance
    )
    preparedSurfaces = try PreparedSurfaces(
      intersection: intersection,
      tolerance: tolerance,
      first: preparedFirstSurface,
      second: preparedSecondSurface,
      parameterDerivativeBounds: intersection.cells.map { cell in
        try cell.parameterDerivativeBounds(
          firstSurface: preparedFirstSurface,
          secondSurface: preparedSecondSurface,
          tolerance: tolerance
        )
      },
      exactIsoparametricGraph: exactIsoparametricGraph
    )
  }

  /// Caller-owned closed localization preparation; no derivative-bound fitting is used.
  package init(localizing intersection: CertifiedImplicitIntersectionCurve,
       tolerance: ModelingTolerance, consumeWork: () throws -> Void) throws {
    try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
    try intersection.validateCertificationContract(tolerance: tolerance)
    let first = try PreparedSurfaceDifferentialEncloser(surface: intersection.firstSurface,
      tolerance: tolerance, consumeWork: consumeWork)
    let second = try PreparedSurfaceDifferentialEncloser(surface: intersection.secondSurface,
      tolerance: tolerance, consumeWork: consumeWork)
    preparedSurfaces = PreparedSurfaces(intersection: intersection, tolerance: tolerance,
      first: first, second: second, parameterDerivativeBounds: [], exactIsoparametricGraph: nil)
  }

  /// Original preparation under the composing caller's explicit limits and bytes.
  package init(localizing intersection: CertifiedImplicitIntersectionCurve,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws {
    try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
    guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0 else {
      throw GeometryConversionError.invalidInput("Original implicit localization needs caller span and remaining source admission.")
    }
    try intersection.validateCertificationContract(tolerance: tolerance)
    let first = try PreparedSurfaceDifferentialEncloser(surface: intersection.firstSurface,
      tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
      maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork,
      consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
    let second = try PreparedSurfaceDifferentialEncloser(surface: intersection.secondSurface,
      tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
      maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork,
      consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
    try OriginalCoefficientAllocation.reserve(count: 1, of: PreparedSurfaces.self, consumeStorage: consumeStorage)
    preparedSurfaces = PreparedSurfaces(intersection: intersection, tolerance: tolerance,
      first: first, second: second, parameterDerivativeBounds: [], exactIsoparametricGraph: nil,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth - 1)
  }

  /// Retains both original support preparations and their composing admission.
  package init(localizing intersection: CertifiedImplicitIntersectionCurve,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws {
    try admission.step()
    guard admission.remainingSourceDepth > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Original implicit preparation exhausted source depth.")
    }
    try intersection.validateCertificationContract(tolerance: tolerance)
    let child = try admission.descendingSource()
    let first = try child.prepare(intersection.firstSurface, tolerance: tolerance)
    let second = try child.prepare(intersection.secondSurface, tolerance: tolerance)
    try admission.reserve(count: 1, stride: MemoryLayout<PreparedSurfaces>.stride)
    preparedSurfaces = PreparedSurfaces(intersection: intersection, tolerance: tolerance,
      first: first, second: second, parameterDerivativeBounds: [], exactIsoparametricGraph: nil,
      maximumSpanCount: admission.maximumSpanCount,
      maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
      remainingSourceDepth: child.remainingSourceDepth, admission: child)
  }

  /// Restricts the graph source carried by this immutable preparation.
  package func restrictedBounds(cellIndex: Int,
    fromNormalizedFraction lowerFraction: Double, toNormalizedFraction upperFraction: Double,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission)
    throws -> CertifiedImplicitIntersectionGraphSubcell {
    try admission.step()
    guard let preparedSurfaces, preparedSurfaces.tolerance == tolerance,
      preparedSurfaces.intersection.cells.indices.contains(cellIndex) else {
      throw GeometryConversionError.invalidInput("Original implicit restriction requires its prepared graph and tolerance.")
    }
    let cell = preparedSurfaces.intersection.cells[cellIndex]
    let derivatives = try cell.parameterDerivativeBounds(firstSurface: preparedSurfaces.first,
      secondSurface: preparedSurfaces.second, tolerance: tolerance, admission: admission)
    return try cell.restrictedBounds(fromNormalizedFraction: lowerFraction,
      toNormalizedFraction: upperFraction, firstSurface: preparedSurfaces.first,
      secondSurface: preparedSurfaces.second, parentDerivativeBounds: derivatives,
      tolerance: tolerance, admission: admission)
  }

  /// One bounded prepare operation. The caller charges this and every advance
  /// to the same work counter; the localizer owns no recursive work allowance.
  package func prepareParameterEnclosure(
    of curve: CertifiedImplicitIntersectionCurve, cellIndex: Int,
    overClosedInterval interval: ScalarInterval, tolerance: ModelingTolerance,
    consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
    consumeStorage: ((Int) throws -> Void)? = nil
  ) throws -> ParameterEnclosureState {
    try checkLocalizationCancellation(tolerance); try consumeWork()
    try chargeOwnerComparison(curve, consumeWork: consumeWork)
    try curve.validateCertificationContract(tolerance:tolerance)
    guard let preparedSurfaces, preparedSurfaces.intersection == curve,
          preparedSurfaces.tolerance == tolerance,
          curve.cells.indices.contains(cellIndex), interval.lower >= 0, interval.upper <= 1 else {
      throw invalidInput(tolerance:tolerance,message:"Implicit localization requires its exact prepared owner and original closed interval.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Whole chains crossing critical cells
    // still need a regular atlas and exact join identity. This cell-local source
    // path keeps its own certified free coordinate and direction; it does not
    // promote a union of one-sided derivative ranges into a smooth chain proof.
    guard !curve.cells.isEmpty else {
      throw invalidInput(tolerance: tolerance, message: "Implicit localization requires an original certified graph cell.")
    }
    let cell = curve.cells[cellIndex]
    try OriginalCoefficientAllocation.reserve(count: 4, of: ScalarInterval.self, consumeStorage: consumeStorage)
    var bounds = cell.parameterBox.intervals
    bounds[cell.freeParameter.rawValue] = try nativeFreeInterval(cell, over: interval, tolerance: tolerance)
    return ParameterEnclosureState(intersection:curve,cellIndex:cellIndex,
      parameterBox:parameterBox(bounds),tolerance:tolerance,originalInterval:interval,phase:.range)
  }

  /// One bounded restriction of the original containing four-parameter root cover.
  package func prepareParameterEnclosure(
    restricting parent: ParameterEnclosureState, cellIndex: Int? = nil,
    overClosedInterval interval: ScalarInterval,
    tolerance: ModelingTolerance,
    consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
    consumeStorage: ((Int) throws -> Void)? = nil
  ) throws -> ParameterEnclosureState {
    try checkLocalizationCancellation(tolerance); try consumeWork()
    try chargeOwnerComparison(parent.intersection, consumeWork: consumeWork)
    guard let preparedSurfaces, preparedSurfaces.intersection == parent.intersection,
          preparedSurfaces.tolerance == tolerance, parent.tolerance == tolerance,
          parent.intersection.cells.indices.contains(parent.cellIndex),
          cellIndex == nil || cellIndex == parent.cellIndex,
          interval.lower.isFinite, interval.upper.isFinite, interval.lower <= interval.upper,
          interval.lower >= parent.originalInterval.lower,
          interval.upper <= parent.originalInterval.upper else {
      throw invalidInput(tolerance:tolerance,
        message:"Implicit child localization requires its exact containing original root owner.")
    }
    let wholeBox: SurfaceIntersectionParameterBox
    switch parent.phase {
    case .range: wholeBox = parent.parameterBox
    case .lowerEndpoint(_, let box), .upperEndpoint(_, let box, _): wholeBox = box
    }
    let cell = parent.intersection.cells[parent.cellIndex]
    let freeIndex = cell.freeParameter.rawValue
    let free = try nativeFreeInterval(cell,over:interval,tolerance:tolerance)
    try OriginalCoefficientAllocation.reserve(count: 4, of: ScalarInterval.self, consumeStorage: consumeStorage)
    var bounds = wholeBox.intervals
    if case .upperEndpoint(let rangeJet, _, let lowerJet) = parent.phase {
      // These are actual original endpoint-root jets and a certified whole-range
      // third bound. Their Taylor enclosure is a root cover, never a point solve.
      let localDelta = OutwardScalarInterval(lower:interval.lower,upper:interval.upper)
        - .exact(parent.originalInterval.lower)
      let delta: OutwardScalarInterval
      if parent.intersection.cells.count == 1 { delta = localDelta }
      else {
        guard let globalDelta = localDelta.divided(by:.exact(Double(parent.intersection.cells.count))),
              globalDelta.isFinite else {
          throw arithmeticFailure(tolerance:tolerance,
            message:"Original root restriction could not preserve global cell-fraction scaling.")
        }
        delta = globalDelta
      }
      let square = delta*delta, cube = square*delta
      func outward(_ value: ScalarInterval) -> OutwardScalarInterval {
        OutwardScalarInterval(lower:value.lower,upper:value.upper)
      }
      for index in bounds.indices {
        try consumeWork()
        let point = lowerJet.coordinates[index]
        let cover = outward(point.value) + outward(point.firstDerivative)*delta
          + outward(point.secondDerivative)*square * .exact(0.5)
          + outward(rangeJet.coordinates[index].thirdDerivative)*cube * OutwardScalarInterval(1.0/6)
        guard cover.isFinite else {
          throw arithmeticFailure(tolerance:tolerance,
            message:"Original endpoint Taylor root cover exceeded finite arithmetic.")
        }
        guard let intersection = cover.intersection(with:outward(bounds[index])) else {
          throw certificationFailure(tolerance:tolerance,
            message:"Original endpoint Taylor root cover contradicts its containing range box.")
        }
        bounds[index] = try scalarInterval(intersection)
      }
    }
    guard let restricted = OutwardScalarInterval(lower:free.lower,upper:free.upper).intersection(
      with:OutwardScalarInterval(lower:bounds[freeIndex].lower,upper:bounds[freeIndex].upper)) else {
      throw certificationFailure(tolerance:tolerance,
        message:"Implicit child free interval contradicts its original whole root cover.")
    }
    bounds[freeIndex] = try scalarInterval(restricted)
    return ParameterEnclosureState(intersection:parent.intersection,cellIndex:parent.cellIndex,
      parameterBox:parameterBox(bounds),tolerance:tolerance,originalInterval:interval,phase:.range)
  }

  /// One outward Krawczyk contraction retaining every already-certified root.
  /// Numeric centers select a preconditioner; they never certify a point root.
  package func advanceParameterEnclosure(
    _ state: ParameterEnclosureState, tolerance: ModelingTolerance,
    maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil, remainingSourceDepth: Int = 0,
    consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
    consumeStorage: ((Int) throws -> Void)? = nil
  ) throws -> ParameterEnclosureStep {
    try checkLocalizationCancellation(tolerance); try consumeWork()
    try chargeOwnerComparison(state.intersection, consumeWork: consumeWork)
    guard let preparedSurfaces,preparedSurfaces.intersection == state.intersection,
          preparedSurfaces.tolerance == state.tolerance,
          tolerance == state.tolerance,state.intersection.cells.indices.contains(state.cellIndex) else {
      throw invalidInput(tolerance:tolerance,message:"Implicit localization state belongs to another prepared owner or tolerance.")
    }
    let admittedSpans = minimumLimit(maximumSpanCount, preparedSurfaces.maximumSpanCount)
    let admittedDepth = minimumLimit(maximumSubdivisionDepth, preparedSurfaces.maximumSubdivisionDepth)
    let admittedSourceDepth = preparedSurfaces.remainingSourceDepth.map {
      maximumSpanCount == nil && maximumSubdivisionDepth == nil ? $0 : min($0, remainingSourceDepth)
    } ?? remainingSourceDepth
    if let admittedSpans, admittedSpans <= 0 {
      throw GeometryConversionError.resourceLimitExceeded("Implicit localization exhausted original span admission.")
    }
    if let admittedDepth, admittedDepth < 0 {
      throw GeometryConversionError.resourceLimitExceeded("Implicit localization exhausted original subdivision admission.")
    }
    let cell = state.intersection.cells[state.cellIndex]
    let freeIndex = cell.freeParameter.rawValue
    try OriginalCoefficientAllocation.reserve(count: 3, of: Int.self, consumeStorage: consumeStorage)
    var dependent: [Int] = []; dependent.reserveCapacity(3)
    for index in 0..<4 { try consumeWork(); if index != freeIndex { dependent.append(index) } }
    let jets: (first: SurfaceIntervalVectorJet, second: SurfaceIntervalVectorJet)
    do {
      jets = try closedSurfaceJets(over: state.parameterBox, prepared: preparedSurfaces, tolerance: tolerance,
        maximumSpanCount: admittedSpans, maximumSubdivisionDepth: admittedDepth,
        remainingSourceDepth: admittedSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    }
    catch let error as KernelError where error.code == .unsupportedCapability {
      guard let maximumSpanCount = admittedSpans, let maximumSubdivisionDepth = admittedDepth else { throw error }
      func original(_ surface: Surface3D, _ box: SurfaceParameterBox) throws -> SurfaceIntervalVectorJet {
        try OriginalSurfaceHigherJetProvider.intervalTaylorJet(of: surface, over: box,
          tolerance: tolerance, throughOrder: 4, maximumSpanCount: maximumSpanCount,
          maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: admittedSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
      }
      jets = try (original(state.intersection.firstSurface,
        SurfaceParameterBox(u: state.parameterBox.firstU, v: state.parameterBox.firstV)),
        original(state.intersection.secondSurface,
          SurfaceParameterBox(u: state.parameterBox.secondU, v: state.parameterBox.secondV)))
    }
    try OriginalCoefficientAllocation.reserve(count: 4, of: IntervalVector.self, consumeStorage: consumeStorage)
    let columns = derivativeColumns(first:jets.first,second:jets.second)
    try OriginalCoefficientAllocation.reserve(count: 3, of: IntervalVector.self, consumeStorage: consumeStorage)
    let dependentColumns = try dependent.map { try consumeWork(); return columns[$0] }
    for column in columns {
      try consumeWork()
      guard column.isFinite else {
        throw arithmeticFailure(tolerance:tolerance,message:"Implicit localization has nonfinite source Jacobian bounds.")
      }
    }
    guard let inverse = try inverseRows(dependentColumns, consumeWork: consumeWork, consumeStorage: consumeStorage) else { return .subdivisionRequired }
    try OriginalCoefficientAllocation.reserve(count: 4, of: ScalarInterval.self, consumeStorage: consumeStorage)
    let bounds = state.parameterBox.intervals
    try OriginalCoefficientAllocation.reserve(count: 4, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
    let centers = try bounds.map { try consumeWork(); return OutwardScalarInterval.exact($0.midpoint) }
    func centerPosition(_ prepared: PreparedSurfaceDifferentialEncloser,
      u: OutwardScalarInterval, v: OutwardScalarInterval) throws -> IntervalVector3DBounds {
      if let admittedSpans, let admittedDepth {
        return try prepared.positionBounds(over: SurfaceParameterBox(
          u: scalarInterval(u), v: scalarInterval(v)), tolerance: tolerance,
          maximumSpanCount: admittedSpans, maximumSubdivisionDepth: admittedDepth,
          remainingSourceDepth: admittedSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      }
      try consumeWork()
      return try prepared.pointValue(u: u.lower, v: v.lower, tolerance: tolerance)
    }
    let centerFirst = try centerPosition(preparedSurfaces.first, u: centers[0], v: centers[1])
    let centerSecond = try centerPosition(preparedSurfaces.second, u: centers[2], v: centers[3])
    // The exact-center point owner avoids interval-conditioning padding.
    // The mean-value segment in the retained convex box then encloses the
    // residual for every original free value while dependent centers stay fixed.
    let freeDisplacement = OutwardScalarInterval(lower:bounds[freeIndex].lower,
      upper:bounds[freeIndex].upper) - centers[freeIndex]
    let residual = IntervalVector(x:centerFirst.x,y:centerFirst.y,z:centerFirst.z)
      - IntervalVector(x:centerSecond.x,y:centerSecond.y,z:centerSecond.z)
      + columns[freeIndex]*freeDisplacement
    guard residual.isFinite else {
      throw arithmeticFailure(tolerance:tolerance,message:"Implicit localization has a nonfinite outward center residual.")
    }
    try OriginalCoefficientAllocation.reserve(count: bounds.count, of: ScalarInterval.self, consumeStorage: consumeStorage)
    var contracted = bounds
    var changed = false
    for row in dependent.indices {
      try consumeWork()
      let coordinate = dependent[row]
      var image = centers[coordinate] - inverse[row].dot(residual)
      for column in dependent.indices {
        try consumeWork()
        let entry = OutwardScalarInterval.exact(row == column ? 1 : 0)
          - inverse[row].dot(dependentColumns[column])
        let displacement = OutwardScalarInterval(lower:bounds[dependent[column]].lower,
          upper:bounds[dependent[column]].upper) - centers[dependent[column]]
        image = image + entry*displacement
      }
      guard image.isFinite else {
        throw arithmeticFailure(tolerance:tolerance,message:"Implicit localization exceeded finite Krawczyk arithmetic.")
      }
      guard let intersection = image.intersection(with:OutwardScalarInterval(
        lower:bounds[coordinate].lower,upper:bounds[coordinate].upper)) else {
        throw certificationFailure(tolerance:tolerance,message:"Implicit localization contradicted its retained root certificate.")
      }
      contracted[coordinate] = try scalarInterval(intersection)
      changed = changed || intersection.lower > bounds[coordinate].lower || intersection.upper < bounds[coordinate].upper
    }
    if changed {
      return .contracted(ParameterEnclosureState(intersection:state.intersection,cellIndex:state.cellIndex,
        parameterBox:parameterBox(contracted),tolerance:tolerance,
        originalInterval:state.originalInterval,phase:state.phase))
    }
    let denominator = determinant(dependentColumns)
    guard denominator.isFinite,denominator.excludesZero else { return .subdivisionRequired }
    let native = cell.parameterBox.interval(for:cell.freeParameter)
    var freeSlope = (OutwardScalarInterval.exact(native.upper) - .exact(native.lower))
      * .exact(Double(state.intersection.cells.count))
    if cell.direction == .reversed { freeSlope = -freeSlope }
    var first = try solveDependentDerivatives(columns:dependentColumns,dependentIndexes:dependent,
      rightHandSide:-columns[freeIndex]*freeSlope,denominator:denominator,tolerance:tolerance,order:"first", consumeWork: consumeWork, consumeStorage: consumeStorage)
    first[freeIndex] = freeSlope
    let firstQuadratic = surfaceQuadratic(jets.first,derivativeU:first[0],derivativeV:first[1])
    let secondQuadratic = surfaceQuadratic(jets.second,derivativeU:first[2],derivativeV:first[3])
    let second = try solveDependentDerivatives(columns:dependentColumns,dependentIndexes:dependent,
      rightHandSide:-(firstQuadratic-secondQuadratic),denominator:denominator,tolerance:tolerance,order:"second", consumeWork: consumeWork, consumeStorage: consumeStorage)
    let firstCubic = surfaceCubic(jets.first,firstU:first[0],firstV:first[1],secondU:second[0],secondV:second[1])
    let secondCubic = surfaceCubic(jets.second,firstU:first[2],firstV:first[3],secondU:second[2],secondV:second[3])
    let third = try solveDependentDerivatives(columns:dependentColumns,dependentIndexes:dependent,
      rightHandSide:-(firstCubic-secondCubic),denominator:denominator,tolerance:tolerance,order:"third", consumeWork: consumeWork, consumeStorage: consumeStorage)
    for index in first.indices {
      try consumeWork()
      guard first[index].isFinite, second[index].isFinite, third[index].isFinite else {
        throw arithmeticFailure(tolerance:tolerance,message:"Implicit localized derivatives exceeded finite arithmetic.")
      }
    }
    try OriginalCoefficientAllocation.reserve(count: bounds.count, of: CertifiedImplicitParameterIntervalJet.Coordinate.self, consumeStorage: consumeStorage)
    let jet = CertifiedImplicitParameterIntervalJet(coordinates:try bounds.indices.map {
      try consumeWork()
      return try CertifiedImplicitParameterIntervalJet.Coordinate(value:bounds[$0],
        firstDerivative:scalarInterval(first[$0]),secondDerivative:scalarInterval(second[$0]),
        thirdDerivative:scalarInterval(third[$0]))
    })
    return try completeParameterEnclosure(jet, state: state, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
  }

  private func nativeFreeInterval(_ cell: CertifiedImplicitIntersectionGraphCell,
    over interval: ScalarInterval, tolerance: ModelingTolerance) throws -> ScalarInterval {
    let source = cell.parameterBox.interval(for: cell.freeParameter)
    if interval.lower == interval.upper, interval.lower == 0 || interval.lower == 1 {
      // The original endpoint is exact free-coordinate authority; dependent roots
      // still require the retained certificate and caller-owned localization.
      let atUpper = (interval.lower == 1) == (cell.direction == .forward)
      let endpoint = atUpper ? source.upper : source.lower
      return try ScalarInterval(lower: endpoint, upper: endpoint)
    }
    let width = OutwardScalarInterval.exact(source.upper) - .exact(source.lower)
    let fraction = OutwardScalarInterval(lower: interval.lower, upper: interval.upper)
    let directed = cell.direction == .forward ? fraction : .exact(1) - fraction
    let free = OutwardScalarInterval.exact(source.lower) + width * directed
    guard let retained = free.intersection(with: OutwardScalarInterval(lower: source.lower, upper: source.upper)) else {
      throw invalidInput(tolerance: tolerance, message: "Implicit closed fraction has no original native free range.")
    }
    return try scalarInterval(retained)
  }

  private func isMonotone(_ coordinate: CertifiedImplicitParameterIntervalJet.Coordinate) -> Bool {
    coordinate.firstDerivative.lower > 0 || coordinate.firstDerivative.upper < 0
  }

  private func endpointState(from state: ParameterEnclosureState,
    rangeBox: SurfaceIntersectionParameterBox, fraction: Double,
    phase: ParameterEnclosurePhase, tolerance: ModelingTolerance,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> ParameterEnclosureState {
    let cell = state.intersection.cells[state.cellIndex]
    let freeIndex = cell.freeParameter.rawValue
    let free = try nativeFreeInterval(cell, over: ScalarInterval(lower: fraction, upper: fraction), tolerance: tolerance)
    try consumeWork()
    try OriginalCoefficientAllocation.reserve(count: 4, of: ScalarInterval.self, consumeStorage: consumeStorage)
    var bounds = rangeBox.intervals
    guard let retained = OutwardScalarInterval(lower: free.lower, upper: free.upper).intersection(
      with: OutwardScalarInterval(lower: bounds[freeIndex].lower, upper: bounds[freeIndex].upper)) else {
      throw certificationFailure(tolerance: tolerance, message: "Implicit endpoint has no retained original range root authority.")
    }
    bounds[freeIndex] = try scalarInterval(retained)
    return ParameterEnclosureState(intersection: state.intersection, cellIndex: state.cellIndex,
      parameterBox: parameterBox(bounds), tolerance: tolerance,
      originalInterval: state.originalInterval, phase: phase)
  }

  private func completeParameterEnclosure(_ jet: CertifiedImplicitParameterIntervalJet,
    state: ParameterEnclosureState, tolerance: ModelingTolerance,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> ParameterEnclosureStep {
    switch state.phase {
    case .range:
      var monotone = false
      for coordinate in jet.coordinates { try consumeWork(); monotone = monotone || isMonotone(coordinate) }
      guard state.originalInterval.width > 0, monotone else { return .enclosed(jet) }
      return .contracted(try endpointState(from: state, rangeBox: state.parameterBox,
        fraction: state.originalInterval.lower, phase: .lowerEndpoint(jet, state.parameterBox), tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage))
    case .lowerEndpoint(let rangeJet, let rangeBox):
      return .contracted(try endpointState(from: state, rangeBox: rangeBox,
        fraction: state.originalInterval.upper, phase: .upperEndpoint(rangeJet, rangeBox, jet), tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage))
    case .upperEndpoint(let rangeJet, _, let lowerJet):
      try OriginalCoefficientAllocation.reserve(count: rangeJet.coordinates.count, of: CertifiedImplicitParameterIntervalJet.Coordinate.self, consumeStorage: consumeStorage)
      let coordinates = try rangeJet.coordinates.indices.map { index in
        try consumeWork()
        let coordinate = rangeJet.coordinates[index]
        guard isMonotone(coordinate) else { return coordinate }
        // A localized derivative sign proves that the extrema occur at these
        // certified endpoint roots. Endpoint values alone do not prove a range.
        let lower = max(coordinate.value.lower,
          min(lowerJet.coordinates[index].value.lower, jet.coordinates[index].value.lower))
        let upper = min(coordinate.value.upper,
          max(lowerJet.coordinates[index].value.upper, jet.coordinates[index].value.upper))
        guard lower <= upper else {
          throw certificationFailure(tolerance: tolerance, message: "Implicit monotone endpoint roots contradict the original range enclosure.")
        }
        return CertifiedImplicitParameterIntervalJet.Coordinate(value: try ScalarInterval(lower: lower, upper: upper),
          firstDerivative: coordinate.firstDerivative, secondDerivative: coordinate.secondDerivative,
          thirdDerivative: coordinate.thirdDerivative)
      }
      return .enclosed(CertifiedImplicitParameterIntervalJet(coordinates: coordinates))
    }
  }

  private func minimumLimit(_ first: Int?, _ second: Int?) -> Int? {
    if let first, let second { return min(first, second) }
    return first ?? second
  }

  private func chargeOwnerComparison(_ curve: CertifiedImplicitIntersectionCurve,
    consumeWork: () throws -> Void) throws {
    if let preparedSurfaces {
      try GeometryStructuralComparisonWork.charge(curve: .implicit(preparedSurfaces.intersection),
        using: { count in for _ in 0..<count { try consumeWork() } })
    }
    try GeometryStructuralComparisonWork.charge(curve: .implicit(curve),
      using: { count in for _ in 0..<count { try consumeWork() } })
  }

  private func closedSurfaceJets(over box: SurfaceIntersectionParameterBox, prepared: PreparedSurfaces,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil,
    maximumSubdivisionDepth: Int? = nil, remainingSourceDepth: Int = 0,
    consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
    consumeStorage: ((Int) throws -> Void)? = nil)
    throws -> (first: SurfaceIntervalVectorJet, second: SurfaceIntervalVectorJet) {
    func original(_ source: PreparedSurfaceDifferentialEncloser,
      _ u: ScalarInterval, _ v: ScalarInterval) throws -> SurfaceIntervalVectorJet {
      if let maximumSpanCount, let maximumSubdivisionDepth {
        return try source.intervalJet(overClosedBox: SurfaceParameterBox(u: u, v: v),
          tolerance: tolerance, maximumSpanCount: maximumSpanCount,
          maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
          consumeWork: consumeWork, consumeStorage: consumeStorage)
      }
      try consumeWork()
      return try source.intervalJet(overClosedBox: SurfaceParameterBox(u: u, v: v), tolerance: tolerance)
    }
    return try (original(prepared.first, box.firstU, box.firstV),
      original(prepared.second, box.secondU, box.secondV))
  }

  private func derivativeColumns(first: SurfaceIntervalVectorJet,second: SurfaceIntervalVectorJet) -> [IntervalVector] {
    [vector(first,at:{ $0.derivativeU }),vector(first,at:{ $0.derivativeV }),
     -vector(second,at:{ $0.derivativeU }),-vector(second,at:{ $0.derivativeV })]
  }

  private func inverseRows(_ columns: [IntervalVector], consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)?) throws -> [IntervalVector]? {
    try OriginalCoefficientAllocation.reserve(count: columns.count, of: Vector3D.self, consumeStorage: consumeStorage)
    let centers = try columns.map { try consumeWork(); return Vector3D(x:$0.x.midpoint,y:$0.y.midpoint,z:$0.z.midpoint) }
    try consumeWork()
    let determinant = centers[0].dot(centers[1].cross(centers[2]))
    guard determinant.isFinite,determinant != 0 else { return nil }
    try OriginalCoefficientAllocation.reserve(count: 3, of: Vector3D.self, consumeStorage: consumeStorage)
    let crosses = [centers[1].cross(centers[2]),centers[2].cross(centers[0]),centers[0].cross(centers[1])]
    try OriginalCoefficientAllocation.reserve(count: crosses.count, of: IntervalVector.self, consumeStorage: consumeStorage)
    let rows = try crosses.map { try consumeWork(); return IntervalVector(x:.exact($0.x/determinant),y:.exact($0.y/determinant),z:.exact($0.z/determinant)) }
    for row in rows { try consumeWork(); if !row.isFinite { return nil } }
    return rows
  }

  private func parameterBox(_ bounds: [ScalarInterval]) -> SurfaceIntersectionParameterBox {
    SurfaceIntersectionParameterBox(firstU:bounds[0],firstV:bounds[1],secondU:bounds[2],secondV:bounds[3])
  }

  private func checkLocalizationCancellation(_ tolerance: ModelingTolerance) throws {
    if Task.isCancelled {
      throw KernelError(phase:.geometry,code:.cancelled,tolerance:tolerance,message:"Implicit localization was cancelled.")
    }
  }

  func intervalJet(
    of curve: CertifiedImplicitIntersectionCurve,
    over interval: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    surfaceJet(
      try enclosedJet(
        of: curve,
        over: interval,
        tolerance: tolerance
      ))
  }

  package func parameterIntervalJet(
    of curve: CertifiedImplicitIntersectionCurve,
    over interval: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitParameterIntervalJet {
    let jet = try enclosedJet(
      of: curve,
      over: interval,
      tolerance: tolerance
    )
    return CertifiedImplicitParameterIntervalJet(
      coordinates: try jet.parameters.map {
        CertifiedImplicitParameterIntervalJet.Coordinate(
          value: try scalarInterval($0.value),
          firstDerivative: try scalarInterval($0.firstDerivative),
          secondDerivative: try scalarInterval($0.secondDerivative),
          thirdDerivative: try scalarInterval($0.thirdDerivative)
        )
      }
    )
  }

  package func restrictedBounds(
    of curve: CertifiedImplicitIntersectionCurve,
    cellIndex: Int,
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionGraphSubcell {
    guard curve.cells.indices.contains(cellIndex) else {
      throw invalidInput(
        tolerance: tolerance,
        message: "An implicit curve restriction referenced an invalid graph cell."
      )
    }
    let cell = curve.cells[cellIndex]
    if let preparedSurfaces, let admission = preparedSurfaces.admission {
      try chargeOwnerComparison(curve, consumeWork: { try admission.step() })
      guard preparedSurfaces.intersection == curve else {
        throw GeometryConversionError.invalidInput("Original implicit restriction belongs to another prepared graph.")
      }
      return try restrictedBounds(cellIndex: cellIndex,
        fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction,
        tolerance: tolerance, admission: admission)
    }
    if let preparedSurfaces,
      preparedSurfaces.first.surface == curve.firstSurface,
      preparedSurfaces.second.surface == curve.secondSurface,
      preparedSurfaces.parameterDerivativeBounds.indices.contains(cellIndex)
    {
      if let exact = preparedSurfaces.exactIsoparametricGraph,
        case .bSpline(let firstSurface) = preparedSurfaces.first.surface,
        case .bSpline(let secondSurface) = preparedSurfaces.second.surface,
        let exactBounds = try exact.restrictedBounds(
          parameterBox: cell.parameterBox,
          freeParameter: cell.freeParameter,
          direction: cell.direction,
          lowerAnchor: cell.lowerAnchor,
          midpointAnchor: cell.midpointAnchor,
          upperAnchor: cell.upperAnchor,
          fromNormalizedFraction: lowerFraction,
          toNormalizedFraction: upperFraction,
          first: firstSurface,
          second: secondSurface,
          tolerance: tolerance
        )
      {
        return exactBounds
      }
      return try cell.restrictedBounds(
        fromNormalizedFraction: lowerFraction,
        toNormalizedFraction: upperFraction,
        firstSurface: curve.firstSurface,
        secondSurface: curve.secondSurface,
        parentDerivativeBounds:
          preparedSurfaces
          .parameterDerivativeBounds[cellIndex],
        tolerance: tolerance
      )
    }
    return try cell.restrictedBounds(
      fromNormalizedFraction: lowerFraction,
      toNormalizedFraction: upperFraction,
      firstSurface: curve.firstSurface,
      secondSurface: curve.secondSurface,
      tolerance: tolerance
    )
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy implicit curve/lift interval calls
  // retain positive-width, modeling-resolution and private recursive refinement
  // limits. General certified area callers must adopt the closed continuation
  // and their shared work/depth contract before treating those domains as complete.
  private func enclosedJet(
    of curve: CertifiedImplicitIntersectionCurve,
    over interval: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CurveIntervalJet {
    let cellCount = curve.cells.count
    guard cellCount > 0 else {
      throw invalidInput(
        tolerance: tolerance,
        message: "An implicit curve interval jet requires graph cells."
      )
    }
    let count = Double(cellCount)
    var result: CurveIntervalJet?
    for index in curve.cells.indices {
      let cellLower = Double(index) / count
      let cellUpper = Double(index + 1) / count
      let lower = max(interval.lower, cellLower)
      let upper = min(interval.upper, cellUpper)
      guard upper > lower else { continue }
      let local = try enclose(
        curve: curve,
        cellIndex: index,
        globalInterval: ScalarInterval(lower: lower, upper: upper),
        depth: 0,
        tolerance: tolerance
      )
      result = result.map { $0.union(local) } ?? local
    }
    guard let result, result.isFinite else {
      throw certificationFailure(
        tolerance: tolerance,
        message: "An implicit curve interval did not produce a finite third-order jet."
      )
    }
    return result
  }

  private func enclose(
    curve: CertifiedImplicitIntersectionCurve,
    cellIndex: Int,
    globalInterval: ScalarInterval,
    depth: Int,
    tolerance: ModelingTolerance
  ) throws -> CurveIntervalJet {
    let count = Double(curve.cells.count)
    let cell = curve.cells[cellIndex]
    var localLower = max(
      0.0,
      min(1.0, globalInterval.lower * count - Double(cellIndex))
    )
    var localUpper = max(
      0.0,
      min(1.0, globalInterval.upper * count - Double(cellIndex))
    )
    if localUpper - localLower <= tolerance.relative {
      // Enclose the requested interval without reverting to the whole cell.
      // The restriction contract needs a representable span above resolution.
      let width = min(1.0, max(4 * tolerance.relative, Double.ulpOfOne * 4_096).nextUp)
      localLower = max(0, min(localLower, localUpper - width).nextDown)
      localUpper = min(1, max(localUpper, localLower + width).nextUp)
    }
    let subcell = try restrictedBounds(
      of: curve,
      cellIndex: cellIndex,
      fromNormalizedFraction: localLower,
      toNormalizedFraction: localUpper,
      tolerance: tolerance
    )
    let parameterBox = subcell.parameterBox
    let localSpan = localUpper - localLower
    let localFirstDerivatives = try subcell.parameterDerivativeBounds.map {
      try ScalarInterval(
        lower: ($0.lower / localSpan).nextDown,
        upper: ($0.upper / localSpan).nextUp
      )
    }
    let firstDerivatives = localFirstDerivatives.map {
      OutwardScalarInterval(lower: $0.lower, upper: $0.upper)
        * OutwardScalarInterval(count)
    }
    let firstParameters = SurfaceParameterBox(
      u: parameterBox.firstU,
      v: parameterBox.firstV
    )
    let secondParameters = SurfaceParameterBox(
      u: parameterBox.secondU,
      v: parameterBox.secondV
    )
    let firstSurface: SurfaceIntervalVectorJet
    let secondSurface: SurfaceIntervalVectorJet
    if let preparedSurfaces,
      preparedSurfaces.first.surface == curve.firstSurface,
      preparedSurfaces.second.surface == curve.secondSurface
    {
      firstSurface = try preparedSurfaces.first.intervalJet(
        over: firstParameters,
        tolerance: tolerance
      )
      secondSurface = try preparedSurfaces.second.intervalJet(
        over: secondParameters,
        tolerance: tolerance
      )
    } else {
      let encloser = DefaultSurfaceDifferentialEncloser()
      firstSurface = try encloser.intervalJet(
        of: curve.firstSurface,
        over: firstParameters,
        tolerance: tolerance
      )
      secondSurface = try encloser.intervalJet(
        of: curve.secondSurface,
        over: secondParameters,
        tolerance: tolerance
      )
    }
    let columns = [
      vector(firstSurface, at: { $0.derivativeU }),
      vector(firstSurface, at: { $0.derivativeV }),
      -vector(secondSurface, at: { $0.derivativeU }),
      -vector(secondSurface, at: { $0.derivativeV }),
    ]
    let freeIndex = cell.freeParameter.rawValue
    let dependentIndexes = columns.indices.filter { $0 != freeIndex }
    let dependentColumns = dependentIndexes.map { columns[$0] }
    let denominator = determinant(dependentColumns)

    if denominator.isFinite, denominator.excludesZero {
      let firstQuadratic = surfaceQuadratic(
        firstSurface,
        derivativeU: firstDerivatives[0],
        derivativeV: firstDerivatives[1]
      )
      let secondQuadratic = surfaceQuadratic(
        secondSurface,
        derivativeU: firstDerivatives[2],
        derivativeV: firstDerivatives[3]
      )
      let secondDerivatives = try solveDependentDerivatives(
        columns: dependentColumns,
        dependentIndexes: dependentIndexes,
        rightHandSide: -(firstQuadratic - secondQuadratic),
        denominator: denominator,
        tolerance: tolerance,
        order: "second"
      )
      let firstCubic = surfaceCubic(
        firstSurface,
        firstU: firstDerivatives[0],
        firstV: firstDerivatives[1],
        secondU: secondDerivatives[0],
        secondV: secondDerivatives[1]
      )
      let secondCubic = surfaceCubic(
        secondSurface,
        firstU: firstDerivatives[2],
        firstV: firstDerivatives[3],
        secondU: secondDerivatives[2],
        secondV: secondDerivatives[3]
      )
      let thirdDerivatives = try solveDependentDerivatives(
        columns: dependentColumns,
        dependentIndexes: dependentIndexes,
        rightHandSide: -(firstCubic - secondCubic),
        denominator: denominator,
        tolerance: tolerance,
        order: "third"
      )
      let firstSpatialFirst = surfaceFirst(
        firstSurface,
        derivativeU: firstDerivatives[0],
        derivativeV: firstDerivatives[1]
      )
      let secondSpatialFirst = surfaceFirst(
        secondSurface,
        derivativeU: firstDerivatives[2],
        derivativeV: firstDerivatives[3]
      )
      let firstSpatialSecond =
        firstQuadratic
        + vector(firstSurface, at: { $0.derivativeU })
        * secondDerivatives[0]
        + vector(firstSurface, at: { $0.derivativeV })
        * secondDerivatives[1]
      let secondSpatialSecond =
        secondQuadratic
        + vector(secondSurface, at: { $0.derivativeU })
        * secondDerivatives[2]
        + vector(secondSurface, at: { $0.derivativeV })
        * secondDerivatives[3]
      let firstSpatialThird =
        firstCubic
        + vector(firstSurface, at: { $0.derivativeU })
        * thirdDerivatives[0]
        + vector(firstSurface, at: { $0.derivativeV })
        * thirdDerivatives[1]
      let secondSpatialThird =
        secondCubic
        + vector(secondSurface, at: { $0.derivativeU })
        * thirdDerivatives[2]
        + vector(secondSurface, at: { $0.derivativeV })
        * thirdDerivatives[3]
      let result = CurveIntervalJet(
        position: averaged(
          vector(firstSurface, at: { $0.value }),
          vector(secondSurface, at: { $0.value })
        ),
        firstDerivative: averaged(
          firstSpatialFirst,
          secondSpatialFirst
        ),
        secondDerivative: averaged(
          firstSpatialSecond,
          secondSpatialSecond
        ),
        thirdDerivative: averaged(
          firstSpatialThird,
          secondSpatialThird
        ),
        parameters: parameterBox.intervals.indices.map { index in
          let value = parameterBox.intervals[index]
          return ParameterCoordinateIntervalJet(
            value: OutwardScalarInterval(
              lower: value.lower,
              upper: value.upper
            ),
            firstDerivative: firstDerivatives[index],
            secondDerivative: secondDerivatives[index],
            thirdDerivative: thirdDerivatives[index]
          )
        }
      )
      guard result.isFinite else {
        throw arithmeticFailure(
          tolerance: tolerance,
          message: "Implicit curve third-order interval differentiation exceeded finite arithmetic."
        )
      }
      return result
    }

    let scale = max(1.0, abs(globalInterval.lower), abs(globalInterval.upper))
    let minimumWidth = max(
      tolerance.relative * scale,
      Double.ulpOfOne * scale * 4_096.0
    )
    guard depth < 20, globalInterval.width > minimumWidth else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        residual: denominator.absoluteLowerBound,
        tolerance: tolerance,
        message:
          "Implicit curve third-order certification could not isolate a regular dependent Jacobian."
      )
    }
    let midpoint = globalInterval.midpoint
    let lower = try enclose(
      curve: curve,
      cellIndex: cellIndex,
      globalInterval: ScalarInterval(
        lower: globalInterval.lower,
        upper: midpoint
      ),
      depth: depth + 1,
      tolerance: tolerance
    )
    let upper = try enclose(
      curve: curve,
      cellIndex: cellIndex,
      globalInterval: ScalarInterval(
        lower: midpoint,
        upper: globalInterval.upper
      ),
      depth: depth + 1,
      tolerance: tolerance
    )
    return lower.union(upper)
  }

  private func solveDependentDerivatives(
    columns: [IntervalVector],
    dependentIndexes: [Int],
    rightHandSide: IntervalVector,
    denominator: OutwardScalarInterval,
    tolerance: ModelingTolerance,
    order: String, consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
    consumeStorage: ((Int) throws -> Void)? = nil
  ) throws -> [OutwardScalarInterval] {
    try OriginalCoefficientAllocation.reserve(count: 4, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
    var derivatives = Array(
      repeating: OutwardScalarInterval(0.0),
      count: 4
    )
    for dependentOffset in columns.indices {
      try consumeWork()
      try OriginalCoefficientAllocation.reserve(count: columns.count, of: IntervalVector.self, consumeStorage: consumeStorage)
      var numeratorColumns = columns
      numeratorColumns[dependentOffset] = rightHandSide
      let numerator = determinant(numeratorColumns)
      guard numerator.isFinite,
        let quotient = numerator.divided(by: denominator),
        quotient.isFinite
      else {
        throw arithmeticFailure(
          tolerance: tolerance,
          message:
            "Implicit curve \(order)-order differentiation exceeded finite interval arithmetic."
        )
      }
      derivatives[dependentIndexes[dependentOffset]] = quotient
    }
    return derivatives
  }

  private func surfaceFirst(
    _ enclosure: SurfaceIntervalVectorJet,
    derivativeU: OutwardScalarInterval,
    derivativeV: OutwardScalarInterval
  ) -> IntervalVector {
    vector(enclosure, at: { $0.derivativeU }) * derivativeU
      + vector(enclosure, at: { $0.derivativeV }) * derivativeV
  }

  private func surfaceQuadratic(
    _ enclosure: SurfaceIntervalVectorJet,
    derivativeU: OutwardScalarInterval,
    derivativeV: OutwardScalarInterval
  ) -> IntervalVector {
    vector(enclosure, at: { $0.secondDerivativeUU })
      * (derivativeU * derivativeU)
      + vector(enclosure, at: { $0.secondDerivativeUV })
      * (OutwardScalarInterval(2.0) * derivativeU * derivativeV)
      + vector(enclosure, at: { $0.secondDerivativeVV })
      * (derivativeV * derivativeV)
  }

  private func surfaceCubic(
    _ enclosure: SurfaceIntervalVectorJet,
    firstU: OutwardScalarInterval,
    firstV: OutwardScalarInterval,
    secondU: OutwardScalarInterval,
    secondV: OutwardScalarInterval
  ) -> IntervalVector {
    let three = OutwardScalarInterval(3.0)
    return vector(enclosure, at: { $0.thirdDerivativeUUU })
      * (firstU * firstU * firstU)
      + vector(enclosure, at: { $0.thirdDerivativeUUV })
      * (three * firstU * firstU * firstV)
      + vector(enclosure, at: { $0.thirdDerivativeUVV })
      * (three * firstU * firstV * firstV)
      + vector(enclosure, at: { $0.thirdDerivativeVVV })
      * (firstV * firstV * firstV)
      + vector(enclosure, at: { $0.secondDerivativeUU })
      * (three * firstU * secondU)
      + vector(enclosure, at: { $0.secondDerivativeUV })
      * (three * (secondU * firstV + firstU * secondV))
      + vector(enclosure, at: { $0.secondDerivativeVV })
      * (three * firstV * secondV)
  }

  private func determinant(_ columns: [IntervalVector]) -> OutwardScalarInterval {
    guard columns.count == 3 else {
      return OutwardScalarInterval(lower: -.infinity, upper: .infinity)
    }
    return columns[0].dot(columns[1].cross(columns[2]))
  }

  private func averaged(
    _ first: IntervalVector,
    _ second: IntervalVector
  ) -> IntervalVector {
    (first + second) * OutwardScalarInterval(0.5)
  }

  private func vector(
    _ jet: SurfaceIntervalVectorJet,
    at keyPath: (SurfaceIntervalJet) -> OutwardScalarInterval
  ) -> IntervalVector {
    IntervalVector(
      x: keyPath(jet.x),
      y: keyPath(jet.y),
      z: keyPath(jet.z)
    )
  }

  private func surfaceJet(_ jet: CurveIntervalJet) -> SurfaceIntervalVectorJet {
    SurfaceIntervalVectorJet(
      x: surfaceJet(
        position: jet.position.x,
        first: jet.firstDerivative.x,
        second: jet.secondDerivative.x,
        third: jet.thirdDerivative.x
      ),
      y: surfaceJet(
        position: jet.position.y,
        first: jet.firstDerivative.y,
        second: jet.secondDerivative.y,
        third: jet.thirdDerivative.y
      ),
      z: surfaceJet(
        position: jet.position.z,
        first: jet.firstDerivative.z,
        second: jet.secondDerivative.z,
        third: jet.thirdDerivative.z
      )
    )
  }

  private func scalarInterval(
    _ interval: OutwardScalarInterval
  ) throws -> ScalarInterval {
    try ScalarInterval(lower: interval.lower, upper: interval.upper)
  }

  private func surfaceJet(
    position: OutwardScalarInterval,
    first: OutwardScalarInterval,
    second: OutwardScalarInterval,
    third: OutwardScalarInterval
  ) -> SurfaceIntervalJet {
    let zero = OutwardScalarInterval(0.0)
    return SurfaceIntervalJet(
      value: position,
      derivativeU: first,
      derivativeV: zero,
      secondDerivativeUU: second,
      secondDerivativeUV: zero,
      secondDerivativeVV: zero,
      thirdDerivativeUUU: third,
      thirdDerivativeUUV: zero,
      thirdDerivativeUVV: zero,
      thirdDerivativeVVV: zero
    )
  }

  private func invalidInput(
    tolerance: ModelingTolerance,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .invalidInput,
      tolerance: tolerance,
      message: message
    )
  }

  private func certificationFailure(
    tolerance: ModelingTolerance,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .intersectionFailure,
      tolerance: tolerance,
      message: message
    )
  }

  private func arithmeticFailure(
    tolerance: ModelingTolerance,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .resourceLimitExceeded,
      tolerance: tolerance,
      message: message
    )
  }
}
