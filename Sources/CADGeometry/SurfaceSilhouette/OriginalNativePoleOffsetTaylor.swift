import CADCore

/// Original first-offset normal admission over the complete collapsed source support.
struct OriginalNativePoleOffsetTaylor {
    static func prepare<B: ExactScalarAdmission & ~Copyable>(source: BSplineSurface3D,
        prepared: PreparedBSplineSurfaceDifferentialEncloser, over query: SurfaceParameterBox,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws -> [OriginalUniquePoleNormalAuthority] {
        let pole = OriginalBSplinePoleNormal(surface: source, tolerance: tolerance, prepared: prepared)
        var authorities: [OriginalUniquePoleNormalAuthority] = []
        for boundary in try boundaries(source: source, over: query, usage: &usage) {
            guard try isCollapsed(boundary, source: source, pole: pole, usage: &usage) else { continue }
            guard let proof = try OriginalUniquePoleNormalAuthority.prepare(source: source,
                boundary: boundary, prepared: prepared, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage) else {
                throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                    message: "Original collapsed support does not have one whole-source oriented offset normal.")
            }
            try RationalAlgebraStorage.retain(1, of: UInt32.self, usage: &usage); authorities.append(proof)
        }
        return authorities
    }

    static func normal<B: ExactScalarAdmission & ~Copyable>(source: BSplineSurface3D,
        pole: OriginalBSplinePoleNormal,
        coefficients: OriginalExactBSplinePoleNormal?,
        authorities: [OriginalUniquePoleNormalAuthority],
        over box: SurfaceParameterBox,
        owning span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        throughOrder: Int, tolerance: ModelingTolerance,
        usage: inout B) throws -> SurfaceAreaIntervalTaylorVectorJet? {
        guard let coefficients else { return nil }
        try span.validate(on: source, over: box, tolerance: tolerance,
            using: &usage)
        for boundary in try boundaries(source: source, over: box, usage: &usage) {
            guard try isCollapsed(boundary, source: source, pole: pole, usage: &usage) else { continue }
            var admitted = false
            for authority in authorities {
                try usage.consumeWork(1)
                if authority.boundary == boundary && authority.tolerance == tolerance {
                    try GeometryStructuralComparisonWork.charge(surface: .bSpline(source),
                        using: &usage)
                    try GeometryStructuralComparisonWork.charge(surface: .bSpline(authority.source),
                        using: &usage)
                    guard authority.source == source else {
                        throw GeometryConversionError.invalidInput("Original pole normal receipt belongs to another source tensor.")
                    }
                    admitted = true; break
                }
            }
            guard admitted else {
                throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                    message: "Original pole offset query lacks its complete boundary normal authority.")
            }
        }
        let original = try OriginalPolynomialSurfaceTaylor.vector(polynomials: coefficients.coefficients,
            over: box, throughOrder: throughOrder, tolerance: tolerance, usage: &usage)
        return try OriginalPolynomialSurfaceTaylor.normalized(original, usage: &usage)
    }

    static func boundaries<B: ExactScalarAdmission & ~Copyable>(source: BSplineSurface3D,
        over box: SurfaceParameterBox, usage: inout B) throws -> [SurfaceParameterBoundary] {
        try RationalAlgebraStorage.retain(4, of: UInt32.self, usage: &usage)
        var values: [SurfaceParameterBoundary] = []
        if case .closed(let lower, let upper) = source.uDomain {
            if box.u.lower == lower { values.append(.uLower) }
            if box.u.upper == upper { values.append(.uUpper) }
        }
        if case .closed(let lower, let upper) = source.vDomain {
            if box.v.lower == lower { values.append(.vLower) }
            if box.v.upper == upper { values.append(.vUpper) }
        }
        return values
    }

    private static func isCollapsed<B: ExactScalarAdmission & ~Copyable>(_ boundary: SurfaceParameterBoundary,
        source: BSplineSurface3D, pole: OriginalBSplinePoleNormal, usage: inout B) throws -> Bool {
        let alongU = boundary == .uLower || boundary == .uUpper
        let fixed = alongU ? source.uDomain : source.vDomain
        let free = alongU ? source.vFundamentalDomain : source.uFundamentalDomain
        guard case .closed(let lower, let upper) = fixed,
              case .closed(let freeLower, let freeUpper) = free else { return false }
        let station = boundary == .uLower || boundary == .vLower ? lower : upper
        let transverse = freeLower + (freeUpper - freeLower) * 0.5
        try usage.consumeWork(1)
        guard transverse.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original collapsed boundary parameter is nonfinite.")
        }
        do {
            _ = try pole.collapsedPoint(at: .init(u: alongU ? station : transverse,
                v: alongU ? transverse : station), direction: alongU ? .constantU : .constantV,
                using: &usage)
            return true
        } catch let error as KernelError where error.code == .invalidInput {
            // Only the owner's exact noncollapse classification is optional.
            return false
        }
    }
}
