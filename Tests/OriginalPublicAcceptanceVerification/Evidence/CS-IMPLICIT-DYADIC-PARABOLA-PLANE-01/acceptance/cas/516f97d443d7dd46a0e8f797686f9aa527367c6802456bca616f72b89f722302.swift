/// Validates restored host coordinates against the retained original graph and bijection.
struct OriginalImplicitCurvePointEvaluator: OriginalRationalGraphCurvePointEvaluating {
    typealias Source = OriginalImplicitCurveSnapshot
    typealias Evidence = OriginalImplicitCurveGraphEvidence
    typealias Base = OriginalExactScalarDomain
    typealias Algebraic = ExactAlgebraicScalarDomain<Base>
    typealias Graph = OriginalParametricGraphReceipt<Source,Base,Evidence>

    let reduction: OriginalImplicitCurveGraphReduction

    func admit<A: ExactScalarAdmission & ~Copyable>(_ graph: Graph,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws {
        try a.checkpoint(); try reduction.admitProof(limits: limits.source, using: &a)
        try OriginalRationalGraphPointAccess.requireIdentity(graph, arity: 1, using: &a)
        let evidence = graph.evidence
        let anchor = try reduction.original.source.chart(0, limits: limits.source, using: &a)
        guard graph.source.owns(anchor), reduction.graph.source.owns(anchor),
            graph.layout.auxiliaries.isEmpty, reduction.originalCoordinates.count == 5,
            evidence.parameterPolynomials.variableCount == 1,
            evidence.forwardHostCoordinates.count == 4, evidence.forwardHomogeneous.count == 4,
            evidence.forwardHomogeneousDerivative.count == 4, evidence.hostCoordinateRanges.count == 4 else {
            throw ExactGeometricRelationFailure.invalidSourceBinding
        }
    }

    func validate<A: ExactScalarAdmission & ~Copyable>(_ point: OriginalIssuedExactIntersectionPoint,
        graph: Graph, limits: OriginalDomainIdentityLimits, using a: inout A) throws {
        try reduction.admitProof(limits: limits.source, using: &a)
        guard point.firstParameters.count == 1, let restored = point.originalFirstCoordinates,
            restored.count == 5 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        let field = point.local.witness.field
        let ring = try ExactPolynomialDomain(field: field, variableCount: 1, using: &a)
        for index in 0..<5 {
            try a.consumeWork(1)
            let law = try OriginalRationalGraphPointAccess.imported(reduction.originalCoordinates[index],
                into: ring, using: &a)
            let value = try ring.evaluated(law, at: point.firstParameters, using: &a).value
            guard try field.compare(value, restored[index], using: &a) == .equal else {
                throw ExactGeometricRelationFailure.invalidCoverage
            }
        }
        try validateOriginal(restored, field: field, using: &a)
        let values = try homogeneous(graph.evidence.forwardHomogeneous, at: point.firstParameters, ring: ring, using: &a)
        guard try field.sign(of: values[3], using: &a) != .zero else { throw ExactGeometricRelationFailure.invalidCoverage }
        for index in 0..<3 {
            let coordinate = index == 0 ? point.position.x : index == 1 ? point.position.y : point.position.z
            guard try field.compare(values[index], field.multiplying(coordinate, values[3], using: &a), using: &a) == .equal else {
                throw ExactGeometricRelationFailure.invalidCoverage
            }
        }
    }

    private func validateOriginal<A: ExactScalarAdmission & ~Copyable>(_ coordinates: [Algebraic.Value],
        field: Algebraic, using a: inout A) throws {
        let original = reduction.original
        let ring = try ExactPolynomialDomain(field: field, variableCount: 5, using: &a)
        for axis in original.layout.parameters.indices {
            try a.consumeWork(1)
            let coordinate = coordinates[original.layout.parameters[axis]]
            let lower = try field.compare(coordinate, field.importingBase(original.support[axis].lower, using: &a), using: &a)
            let upper = try field.compare(coordinate, field.importingBase(original.support[axis].upper, using: &a), using: &a)
            guard lower != .less, upper != .greater,
                upper != .equal || original.includesUpperBoundary[axis] else {
                throw ExactGeometricRelationFailure.invalidCoverage
            }
        }
        for condition in original.conditions {
            try a.consumeWork(1)
            let law = try OriginalRationalGraphPointAccess.imported(condition.polynomial, into: ring, using: &a)
            let sign = try field.sign(of: ring.evaluated(law, at: coordinates, using: &a).value, using: &a)
            let accepted: Bool
            switch condition.relation {
            case .equal: accepted = sign == .zero
            case .notEqual: accepted = sign != .zero
            case .positive: accepted = sign == .positive
            case .nonnegative: accepted = sign != .negative
            }
            guard accepted else { throw ExactGeometricRelationFailure.invalidCoverage }
        }
        try a.checkpoint()
    }

    func tangent<A: ExactScalarAdmission & ~Copyable>(_ graph: Graph,
        at parameters: [Algebraic.Value], field: Algebraic, using a: inout A) throws -> [Algebraic.Value] {
        guard parameters.count == 1 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        let ring = try ExactPolynomialDomain(field: field, variableCount: 1, using: &a)
        let value = try homogeneous(graph.evidence.forwardHomogeneous, at: parameters, ring: ring, using: &a)
        let derivative = try homogeneous(graph.evidence.forwardHomogeneousDerivative, at: parameters, ring: ring, using: &a)
        guard try field.sign(of: value[3], using: &a) != .zero else { throw ExactGeometricRelationFailure.invalidCoverage }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Algebraic.Value.self))
        var tangent: [Algebraic.Value] = []; tangent.reserveCapacity(3)
        for axis in 0..<3 {
            try a.consumeWork(1)
            tangent.append(try field.subtracting(field.multiplying(derivative[axis], value[3], using: &a),
                field.multiplying(value[axis], derivative[3], using: &a), using: &a))
        }
        return tangent
    }

    func position<A: ExactScalarAdmission & ~Copyable>(_ graph: Graph, numbers: [Double],
        field: Base, limits: OriginalDomainIdentityLimits, using a: inout A) throws -> [OriginalExactScalar]? {
        guard !numbers.isEmpty else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        let evidence = graph.evidence, ring = evidence.parameterPolynomials
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalExactScalar.self))
        let parameter = [try evidence.field.binary64(exactly: numbers[0], using: &a)]
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 5, of: OriginalExactScalar.self))
        var coordinates: [OriginalExactScalar] = []; coordinates.reserveCapacity(5); coordinates.append(parameter[0])
        for law in evidence.forwardHostCoordinates {
            try a.consumeWork(1); coordinates.append(try ring.evaluated(law, at: parameter, using: &a).value)
        }
        guard try graph.admits(parameter, limits: limits.source, using: &a),
            try reduction.original.admits(coordinates, limits: limits.source, using: &a) else { return nil }
        let originalGraph = reduction.original
        let weight = try ring.evaluated(evidence.forwardHomogeneous[3], at: parameter, using: &a).value
        let originalWeight = try originalGraph.polynomials.evaluated(originalGraph.homogeneous[3], at: coordinates, using: &a).value
        guard try evidence.field.sign(of: weight, using: &a) != .zero,
            try originalGraph.field.sign(of: originalWeight, using: &a) != .zero else { throw ExactGeometricRelationFailure.invalidCoverage }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: OriginalExactScalar.self))
        var result: [OriginalExactScalar] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            try a.consumeWork(1)
            let numerator = try ring.evaluated(evidence.forwardHomogeneous[axis], at: parameter, using: &a).value
            let original = try originalGraph.polynomials.evaluated(originalGraph.homogeneous[axis], at: coordinates, using: &a).value
            guard try evidence.field.compare(evidence.field.multiplying(numerator, originalWeight, using: &a),
                evidence.field.multiplying(original, weight, using: &a), using: &a) == .equal else {
                throw ExactGeometricRelationFailure.invalidCoverage
            }
            result.append(try field.importing(evidence.field.dividing(numerator, weight, using: &a), using: &a))
        }
        return result
    }

    private func homogeneous<A: ExactScalarAdmission & ~Copyable>(_ laws: [ExactPolynomial<Base>],
        at parameters: [Algebraic.Value], ring: ExactPolynomialDomain<Algebraic>, using a: inout A
    ) throws -> [Algebraic.Value] {
        guard laws.count == 4 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Algebraic.Value.self))
        var values: [Algebraic.Value] = []; values.reserveCapacity(4)
        for law in laws {
            try a.consumeWork(1)
            let imported = try OriginalRationalGraphPointAccess.imported(law, into: ring, using: &a)
            values.append(try ring.evaluated(imported, at: parameters, using: &a).value)
        }
        return values
    }
}
