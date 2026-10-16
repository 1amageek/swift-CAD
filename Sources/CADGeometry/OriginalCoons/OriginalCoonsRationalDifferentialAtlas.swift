import CADCore

/// Exact native boundary cell laws, retained independently of any tensor image.
struct OriginalCoonsRationalDifferentialAtlas: Sendable {
  struct Cell: Sendable {
    let lowerU: ExactRationalCoefficient
    let upperU: ExactRationalCoefficient
    let lowerV: ExactRationalCoefficient
    let upperV: ExactRationalCoefficient
    let homogeneous: [ExactBivariatePolynomial]
    let originalConstructionHomogeneous: [ExactBivariatePolynomial]
    let tangentU: [ExactBivariatePolynomial]
    let tangentV: [ExactBivariatePolynomial]
    let normal: [ExactBivariatePolynomial]
  }
  struct Field {
    let tangentU: [OutwardScalarInterval]
    let tangentV: [OutwardScalarInterval]
    let normal: [OutwardScalarInterval]
  }
  let cells: [Cell]

  /// The caller admits complete original C0 before composing these fields.
  static func prepared<B: ExactScalarAdmission & ~Copyable>(
    _ surface: Surface3D,
    maximumSpanCount: Int, tolerance: ModelingTolerance, usage: inout B
  ) throws -> Self? {
    switch surface {
    case .procedural(.originalCoons(let source)):
      return try prepared(source, usage: &usage)
    case .procedural(.originalBoundaryCorrected(let source)):
      return try OriginalBoundaryCorrectedRationalAtlas.prepared(source, usage: &usage)
    case .bSpline(let source):
      guard source.uDomain == .closed(0, 1), source.vDomain == .closed(0, 1) else { return nil }

      let prepared = try PreparedBSplineSurfaceDifferentialEncloser(
        surface: source, tolerance: tolerance, using: &usage)
      let square = try SurfaceParameterBox(
        u: .init(lower: 0, upper: 1), v: .init(lower: 0, upper: 1))
      let owners = try prepared.originalNativeSpans(
        over: square, tolerance: tolerance, maximumSpanCount: maximumSpanCount, using: &usage)
      try RationalAlgebraStorage.retain(owners.count, of: Cell.self, usage: &usage)
      var cells: [Cell] = []
      cells.reserveCapacity(owners.count)
      for owner in owners {
        try usage.consumeWork(1)
        let domain = SurfaceParameterBox(u: owner.uBounds, v: owner.vBounds)
        let original = try OriginalRationalSurfacePolynomial(
          source: source, native: owner,
          domain: domain, view: .unitZ, tolerance: tolerance, usage: &usage)
        let derivatives = try OriginalRationalSurfaceDerivativeLaw(
          original: original,
          throughOrder: 1, usage: &usage)
        guard let u = derivatives.partials.first(where: { $0.uOrder == 1 && $0.vOrder == 0 }),
          let v = derivatives.partials.first(where: { $0.uOrder == 0 && $0.vOrder == 1 })
        else {
          throw GeometryConversionError.invalidInput(
            "Original native atlas lost its rational tangent law.")
        }
        var first = u.numerators
        var second = v.numerators
        for upper in [false, true] {
          first = try strip(first, alongU: true, upper: upper, usage: &usage)
          second = try strip(second, alongU: false, upper: upper, usage: &usage)
        }
        try OriginalCoefficientAllocation.reserve(
          count: 3, of: ExactBivariatePolynomial.self, using: &usage)
        var normal: [ExactBivariatePolynomial] = []
        normal.reserveCapacity(3)
        for axis in 0..<3 {
          let i = (axis + 1) % 3
          let j = (axis + 2) % 3
          normal.append(
            try first[i].multiplied(by: second[j], usage: &usage)
              .subtracting(first[j].multiplied(by: second[i], usage: &usage), usage: &usage))
        }
        cells.append(
          try Cell(
            lowerU: .originalDouble(owner.uBounds.lower, usage: &usage),
            upperU: .originalDouble(owner.uBounds.upper, usage: &usage),
            lowerV: .originalDouble(owner.vBounds.lower, usage: &usage),
            upperV: .originalDouble(owner.vBounds.upper, usage: &usage),
            homogeneous: original.homogeneous,
            originalConstructionHomogeneous: original.homogeneous,
            tangentU: first, tangentV: second, normal: normal))
      }
      guard !cells.isEmpty else {
        throw GeometryConversionError.invalidInput(
          "Original native atlas has no selected source cell.")
      }
      return Self(cells: cells)
    default: return nil
    }
  }

