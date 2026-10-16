import CADCore

extension DefaultOriginalSurfaceEmbeddingValidator {
  public func validateBoundaryContacts(
    first: Surface3D, second: Surface3D, sharedBoundaries: [OriginalSurfaceSharedBoundary],
    allowedCorners: [(Point2D, Point2D)], maximumSubdivisionDepth: Int, maximumSpanCount: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try validateBoundaryContacts(
      first: first, second: second, sharedBoundaries: sharedBoundaries,
      allowedCorners: allowedCorners, maximumSubdivisionDepth: maximumSubdivisionDepth,
      maximumSpanCount: maximumSpanCount, remainingSourceDepth: 20, tolerance: tolerance,
      using: &execution)
  }

  public func validateBoundaryContacts(
    first: Surface3D, second: Surface3D, sharedBoundaries: [OriginalSurfaceSharedBoundary],
    allowedCorners: [(Point2D, Point2D)], maximumSubdivisionDepth: Int, maximumSpanCount: Int,
    remainingSourceDepth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    let unit = ParameterDomain.closed(0, 1)
    guard first.uDomain == unit, first.vDomain == unit, second.uDomain == unit,
      second.vDomain == unit,
      maximumSubdivisionDepth >= 0, maximumSpanCount > 0
    else {
      throw GeometryConversionError.invalidInput(
        "Original Loft side contacts require normalized source squares and caller ceilings.")
    }
    let a = try prepare(
      first, remainingSourceDepth: remainingSourceDepth,
      maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, using: &execution)
    let b = try prepare(
      second, remainingSourceDepth: remainingSourceDepth,
      maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, using: &execution)
    for surface in [first, second] {
      if case .bSpline(let original) = surface {
        try OriginalSplineSurfaceContinuityAdmission().validate(
          original, tolerance: tolerance, usage: &execution)
      }
    }
    let issuer = OriginalSurfaceBoundarySourceIssuer()
    for seam in sharedBoundaries {
      let a = try issuer.boundary(
        of: first, at: seam.first, maximumDepth: maximumSubdivisionDepth,
        maximumSpanCount: maximumSpanCount, tolerance: tolerance, using: &execution)
      let b = try issuer.boundary(
        of: second, at: seam.second, maximumDepth: maximumSubdivisionDepth,
        maximumSpanCount: maximumSpanCount, tolerance: tolerance, using: &execution)
      guard try OriginalSplineTraversalIdentity().proves(a, b, usage: &execution) else {
        throw exhausted(
          tolerance,
          "Nominated original Loft boundaries do not retain the same exact directed source law.")
      }
    }
    for (a, b) in allowedCorners {
      guard [a.x, a.y, b.x, b.y].allSatisfy({ $0 == 0 || $0 == 1 }) else {
        throw GeometryConversionError.invalidInput(
          "Original side corner contacts must retain actual parameter corners.")
      }
      let firstBoundary = try issuer.boundary(
        of: first, at: a.y == 0 ? .vLower : .vUpper, maximumDepth: maximumSubdivisionDepth,
        maximumSpanCount: maximumSpanCount, tolerance: tolerance, using: &execution)
      let secondBoundary = try issuer.boundary(
        of: second, at: b.y == 0 ? .vLower : .vUpper, maximumDepth: maximumSubdivisionDepth,
        maximumSpanCount: maximumSpanCount, tolerance: tolerance, using: &execution)
      guard
        try OriginalCoonsCornerIncidence().proves(
          first: firstBoundary, firstAtEnd: a.x == 1,
          second: secondBoundary, secondAtEnd: b.x == 1, usage: &execution)
      else {
        throw GeometryConversionError.invalidInput(
          "Nominated original surface corners are not the same original spatial point.")
      }
    }
    if let firstImage = try exactBilinearImage(first, using: &execution),
      let secondImage = try exactBilinearImage(second, using: &execution),
      let firstProof = try OriginalBilinearEmbeddingCertificate.proven(
        firstImage, usage: &execution),
      let secondProof = try OriginalBilinearEmbeddingCertificate.proven(
        secondImage, usage: &execution),
      try OriginalBilinearBoundaryContactCertificate().proves(
        firstProof, secondProof,
        sharedBoundaries: sharedBoundaries, allowedCorners: allowedCorners,
        tolerance: tolerance, usage: &execution)
    {
      return
    }
    let full = try SurfaceParameterBox(
      u: ScalarInterval(lower: 0, upper: 1), v: ScalarInterval(lower: 0, upper: 1))
    func rationalAtlas(_ surface: Surface3D) throws -> OriginalCoonsRationalDifferentialAtlas? {
      try OriginalCoonsRationalDifferentialAtlas.prepared(
        surface, maximumSpanCount: maximumSpanCount,
        tolerance: tolerance, usage: &execution)
    }
    let firstRational = try rationalAtlas(first)
    let secondRational = try rationalAtlas(second)
    let rationalContacts = OriginalCoonsRationalBoundaryContactProof()
    try RationalAlgebraStorage.retain(
      1, of: (SurfaceParameterBox, SurfaceParameterBox, Int).self, usage: &execution)
    var pending = [(full, full, 0)]
    while let (aBox, bBox, depth) = pending.popLast() {
      try CurrentTaskCancellationChecker().checkCancellation()
      try execution.visitGeometricCell(depth: depth)
      let aj = try query(
        a, box: aBox, maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount,
        remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, using: &execution)
      let bj = try query(
        b, box: bBox, maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount,
        remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, using: &execution)
      if try separated(aj, bj, tolerance: tolerance, using: &execution) { continue }
      var admitted = false
      for seam in sharedBoundaries {
        let tangentA = freeRange(aBox, boundary: seam.first)
        let tangentB = freeRange(bBox, boundary: seam.second)
        let tangent = try ScalarInterval(
          lower: min(tangentA.lower, tangentB.lower), upper: max(tangentA.upper, tangentB.upper))
        let firstHull = try touchingHull(aBox, tangent: tangent, boundary: seam.first)
        let secondHull = try touchingHull(bBox, tangent: tangent, boundary: seam.second)
        let firstJet = try query(
          a, box: firstHull, maximumDepth: maximumSubdivisionDepth,
          maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth,
          tolerance: tolerance, using: &execution)
        let secondJet = try query(
          b, box: secondHull, maximumDepth: maximumSubdivisionDepth,
          maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth,
          tolerance: tolerance, using: &execution)
        if try monotone(
          first: firstJet, second: secondJet, firstBoundary: seam.first,
          secondBoundary: seam.second, using: &execution)
        {
          admitted = true
          break
        }
        if let firstRational, let secondRational {
          let firstFields = try firstRational.fields(over: firstHull, usage: &execution)
          let secondFields = try secondRational.fields(over: secondHull, usage: &execution)
          if try rationalContacts.provesSeam(
            first: firstFields, second: secondFields, firstBoundary: seam.first,
            secondBoundary: seam.second, using: &execution)
          {
            admitted = true
            break
          }
        }
      }
      if admitted { continue }
      for (cornerA, cornerB) in allowedCorners {
        guard aBox.u.contains(cornerA.x), aBox.v.contains(cornerA.y),
          bBox.u.contains(cornerB.x), bBox.v.contains(cornerB.y)
        else { continue }
        if try cornerConesSeparate(aj, at: cornerA, bj, at: cornerB, using: &execution) {
          admitted = true
          break
        }
        if let firstRational, let secondRational {
          let firstFields = try firstRational.fields(over: aBox, usage: &execution)
          let secondFields = try secondRational.fields(over: bBox, usage: &execution)
          if try rationalContacts.provesCorner(
            first: firstFields, second: secondFields, firstCorner: cornerA, secondCorner: cornerB,
            using: &execution)
          {
            admitted = true
            break
          }
        }
      }
      if admitted { continue }
      guard depth < maximumSubdivisionDepth else {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original Loft stationary
        // boundary contacts also need whole higher-order cone/regular
        // quotient authority. A tiny neighborhood cannot admit them.
        throw exhausted(
          tolerance,
          "Original shared-side contact neighborhood remains unresolved under its original limits.")
      }
      let splitFirst = max(aBox.u.width, aBox.v.width) >= max(bBox.u.width, bBox.v.width)
      let children = try split(splitFirst ? aBox : bBox, tolerance: tolerance, using: &execution)
      try RationalAlgebraStorage.retain(
        children.count, of: (SurfaceParameterBox, SurfaceParameterBox, Int).self, usage: &execution)
      for child in children {
        pending.append(splitFirst ? (child, bBox, depth + 1) : (aBox, child, depth + 1))
      }
    }
  }

