import CADCore

/// Original Coons and target source ownership attached to the exact relation.
package struct OriginalCoonsIntersectionRelation: Sendable {
    package typealias Target = OriginalRuledIntersectionRelation.Target
    package let coons: OriginalCoonsSurfacePolynomial
    package let target: Target
    package let relation: OriginalPolynomialRelation
}

extension OriginalCoonsSurfacePolynomial {
    /// CS uses (native curve t, original normalized Coons u/v).
    package func curveRelation<B: RationalAlgebraAdmitting>(curve: OriginalRationalCurvePolynomial,
        curveDomain: OriginalRationalParameterDomain, usage: inout B) throws -> OriginalCoonsIntersectionRelation {
        let native = try OriginalRationalParameterDomain(lower: curve.lowerParameter,
            upper: curve.upperParameter, usage: &usage)
        try OriginalRuledRelationEquations.requireContained(curveDomain, in: native, tolerance: nil, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: OriginalRationalParameterDomain.self, usage: &usage)
        let relation = try OriginalRuledRelationEquations.relation(first: curve.homogeneous, second: homogeneous,
            variableCount: 3, firstU: 0, firstV: nil, secondU: 1, secondV: 2,
            domains: [curveDomain, uDomain, vDomain], usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalCoonsIntersectionRelation.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(coons: self, target: .curve(curve), relation: relation)
    }

    /// SSI uses (original normalized Coons u/v, native surface s/t).
    package func surfaceRelation<B: RationalAlgebraAdmitting>(surface: OriginalRationalSurfacePolynomial,
        usage: inout B) throws -> OriginalCoonsIntersectionRelation {
        let s = try OriginalRationalParameterDomain(surface.domain.u, usage: &usage)
        let t = try OriginalRationalParameterDomain(surface.domain.v, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: OriginalRationalParameterDomain.self, usage: &usage)
        let relation = try OriginalRuledRelationEquations.relation(first: homogeneous, second: surface.homogeneous,
            variableCount: 4, firstU: 0, firstV: 1, secondU: 2, secondV: 3,
            domains: [uDomain, vDomain, s, t], usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalCoonsIntersectionRelation.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(coons: self, target: .surface(surface), relation: relation)
    }
}
