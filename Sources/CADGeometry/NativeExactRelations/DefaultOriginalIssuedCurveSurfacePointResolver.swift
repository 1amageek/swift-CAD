#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
@testable import SourceIssuer
import OriginalCoordinateTransfer
#endif

/// Consumes exact selected cells once; original correspondence precedes tuple identity.
public struct DefaultOriginalIssuedCurveSurfacePointResolver<First: Sendable, FirstSelection: Sendable,
    Second: Sendable, SecondSelection: Sendable>: OriginalIssuedCurveSurfacePointResolving {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    public init() {}
    public func resolve<A: ExactScalarAdmission & ~Copyable>(
        relation: borrowing OriginalIssuedRelation<First, FirstSelection, Second, SecondSelection>,
        maximumPoints: Int, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedCurveSurfacePointSet<First, FirstSelection, Second, SecondSelection> {
        do {
            let retained = copy relation
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { usage in
                try resolveTracked(relation: retained, maximumPoints: maximumPoints, using: &usage)
            }
        } catch { throw .preserving(error) }
    }
    private func resolveTracked<A: ExactScalarAdmission & ~Copyable>(
        relation: borrowing OriginalIssuedRelation<First, FirstSelection, Second, SecondSelection>,
        maximumPoints: Int, using admission: inout OriginalSourceProofAdmission<A>
    ) throws(NativeExactRelationFailure) -> OriginalIssuedCurveSurfacePointSet<First, FirstSelection, Second, SecondSelection> {
        do {
            try admission.checkpoint()
            guard relation.kind == .curveSurface, maximumPoints >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            guard !relation.hasPositiveDimensionalSolutions else { throw NativeExactRelationFailure.nonDiscreteIntersection }
            for axis in relation.first.original.coverage.effective.axes {
                try admission.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient)
            }
            for axis in relation.second.original.coverage.effective.axes {
                try admission.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient)
            }
            let count = relation.isolatedCellCount, payload = count.multipliedReportingOverflow(by: 3)
            guard count >= 0, !payload.overflow else { throw ExactScalarFailure.countOverflow }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: payload.partialValue, of: Field.Value.self))
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: OriginalIssuedCurveSurfacePointIncidence.self))
            var values: [Field.Value] = []; values.reserveCapacity(payload.partialValue)
            var incidences: [OriginalIssuedCurveSurfacePointIncidence] = []; incidences.reserveCapacity(count)
            for pairIndex in relation.pairs.indices {
                let pair = relation.pairs[pairIndex], exact = pair.relation
                try admission.admitDepth(value: exact.components.depth.value, coefficient: exact.components.depth.coefficient)
                let cells = try ExactRealCellDomain(retaining: exact.original.predicate.source, using: &admission)
                let first = relation.first.maps[pair.firstMapIndex]
                let second = relation.second.maps[pair.secondMapIndex]
                let firstCover = relation.first.original, secondCover = relation.second.original
                let curve = firstCover.laws[firstCover.charts[first.chartIndex].lawIndex]
                let surface = secondCover.laws[secondCover.charts[second.chartIndex].lawIndex]
                for selectedCellIndex in exact.selection.cells.indices {
                    try admission.consumeWork(1)
                    let cell = exact.selection.cells[selectedCellIndex]
                    guard cell.dimension == 0 else { throw NativeExactRelationFailure.nonDiscreteIntersection }
                    let sample = try cells.sample(of: cell, in: exact.selection.partition, using: &admission)
                    guard sample.coordinates.count == 3, incidences.count < count else { throw NativeExactRelationFailure.invalidDomain }
                    let offset = values.count
                    try append(curve, coordinates: sample.coordinates[0..<1], field: sample.field, into: &values, using: &admission)
                    try append(surface, coordinates: sample.coordinates[1..<3], field: sample.field, into: &values, using: &admission)
                    incidences.append(.init(pairIndex: pairIndex, selectedCellIndex: selectedCellIndex, coordinateOffset: offset))
                }
            }
            guard incidences.count == count, values.count == payload.partialValue else { throw NativeExactRelationFailure.invalidDomain }
            let transferred = try DefaultExactOriginalScalarTransporter().transfer(values,
                into: relation.first.original.coverage.request.frame.scalarField, using: &admission)
            let field = transferred.field, originalValues = transferred.values
            try sort(&incidences, values: originalValues, field: field, using: &admission)
            // Count exact groups before allocating the final point payload.
            var unique = 0
            for index in incidences.indices {
                if try index == 0 || !same(incidences[index-1], incidences[index], values: originalValues, field: field, using: &admission) {
                    guard unique < maximumPoints else { throw NativeExactRelationFailure.resultLimit }
                    unique += 1
                }
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: unique, of: OriginalIssuedCurveSurfacePoint.self))
            var points: [OriginalIssuedCurveSurfacePoint] = []; points.reserveCapacity(unique)
            var start = 0
            while start < incidences.count {
                var end = start + 1
                while try end < incidences.count && same(incidences[start], incidences[end], values: originalValues, field: field, using: &admission) { end += 1 }
                let offset = incidences[start].coordinateOffset
                points.append(.init(t: originalValues[offset], u: originalValues[offset+1], v: originalValues[offset+2], incidenceRange: start..<end))
                start = end
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalIssuedCurveSurfacePointSet<First, FirstSelection, Second, SecondSelection>.self))
            let result = OriginalIssuedCurveSurfacePointSet(relation: copy relation, coordinates: transferred, points: points, incidences: incidences, proofDepth: try admission.depth)
            try admission.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
    // In-place heap ordering keeps Swift's implicit sort scratch outside this budgeted path.
    private func sort<A: ExactScalarAdmission & ~Copyable>(
        _ incidences: inout [OriginalIssuedCurveSurfacePointIncidence],
        values: borrowing [OriginalExactScalar], field: borrowing Base, using admission: inout A
    ) throws {
        guard incidences.count > 1 else { return }
        for start in (0..<(incidences.count / 2)).reversed() {
            try sift(&incidences, start: start, end: incidences.count, values: values, field: field, using: &admission)
        }
        for end in (1..<incidences.count).reversed() {
            try admission.consumeWork(1)
            incidences.swapAt(0, end)
            try sift(&incidences, start: 0, end: end, values: values, field: field, using: &admission)
        }
    }
    private func sift<A: ExactScalarAdmission & ~Copyable>(
        _ incidences: inout [OriginalIssuedCurveSurfacePointIncidence], start: Int, end: Int,
        values: borrowing [OriginalExactScalar], field: borrowing Base, using admission: inout A
    ) throws {
        var root = start
        // This bound proves 2 * root + 1 is representable and inside the active heap.
        while end >= 2 && root <= (end - 2) / 2 {
            try admission.consumeWork(1)
            var child = root * 2 + 1
            let right = child + 1
            if try right < end && less(incidences[child], incidences[right], values: values, field: field, using: &admission) {
                child = right
            }
            guard try less(incidences[root], incidences[child], values: values, field: field, using: &admission) else { return }
            incidences.swapAt(root, child); root = child
        }
    }
    private func less<A: ExactScalarAdmission & ~Copyable>(
        _ lhs: OriginalIssuedCurveSurfacePointIncidence, _ rhs: OriginalIssuedCurveSurfacePointIncidence,
        values: borrowing [OriginalExactScalar], field: borrowing Base, using admission: inout A
    ) throws -> Bool {
        for axis in 0..<3 {
            try admission.consumeWork(1)
            let order = try field.compare(values[lhs.coordinateOffset + axis], values[rhs.coordinateOffset + axis], using: &admission)
            if order != .equal { return order == .less }
        }
        return false
    }
    private func same<A: ExactScalarAdmission & ~Copyable>(_ lhs: OriginalIssuedCurveSurfacePointIncidence,
        _ rhs: OriginalIssuedCurveSurfacePointIncidence, values: borrowing [OriginalExactScalar], field: borrowing Base,
        using admission: inout A
    ) throws -> Bool {
        for axis in 0..<3 {
            try admission.consumeWork(1)
            if try field.compare(values[lhs.coordinateOffset + axis], values[rhs.coordinateOffset + axis], using: &admission) != .equal { return false }
        }
        return true
    }
    private func append<S: Sendable, C: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ law: borrowing OriginalRationalChartReceipt<S,C,Base>, coordinates: ArraySlice<Field.Value>, field: borrowing Field,
        into values: inout [Field.Value], using admission: inout A
    ) throws {
        try law.admitProof(using: &admission)
        let n = coordinates.count
        guard law.parameterTransport.numerators.count == n, law.parameterTransport.denominators.count == n else {
            throw NativeExactRelationFailure.invalidDomain
        }
        let ring = try ExactPolynomialDomain(field: copy field, variableCount: n, using: &admission)
        // The solver's sample owner is retained by the transferred coordinate receipt.
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n, of: Field.Value.self))
        let at = Array(coordinates)
        for axis in 0..<n {
            let numerator = try imported(law.parameterTransport.numerators[axis], into: ring, field: field, using: &admission)
            let denominator = try imported(law.parameterTransport.denominators[axis], into: ring, field: field, using: &admission)
            let a = try ring.evaluated(numerator, at: at, using: &admission).value
            let b = try ring.evaluated(denominator, at: at, using: &admission).value
            guard try field.sign(of: b, using: &admission) != .zero else { throw NativeExactRelationFailure.invalidDomain }
            values.append(try field.dividing(a, b, using: &admission))
        }
    }
    private func imported<A: ExactScalarAdmission & ~Copyable>(_ law: ExactPolynomial<Base>,
        into ring: ExactPolynomialDomain<Field>, field: borrowing Field, using admission: inout A
    ) throws -> ExactPolynomial<Field> {
        try admission.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: law.terms.count, of: ExactPolynomialTerm<Field.Value>.self))
        var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.terms.count)
        for term in law.terms {
            try admission.consumeWork(1)
            terms.append(.init(powers: term.powers, coefficient: try field.importingBase(term.coefficient, using: &admission)))
        }
        return try ring.polynomial(terms: terms, using: &admission)
    }
}