  private func freeRange(_ box: SurfaceParameterBox, boundary: SurfaceParameterBoundary)
    -> ScalarInterval
  {
    boundary == .uLower || boundary == .uUpper ? box.v : box.u
  }

  private func touchingHull(
    _ box: SurfaceParameterBox, tangent: ScalarInterval,
    boundary: SurfaceParameterBoundary
  ) throws -> SurfaceParameterBox {
    let fixedU = boundary == .uLower || boundary == .uUpper
    let upper = boundary == .uUpper || boundary == .vUpper
    let original = fixedU ? box.u : box.v
    let transverse = try ScalarInterval(
      lower: upper ? original.lower : 0, upper: upper ? 1 : original.upper)
    return fixedU ? .init(u: transverse, v: tangent) : .init(u: tangent, v: transverse)
  }

  private func cornerConesSeparate(
    _ a: OriginalSurfaceFirstOrderEnclosure, at cornerA: Point2D,
    _ b: OriginalSurfaceFirstOrderEnclosure, at cornerB: Point2D,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(128)
    func outward(_ q: OriginalSurfaceFirstOrderEnclosure, corner: Point2D) -> [Vector] {
      [
        Vector(x: q.x.derivativeU, y: q.y.derivativeU, z: q.z.derivativeU).scaled(
          corner.x == 0 ? 1 : -1),
        Vector(x: q.x.derivativeV, y: q.y.derivativeV, z: q.z.derivativeV).scaled(
          corner.y == 0 ? 1 : -1),
      ]
    }
    let first = outward(a, corner: cornerA)
    let second = outward(b, corner: cornerB)
    let candidates = [
      first[0].midpoint + first[1].midpoint - second[0].midpoint - second[1].midpoint,
      first[0].midpoint - second[0].midpoint, first[0].midpoint - second[1].midpoint,
      first[1].midpoint - second[0].midpoint, first[1].midpoint - second[1].midpoint,
    ]
    for candidate in candidates {
      try execution.consumeWork(48)
      guard [candidate.x, candidate.y, candidate.z].allSatisfy({ $0.isFinite }) else { continue }
      if first.allSatisfy({ $0.projected(candidate).lower > 0 }),
        second.allSatisfy({ $0.projected(candidate).upper < 0 })
      {
        return true
      }
    }
    return false
  }
}