  static func prepared<B: ExactScalarAdmission & ~Copyable>(
    _ surface: OriginalCoonsSurface3D,
    usage: inout B
  ) throws -> Self? {
    try surface.admitScalarPreparation(using: &usage)
    guard let original = try OriginalCoonsHomogeneousAtlas.prepared(surface, usage: &usage) else {
      return nil
    }
    try RationalAlgebraStorage.retain(original.cells.count, of: Cell.self, usage: &usage)
    var result: [Cell] = []
    result.reserveCapacity(original.cells.count)
    for cell in original.cells {
      let position = cell.homogeneous
      let denominator = position[3]
      let du = try denominator.differentiated(alongU: true, usage: &usage)
      let dv = try denominator.differentiated(alongU: false, usage: &usage)
      try RationalAlgebraStorage.retain(6, of: ExactBivariatePolynomial.self, usage: &usage)
      var first: [ExactBivariatePolynomial] = []
      var second: [ExactBivariatePolynomial] = []
      first.reserveCapacity(3)
      second.reserveCapacity(3)
      for axis in 0..<3 {
        first.append(
          try position[axis].differentiated(alongU: true, usage: &usage)
            .multiplied(by: denominator, usage: &usage)
            .subtracting(position[axis].multiplied(by: du, usage: &usage), usage: &usage))
        second.append(
          try position[axis].differentiated(alongU: false, usage: &usage)
            .multiplied(by: denominator, usage: &usage)
            .subtracting(position[axis].multiplied(by: dv, usage: &usage), usage: &usage))
      }
      for upper in [false, true] {
        first = try strip(first, alongU: true, upper: upper, usage: &usage)
        second = try strip(second, alongU: false, upper: upper, usage: &usage)
      }
      try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
      var normal: [ExactBivariatePolynomial] = []
      normal.reserveCapacity(3)
      for axis in 0..<3 {
        let i = (axis + 1) % 3
        let j = (axis + 2) % 3
        normal.append(
          try first[i].multiplied(by: second[j], usage: &usage)
            .subtracting(first[j].multiplied(by: second[i], usage: &usage), usage: &usage))
      }
      result.append(
        Cell(
          lowerU: cell.lowerU, upperU: cell.upperU, lowerV: cell.lowerV, upperV: cell.upperV,
          homogeneous: position, originalConstructionHomogeneous: position,
          tangentU: first, tangentV: second, normal: normal))
    }
    guard !result.isEmpty else {
      throw GeometryConversionError.invalidInput(
        "Original Coons rational atlas has no positive source cells.")
    }
    try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
    try CurrentTaskCancellationChecker().checkCancellation()
    return Self(cells: result)
  }

  func fields<B: ExactScalarAdmission & ~Copyable>(
    over domain: SurfaceParameterBox,
    usage: inout B
  ) throws -> [Field] {
    let u0 = try ExactRationalCoefficient.originalDouble(domain.u.lower, usage: &usage)
    let u1 = try ExactRationalCoefficient.originalDouble(domain.u.upper, usage: &usage)
    let v0 = try ExactRationalCoefficient.originalDouble(domain.v.lower, usage: &usage)
    let v1 = try ExactRationalCoefficient.originalDouble(domain.v.upper, usage: &usage)
    try OriginalCoefficientAllocation.reserve(count: cells.count, of: Field.self, using: &usage)
    var result: [Field] = []
    result.reserveCapacity(cells.count)
    for cell in cells {
      try usage.consumeWork(1)
      if try cell.upperU.subtracting(u0, usage: &usage).isNegative
        || u1.subtracting(cell.lowerU, usage: &usage).isNegative
        || cell.upperV.subtracting(v0, usage: &usage).isNegative
        || v1.subtracting(cell.lowerV, usage: &usage).isNegative
      {
        continue
      }
      let box = try SurfaceParameterBox(
        u: ScalarInterval(
          lower: max(domain.u.lower, cell.lowerU.outwardInterval(usage: &usage).lower),
          upper: min(domain.u.upper, cell.upperU.outwardInterval(usage: &usage).upper)),
        v: ScalarInterval(
          lower: max(domain.v.lower, cell.lowerV.outwardInterval(usage: &usage).lower),
          upper: min(domain.v.upper, cell.upperV.outwardInterval(usage: &usage).upper)))
      result.append(
        try Field(
          tangentU: OriginalCoefficientAllocation.map(elements: cell.tangentU, using: &usage) {
            value, usage in try value.enclosure(over: box, usage: &usage)
          },
          tangentV: OriginalCoefficientAllocation.map(elements: cell.tangentV, using: &usage) {
            value, usage in try value.enclosure(over: box, usage: &usage)
          },
          normal: OriginalCoefficientAllocation.map(elements: cell.normal, using: &usage) {
            value, usage in try value.enclosure(over: box, usage: &usage)
          }))
    }
    guard !result.isEmpty else {
      throw GeometryConversionError.invalidInput(
        "Original Coons query escaped its retained rational cell cover.")
    }
    return result
  }

  static func strip<B: ExactScalarAdmission & ~Copyable>(
    _ original: [ExactBivariatePolynomial],
    alongU: Bool, upper: Bool, usage: inout B
  ) throws -> [ExactBivariatePolynomial] {
    let boundary = upper ? ExactRationalCoefficient.one : .zero
    var multiplicity: Int?
    for polynomial in original where !polynomial.isZero {
      let factor = try polynomial.dividedByBoundaryFactor(
        alongU: alongU, boundary: boundary, usage: &usage)
      multiplicity = min(multiplicity ?? factor.multiplicity, factor.multiplicity)
    }
    guard let multiplicity, multiplicity > 0 else { return original }
    let factor = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
      .subtracting(.constant(boundary, usage: &usage), usage: &usage)
    var power = try ExactBivariatePolynomial.constant(.one, usage: &usage)
    for _ in 0..<multiplicity { power = try power.multiplied(by: factor, usage: &usage) }
    let sign = upper && multiplicity & 1 == 1 ? ExactRationalCoefficient.one.negated : .one
    try RationalAlgebraStorage.retain(
      original.count, of: ExactBivariatePolynomial.self, usage: &usage)
    var result: [ExactBivariatePolynomial] = []
    result.reserveCapacity(original.count)
    for polynomial in original {
      result.append(
        try polynomial.dividedExactly(by: power, usage: &usage).scaled(by: sign, usage: &usage))
    }
    return result
  }
}
