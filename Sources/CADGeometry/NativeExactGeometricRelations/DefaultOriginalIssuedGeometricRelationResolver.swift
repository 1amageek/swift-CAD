#if ISSUED_GEOMETRY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import L6
import DI0
import DI
import SourceIssuer
import IssuedGraphs
#endif

public struct DefaultOriginalIssuedGeometricRelationResolver: OriginalIssuedGeometricRelationResolving {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    public init() {}
    public func resolve<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ relations: borrowing OriginalIssuedGraphRelations<S,E,C,T,F,D>, limits: OriginalDomainIdentityLimits,
        geometryLimits: ExactGeometricRelationLimits, maximumPoints: Int, using a: inout A
    ) throws(NativeExactGeometricRelationFailure) -> OriginalIssuedGeometricRelations<S,E,C,T,F,D> {
        do {
            guard maximumPoints >= 0 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
            try relations.admitProof(limits: limits, using: &a)
            let resolver = DefaultExactGeometricGraphRelationResolver<Base>()
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: relations.pairs.count, of: OriginalIssuedGeometricRelationPair.self))
            var pairs: [OriginalIssuedGeometricRelationPair] = []; pairs.reserveCapacity(relations.pairs.count)
            var points: [OriginalIssuedExactIntersectionPoint] = []
            var strataCount = 0, componentCount = 0
            for pair in relations.pairs {
                try a.consumeWork(1)
                let geometry = try resolver.resolve(pair.relation, limits: geometryLimits, using: &a)
                let stratumSum = strataCount.addingReportingOverflow(geometry.strata.count)
                let componentSum = componentCount.addingReportingOverflow(pair.relation.components.count)
                guard !stratumSum.overflow, !componentSum.overflow else { throw ExactGeometricRelationFailure.countOverflow }
                strataCount = stratumSum.partialValue; componentCount = componentSum.partialValue
                guard strataCount <= geometryLimits.maximumStrata, componentCount <= geometryLimits.topology.maximumComponents else { throw ExactGeometricRelationFailure.resultLimit }
                for members in pair.relation.components.memberRanges {
                    var isolated = true
                    for m in members { try a.consumeWork(1); if pair.relation.components.members[m].dimension != 0 { isolated = false } }
                    guard isolated else { continue }
                    for m in members {
                        guard points.count < maximumPoints else { throw ExactGeometricRelationFailure.resultLimit }
                        let cell = pair.relation.components.members[m]
                        var ordinal: Int? = nil
                        for i in pair.relation.selection.cells.indices { try a.consumeWork(1); if pair.relation.selection.cells[i] == cell { ordinal = i; break } }
                        guard let ordinal else { throw ExactGeometricRelationFailure.invalidCoverage }
                        let local = try resolver.point(atParameterOrdinal: ordinal, in: geometry, using: &a)
                        let first = relations.first.graphs[pair.firstGraphIndex].original.graph.parameterTransport
                        let second = relations.second.graphs[pair.secondGraphIndex].original.graph.parameterTransport
                        let firstParameters = try transport(first, coordinates: local.parameters, offset: 0, field: local.witness.field, &a)
                        let secondParameters = try transport(second, coordinates: local.parameters, offset: pair.relation.original.first.parameterCount, field: local.witness.field, &a)
                        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedExactIntersectionPoint.self))
                        points.append(.init(sourceRelation: copy relations, pairOrdinal: pairs.count, local: local, firstParameters: firstParameters, secondParameters: secondParameters))
                    }
                }
                pairs.append(.init(original: pair, geometry: geometry))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedGeometricRelations<S,E,C,T,F,D>.self))
            let result = OriginalIssuedGeometricRelations(original: copy relations, pairs: pairs, exactPoints: points)
            try a.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
    private func transport<A: ExactScalarAdmission & ~Copyable>(_ original: OriginalRationalParameterTransport<Base>,
        coordinates: [Field.Value], offset: Int, field: Field, _ a: inout A) throws -> [Field.Value] {
        let count = original.numerators.count
        guard count == original.denominators.count, offset >= 0, offset <= coordinates.count,
            count <= coordinates.count - offset else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        let ring = try ExactPolynomialDomain(field: field, variableCount: count, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Field.Value.self))
        var local: [Field.Value] = []; local.reserveCapacity(count)
        for i in 0..<count { try a.consumeWork(1); local.append(coordinates[offset + i]) }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Field.Value.self))
        var result: [Field.Value] = []; result.reserveCapacity(count)
        for axis in 0..<count {
            let numerator = try imported(original.numerators[axis], into: ring, field: field, &a)
            let denominator = try imported(original.denominators[axis], into: ring, field: field, &a)
            result.append(try field.dividing(ring.evaluated(numerator, at: local, using: &a).value,
                ring.evaluated(denominator, at: local, using: &a).value, using: &a))
        }
        return result
    }
    private func imported<A: ExactScalarAdmission & ~Copyable>(_ law: ExactPolynomial<Base>,
        into ring: ExactPolynomialDomain<Field>, field: Field, _ a: inout A) throws -> ExactPolynomial<Field> {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: law.termCount, of: ExactPolynomialTerm<Field.Value>.self))
        var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
        for term in law.terms { try a.consumeWork(1); terms.append(.init(powers: term.powers, coefficient: try field.importingBase(term.coefficient, using: &a))) }
        return try ring.polynomial(terms: terms, using: &a)
    }
}
