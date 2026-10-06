import CADCore

extension DefaultOriginalSurfaceEmbeddingValidator {
    public func validateBoundaryContacts<B: RationalAlgebraAdmitting>(first: Surface3D, second: Surface3D,
        sharedBoundaries: [OriginalSurfaceSharedBoundary], allowedCorners: [(Point2D, Point2D)],
        maximumSubdivisionDepth: Int, maximumSpanCount: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        try validateBoundaryContacts(first: first, second: second, sharedBoundaries: sharedBoundaries,
            allowedCorners: allowedCorners, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumSpanCount: maximumSpanCount, remainingSourceDepth: 20, tolerance: tolerance, usage: &usage)
    }

    public func validateBoundaryContacts<B: RationalAlgebraAdmitting>(first: Surface3D, second: Surface3D,
        sharedBoundaries: [OriginalSurfaceSharedBoundary], allowedCorners: [(Point2D, Point2D)],
        maximumSubdivisionDepth: Int, maximumSpanCount: Int, remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        let unit = ParameterDomain.closed(0, 1)
        guard first.uDomain == unit, first.vDomain == unit, second.uDomain == unit, second.vDomain == unit,
              maximumSubdivisionDepth >= 0, maximumSpanCount > 0 else {
            throw GeometryConversionError.invalidInput("Original Loft side contacts require normalized source squares and caller ceilings.")
        }
        let a = try prepare(first, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage)
        let b = try prepare(second, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage)
        for surface in [first, second] { if case .bSpline(let original) = surface {
            try OriginalSplineSurfaceContinuityAdmission().validate(original, tolerance: tolerance, usage: &usage)
        } }
        let issuer = OriginalSurfaceBoundarySourceIssuer()
        for seam in sharedBoundaries {
            let a = try issuer.boundary(of: first, at: seam.first, maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, usage: &usage)
            let b = try issuer.boundary(of: second, at: seam.second, maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, usage: &usage)
            guard try OriginalSplineTraversalIdentity().proves(a, b, usage: &usage) else {
                throw exhausted(tolerance, "Nominated original Loft boundaries do not retain the same exact directed source law.")
            }
        }
        for (a, b) in allowedCorners {
            guard [a.x, a.y, b.x, b.y].allSatisfy({ $0 == 0 || $0 == 1 }) else {
                throw GeometryConversionError.invalidInput("Original side corner contacts must retain actual parameter corners.")
            }
            let firstBoundary = try issuer.boundary(of: first, at: a.y == 0 ? .vLower : .vUpper,
                maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount, tolerance: tolerance, usage: &usage)
            let secondBoundary = try issuer.boundary(of: second, at: b.y == 0 ? .vLower : .vUpper,
                maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount, tolerance: tolerance, usage: &usage)
            guard try OriginalCoonsCornerIncidence().proves(first: firstBoundary, firstAtEnd: a.x == 1,
                second: secondBoundary, secondAtEnd: b.x == 1, usage: &usage) else {
                throw GeometryConversionError.invalidInput("Nominated original surface corners are not the same original spatial point.")
            }
        }
        if let firstImage = try exactBilinearImage(first, usage: &usage),
           let secondImage = try exactBilinearImage(second, usage: &usage),
           let firstProof = try OriginalBilinearEmbeddingCertificate.proven(firstImage, usage: &usage),
           let secondProof = try OriginalBilinearEmbeddingCertificate.proven(secondImage, usage: &usage),
           try OriginalBilinearBoundaryContactCertificate().proves(firstProof, secondProof,
               sharedBoundaries: sharedBoundaries, allowedCorners: allowedCorners,
               tolerance: tolerance, usage: &usage) { return }
        let full = try SurfaceParameterBox(u: ScalarInterval(lower: 0, upper: 1), v: ScalarInterval(lower: 0, upper: 1))
        func rationalAtlas(_ surface: Surface3D) throws -> OriginalCoonsRationalDifferentialAtlas? {
            try OriginalCoonsRationalDifferentialAtlas.prepared(surface, maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, usage: &usage)
        }
        let firstRational = try rationalAtlas(first), secondRational = try rationalAtlas(second)
        let rationalContacts = OriginalCoonsRationalBoundaryContactProof()
        try RationalAlgebraStorage.retain(1, of: (SurfaceParameterBox, SurfaceParameterBox, Int).self, usage: &usage)
        var pending = [(full, full, 0)]
        while let (aBox, bBox, depth) = pending.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.visitExactCell(depth: depth)
            let aj = try query(a, box: aBox, maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth,
                tolerance: tolerance, usage: &usage)
            let bj = try query(b, box: bBox, maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth,
                tolerance: tolerance, usage: &usage)
            if try separated(aj, bj, tolerance: tolerance, usage: &usage) { continue }
            var admitted = false
            for seam in sharedBoundaries {
                let tangentA = freeRange(aBox, boundary: seam.first), tangentB = freeRange(bBox, boundary: seam.second)
                let tangent = try ScalarInterval(lower: min(tangentA.lower, tangentB.lower), upper: max(tangentA.upper, tangentB.upper))
                let firstHull = try touchingHull(aBox, tangent: tangent, boundary: seam.first)
                let secondHull = try touchingHull(bBox, tangent: tangent, boundary: seam.second)
                let firstJet = try query(a, box: firstHull, maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth,
                    tolerance: tolerance, usage: &usage)
                let secondJet = try query(b, box: secondHull, maximumDepth: maximumSubdivisionDepth, maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth,
                    tolerance: tolerance, usage: &usage)
                if try monotone(first: firstJet, second: secondJet, firstBoundary: seam.first, secondBoundary: seam.second, usage: &usage) {
                    admitted = true; break
                }
                if let firstRational, let secondRational {
                    let firstFields = try firstRational.fields(over: firstHull, usage: &usage)
                    let secondFields = try secondRational.fields(over: secondHull, usage: &usage)
                    if try rationalContacts.provesSeam(first: firstFields, second: secondFields,
                        firstBoundary: seam.first, secondBoundary: seam.second, usage: &usage) {
                        admitted = true; break
                    }
                }
            }
            if admitted { continue }
            for (cornerA, cornerB) in allowedCorners {
                guard aBox.u.contains(cornerA.x), aBox.v.contains(cornerA.y),
                      bBox.u.contains(cornerB.x), bBox.v.contains(cornerB.y) else { continue }
                if try cornerConesSeparate(aj, at: cornerA, bj, at: cornerB, usage: &usage) { admitted = true; break }
                if let firstRational, let secondRational {
                    let firstFields = try firstRational.fields(over: aBox, usage: &usage)
                    let secondFields = try secondRational.fields(over: bBox, usage: &usage)
                    if try rationalContacts.provesCorner(first: firstFields, second: secondFields,
                        firstCorner: cornerA, secondCorner: cornerB, usage: &usage) {
                        admitted = true; break
                    }
                }
            }
            if admitted { continue }
            guard depth < maximumSubdivisionDepth else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original Loft stationary
                // boundary contacts also need whole higher-order cone/regular
                // quotient authority. A tiny neighborhood cannot admit them.
                throw exhausted(tolerance, "Original shared-side contact neighborhood remains unresolved under its original limits.")
            }
            let splitFirst = max(aBox.u.width, aBox.v.width) >= max(bBox.u.width, bBox.v.width)
            let children = try split(splitFirst ? aBox : bBox, tolerance: tolerance, usage: &usage)
            try RationalAlgebraStorage.retain(children.count, of: (SurfaceParameterBox, SurfaceParameterBox, Int).self, usage: &usage)
            for child in children { pending.append(splitFirst ? (child, bBox, depth + 1) : (aBox, child, depth + 1)) }
        }
    }

    private func freeRange(_ box: SurfaceParameterBox, boundary: SurfaceParameterBoundary) -> ScalarInterval {
        boundary == .uLower || boundary == .uUpper ? box.v : box.u
    }

    private func touchingHull(_ box: SurfaceParameterBox, tangent: ScalarInterval,
        boundary: SurfaceParameterBoundary) throws -> SurfaceParameterBox {
        let fixedU = boundary == .uLower || boundary == .uUpper
        let upper = boundary == .uUpper || boundary == .vUpper
        let original = fixedU ? box.u : box.v
        let transverse = try ScalarInterval(lower: upper ? original.lower : 0, upper: upper ? 1 : original.upper)
        return fixedU ? .init(u: transverse, v: tangent) : .init(u: tangent, v: transverse)
    }

    private func cornerConesSeparate<B: RationalAlgebraAdmitting>(_ a: OriginalSurfaceFirstOrderEnclosure, at cornerA: Point2D,
        _ b: OriginalSurfaceFirstOrderEnclosure, at cornerB: Point2D, usage: inout B) throws -> Bool {
        try usage.consumeExactWork(128)
        func outward(_ q: OriginalSurfaceFirstOrderEnclosure, corner: Point2D) -> [Vector] {
            [Vector(x: q.x.derivativeU, y: q.y.derivativeU, z: q.z.derivativeU).scaled(corner.x == 0 ? 1 : -1),
             Vector(x: q.x.derivativeV, y: q.y.derivativeV, z: q.z.derivativeV).scaled(corner.y == 0 ? 1 : -1)]
        }
        let first = outward(a, corner: cornerA), second = outward(b, corner: cornerB)
        let candidates = [first[0].midpoint + first[1].midpoint - second[0].midpoint - second[1].midpoint,
                          first[0].midpoint - second[0].midpoint, first[0].midpoint - second[1].midpoint,
                          first[1].midpoint - second[0].midpoint, first[1].midpoint - second[1].midpoint]
        for candidate in candidates {
            try usage.consumeExactWork(48)
            guard [candidate.x, candidate.y, candidate.z].allSatisfy({ $0.isFinite }) else { continue }
            if first.allSatisfy({ $0.projected(candidate).lower > 0 }),
               second.allSatisfy({ $0.projected(candidate).upper < 0 }) { return true }
        }
        return false
    }
}
