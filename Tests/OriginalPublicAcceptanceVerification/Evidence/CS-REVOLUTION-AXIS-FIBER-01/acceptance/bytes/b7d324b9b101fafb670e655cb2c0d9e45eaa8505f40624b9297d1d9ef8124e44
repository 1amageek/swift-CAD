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

/// Shared publication of one retained L5 relation; no second decomposition or tuple merging.
struct OriginalIssuedGeometricPublication {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    let pairs: [OriginalIssuedGeometricRelationPair]
    let points: [OriginalIssuedExactIntersectionPoint]
    static func resolve<R: OriginalIssuedGraphRelationOwning,A: ExactScalarAdmission & ~Copyable>(
        _ relations: borrowing R, geometryLimits: ExactGeometricRelationLimits, maximumPoints: Int,
        transports: (OriginalIssuedGraphRelationPair) -> (OriginalRationalParameterTransport<Base>,OriginalRationalParameterTransport<Base>?),
        firstCoordinates: ((OriginalIssuedGraphRelationPair) -> [ExactPolynomial<Base>])? = nil,
        using a: inout A) throws -> Self {
        guard maximumPoints >= 0 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        let resolver = DefaultExactGeometricGraphRelationResolver<Base>()
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:relations.pairs.count,of:OriginalIssuedGeometricRelationPair.self))
        var pairs: [OriginalIssuedGeometricRelationPair] = []; pairs.reserveCapacity(relations.pairs.count)
        var points: [OriginalIssuedExactIntersectionPoint] = []
        // Erase the immutable full source owner once, sharing its retained box across points.
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:R.self))
        let owner: any OriginalIssuedGraphRelationOwning = copy relations
        var strataCount = 0, componentCount = 0
        for pair in relations.pairs {
            try a.consumeWork(1)
            let geometry = try resolver.resolve(pair.relation,limits:geometryLimits,using:&a)
            let stratumSum = strataCount.addingReportingOverflow(geometry.strata.count)
            let componentSum = componentCount.addingReportingOverflow(pair.relation.components.count)
            guard !stratumSum.overflow,!componentSum.overflow else { throw ExactGeometricRelationFailure.countOverflow }
            strataCount = stratumSum.partialValue; componentCount = componentSum.partialValue
            guard strataCount <= geometryLimits.maximumStrata,componentCount <= geometryLimits.topology.maximumComponents else { throw ExactGeometricRelationFailure.resultLimit }
            let maps = transports(pair)
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
                    let local = try resolver.point(atParameterOrdinal:ordinal,in:geometry,using:&a)
                    let first = try transport(maps.0,coordinates:local.parameters,offset:0,field:local.witness.field,using:&a)
                    let second: [Field.Value]
                    if let map = maps.1 {
                        second = try transport(map,coordinates:local.parameters,offset:pair.relation.original.first.parameterCount,field:local.witness.field,using:&a)
                    } else {
                        let offset = pair.relation.original.first.parameterCount, count = pair.relation.original.second.parameterCount
                        guard offset >= 0,count >= 0,offset <= local.parameters.count,count <= local.parameters.count-offset else { throw ExactGeometricRelationFailure.invalidSourceBinding }
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Field.Value.self))
                        var values: [Field.Value] = []; values.reserveCapacity(count)
                        for i in 0..<count { try a.consumeWork(1);values.append(local.parameters[offset+i]) }
                        second = values
                    }
                    let restored: [Field.Value]?
                    if let firstCoordinates {
                        let laws = firstCoordinates(pair), count = pair.relation.original.first.parameterCount
                        guard count >= 0,count <= local.parameters.count else { throw ExactGeometricRelationFailure.invalidSourceBinding }
                        let ring = try ExactPolynomialDomain(field:local.witness.field,variableCount:count,using:&a)
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Field.Value.self))
                        var tuple: [Field.Value] = []; tuple.reserveCapacity(count)
                        for i in 0..<count { try a.consumeWork(1);tuple.append(local.parameters[i]) }
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:laws.count,of:Field.Value.self))
                        var values: [Field.Value] = []; values.reserveCapacity(laws.count)
                        for law in laws {
                            try a.consumeWork(1)
                            values.append(try ring.evaluated(imported(law,into:ring,field:local.witness.field,using:&a),at:tuple,using:&a).value)
                        }
                        restored = values
                    } else { restored = nil }
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedExactIntersectionPoint.self))
                    points.append(.init(sourceRelation:owner,pairOrdinal:pairs.count,local:local,firstParameters:first,secondParameters:second,originalFirstCoordinates:restored))
                }
            }
            pairs.append(.init(original:pair,geometry:geometry))
        }
        try a.checkpoint(); return .init(pairs:pairs,points:points)
    }
    private static func transport<A: ExactScalarAdmission & ~Copyable>(_ original: OriginalRationalParameterTransport<Base>,
        coordinates: [Field.Value], offset: Int, field: Field, using a: inout A) throws -> [Field.Value] {
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
            let numerator = try imported(original.numerators[axis], into: ring, field: field, using: &a)
            let denominator = try imported(original.denominators[axis], into: ring, field: field, using: &a)
            result.append(try field.dividing(ring.evaluated(numerator, at: local, using: &a).value,
                ring.evaluated(denominator, at: local, using: &a).value, using: &a))
        }
        return result
    }
    private static func imported<A: ExactScalarAdmission & ~Copyable>(_ law: ExactPolynomial<Base>,
        into ring: ExactPolynomialDomain<Field>, field: Field, using a: inout A) throws -> ExactPolynomial<Field> {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: law.termCount, of: ExactPolynomialTerm<Field.Value>.self))
        var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
        for term in law.terms { try a.consumeWork(1); terms.append(.init(powers: term.powers, coefficient: try field.importingBase(term.coefficient, using: &a))) }
        return try ring.polynomial(terms: terms, using: &a)
    }
}
