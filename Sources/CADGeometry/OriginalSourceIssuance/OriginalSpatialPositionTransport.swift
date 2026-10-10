#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Shared position composition; callers first verify original source/child authority.
enum OriginalSpatialPositionTransport {
    static func applying<S: OriginalSpatialSourceReading,C: OriginalSourceCoefficientImporting,
        F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,A: ExactScalarAdmission & ~Copyable>(
        source: borrowing S, homogeneous: borrowing [ExactPolynomial<F>], ring: borrowing ExactPolynomialDomain<F>,
        coefficients: borrowing C, using admission: inout A) throws -> [ExactPolynomial<F>]
        where F.Source == F.Value,S.Coefficient == F.Source,C.Field == F {
        guard homogeneous.count == 4 else { throw OriginalSourceIssuanceFailure.invalidChart }
        let field=ring.field
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<F>.self))
        var h: [ExactPolynomial<F>] = []; h.reserveCapacity(4)
        for axis in 0..<4 { h.append(try ring.importing(homogeneous[axis], using: &admission)) }
        guard try !ring.isZero(h[3], using: &admission) else { throw OriginalSourceIssuanceFailure.invalidSource }
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<F>.self))
        var output: [ExactPolynomial<F>] = []; output.reserveCapacity(4)
        for row in 0..<3 {
            var sum = try ring.zero(using: &admission)
            for column in 0..<4 {
                try admission.consumeWork(1)
                let coefficient = try coefficients.importing(source.spatialCoefficient(row: row, column: column), into: field, using: &admission)
                sum = try ring.adding(sum, ring.scaled(h[column], by: coefficient, using: &admission), using: &admission)
            }
            output.append(sum)
        }
        output.append(h[3])
        return output
    }
}
