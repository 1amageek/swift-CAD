import CADCore

/// Complete source-factor partition of fixed-coordinate original field loci.
struct SurfaceSilhouetteFieldCoordinateComponents {
    let curves: [OriginalSurfaceSilhouetteCurve]
    let endpoints: [OriginalSingularFieldSystemRoot]

    init(field: OriginalSurfaceSilhouetteField, projection: OriginalSingularFieldPlaneProjection,
        usage: inout OriginalQueryExecution) throws {
        let original = projection.squareFree
        let content = try OriginalSingularFieldPlaneGCD.content(original,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let nonVertical = try OriginalSingularFieldPlaneGCD.primitive(original,
            content: content, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        var curves: [OriginalSurfaceSilhouetteCurve] = []
        var endpoints: [OriginalSingularFieldSystemRoot] = []
        for fixed in projection.verticalComponents {
            try usage.consumeWork(1)
            let u = try fixed.value(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let factor = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: true,
                in: u.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                .subtracting(.constant(u, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let complementary = try OriginalSingularFieldSystemSolver.fiber(nonVertical, at: u,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let cuts = try Self.cuts(complementary, over: projection.domain.v,
                depth: fixed.isolation.depth, usage: &usage)
            var points: [OriginalSingularFieldSystemRoot] = []
            for cut in cuts {
                let vRoot = try OriginalSingularFieldPlaneProjection.root(cut, context: u.context,
                    inheritedDepth: fixed.isolation.depth, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                let v = try vRoot.value(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                let first = try u.embedded(in: v.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                let secondEquation: OriginalSingularFieldPlanePolynomial
                switch cut {
                case .authored(let boundary):
                    secondEquation = try Self.boundary(boundary, alongU: false,
                        context: original.context, usage: &usage)
                case .algebraic: secondEquation = nonVertical
                }
                let firstEquation = try Self.lift(fixed.polynomial, alongU: true, usage: &usage)
                try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
                let point = OriginalSingularFieldSystemRoot(equations: [firstEquation, secondEquation],
                    projectionRoot: fixed, fiberRoot: vRoot, u: first, v: v, sourceDomain: projection.domain)
                guard case .zero = try point.sign(of: original,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
                    throw rationalAlgebraFailure("Original vertical component endpoint lost full zero-law incidence.")
                }
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldSystemRoot.self, usage: &usage)
                points.append(point)
            }
            try Self.append(points: points, factor: factor, freeAlongU: false,
                field: field, original: original, domain: projection.domain,
                curves: &curves, endpoints: &endpoints, usage: &usage)
        }
        for fixed in projection.horizontalComponents {
            let factor = try Self.boundary(fixed, alongU: false, context: original.context, usage: &usage)
            let remainder = try original.dividedExactly(by: factor,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let complementary = try OriginalSingularFieldPlaneProjection.restricted(remainder,
                alongU: false, station: fixed, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let cuts = try Self.cuts(complementary, over: projection.domain.u,
                depth: projection.sourceDepth, usage: &usage)
            var points: [OriginalSingularFieldSystemRoot] = []
            for cut in cuts {
                let uRoot = try OriginalSingularFieldPlaneProjection.root(cut, context: original.context,
                    inheritedDepth: projection.sourceDepth, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                let u = try uRoot.value(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                let vRoot = try OriginalSingularFieldPlaneProjection.root(.authored(fixed), context: u.context,
                    inheritedDepth: uRoot.isolation.depth, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                let v = try vRoot.value(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                let first = try u.embedded(in: v.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                let firstEquation = try Self.lift(uRoot.polynomial, alongU: true, usage: &usage)
                try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
                let point = OriginalSingularFieldSystemRoot(equations: [firstEquation, factor],
                    projectionRoot: uRoot, fiberRoot: vRoot, u: first, v: v, sourceDomain: projection.domain)
                guard case .zero = try point.sign(of: original,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
                    throw rationalAlgebraFailure("Original horizontal component endpoint lost full zero-law incidence.")
                }
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldSystemRoot.self, usage: &usage)
                points.append(point)
            }
            try Self.append(points: points, factor: factor, freeAlongU: true,
                field: field, original: original, domain: projection.domain,
                curves: &curves, endpoints: &endpoints, usage: &usage)
        }
        self.curves = curves; self.endpoints = endpoints
    }

    private static func cuts(_ polynomial: OriginalSingularFieldPolynomial,
        over domain: ScalarInterval, depth: Int, usage: inout OriginalQueryExecution)
        throws -> [OriginalSingularFieldEndpoint] {
        guard !polynomial.isZero else {
            throw rationalAlgebraFailure("Original square-free coordinate factor retained a coincident complementary component.")
        }
        let lower = try ExactRationalCoefficient.originalDouble(domain.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(domain.upper, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldEndpoint.self, usage: &usage)
        var result: [OriginalSingularFieldEndpoint] = [.authored(lower), .authored(upper)]
        for root in try OriginalSingularFieldPlaneProjection.sliceRoots(polynomial,
            lower: lower, upper: upper, inheritedDepth: depth,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
            var candidate = OriginalSingularFieldEndpoint.algebraic(root)
            var index = 0, duplicate = false
            while index < result.count {
                var existing = result[index]
                let order = try OriginalSingularFieldEndpoint.compare(&candidate, &existing,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                result[index] = existing
                if order == 0 { duplicate = true; break }
                if order < 0 { break }; index += 1
            }
            if !duplicate {
                try usage.consumeWork(result.count - index)
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldEndpoint.self, usage: &usage)
                result.insert(candidate, at: index)
            }
        }
        return result
    }

    private static func boundary(_ value: ExactRationalCoefficient, alongU: Bool,
        context: OriginalSingularFieldContext, usage: inout OriginalQueryExecution)
        throws -> OriginalSingularFieldPlanePolynomial {
        let station = try OriginalSingularFieldElement.constant(value, in: context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        return try OriginalSingularFieldPlanePolynomial.coordinate(alongU: alongU,
            in: context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            .subtracting(.constant(station, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }

    private static func lift(_ original: OriginalSingularFieldPolynomial, alongU: Bool,
        usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldPlanePolynomial {
        try RationalAlgebraStorage.retain(original.coefficients.count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        var terms: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        for index in original.coefficients.indices {
            try usage.consumeWork(1)
            terms[try .init(u: alongU ? index : 0, v: alongU ? 0 : index)] = original.coefficients[index]
        }
        return try .init(context: original.context, coefficients: terms,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }

    private static func append(points: [OriginalSingularFieldSystemRoot],
        factor: OriginalSingularFieldPlanePolynomial, freeAlongU: Bool,
        field: OriginalSurfaceSilhouetteField, original: OriginalSingularFieldPlanePolynomial,
        domain: SurfaceParameterBox, curves: inout [OriginalSurfaceSilhouetteCurve],
        endpoints: inout [OriginalSingularFieldSystemRoot], usage: inout OriginalQueryExecution) throws {
        guard points.count >= 2 else { throw rationalAlgebraFailure("Original coordinate component lost its closed range endpoints.") }
        let selected = try field.selectingOriginalFieldFactor(factor, usage: &usage)
        for index in 0..<(points.count - 1) {
            let first = points[index], last = points[index + 1]
            let firstDepth = max(first.projectionRoot.isolation.depth, first.fiberRoot.isolation.depth)
            let lastDepth = max(last.projectionRoot.isolation.depth, last.fiberRoot.isolation.depth)
            let image = try SurfaceSilhouetteOrderedFreeParameterImage(
                start: try .init(freeAlongU ? first.u : first.v, depth: firstDepth, using: &usage),
                end: try .init(freeAlongU ? last.u : last.v, depth: lastDepth, using: &usage), usage: &usage)
            let a = SurfaceSilhouetteFieldAtlasEndpoint(original: original,
                location: .station(first, completeHalfBranchCount: 0))
            let b = SurfaceSilhouetteFieldAtlasEndpoint(original: original,
                location: .station(last, completeHalfBranchCount: 0))
            try RationalAlgebraStorage.retain(1, of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
            curves.append(.init(field: selected, chart: domain, freeCoordinate: freeAlongU ? .u : .v,
                orderedFreeImage: image, fieldAtlasStart: a, fieldAtlasEnd: b))
        }
        try RationalAlgebraStorage.retain(points.count, of: OriginalSingularFieldSystemRoot.self, usage: &usage)
        endpoints.append(contentsOf: points)
    }
}
