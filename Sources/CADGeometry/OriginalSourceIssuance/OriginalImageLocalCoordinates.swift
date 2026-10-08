#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// The exact inverse of the retained authored binary frame, shared by image laws.
struct OriginalImageLocalCoordinates<Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting> {
    let ring: ExactPolynomialDomain<Field>
    let local: [ExactPolynomial<Field>]
    let determinant: Field.Value
    init<Source: OriginalImageFrameReading, A: ExactScalarAdmission & ~Copyable>(
        source original: borrowing Source, field: borrowing Field, requireIdentity: Bool,
        using admission: inout A) throws {
        let ring = try ExactPolynomialDomain(field: copy field, variableCount: 3, using: &admission)
        let zero = try field.integer(0, using: &admission), one = try field.integer(1, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 9, of: Field.Value.self))
        var matrix: [Field.Value] = []; matrix.reserveCapacity(9)
        for row in 0..<3 {
            for column in 0..<3 {
                try admission.consumeWork(1)
                let value = try field.binary64(exactly: original.frame(row: row, column: column), using: &admission)
                if requireIdentity {
                    guard try field.compare(value, row == column ? one : zero, using: &admission) == .equal else {
                        throw OriginalSourceIssuanceFailure.invalidSource
                    }
                }
                matrix.append(value)
            }
        }
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 9, of: Field.Value.self))
        var inverse: [Field.Value] = []; inverse.reserveCapacity(9)
        for row in 0..<3 {
            for column in 0..<3 {
                try admission.consumeWork(1)
                let r1 = (column + 1) % 3, r2 = (column + 2) % 3
                let c1 = (row + 1) % 3, c2 = (row + 2) % 3
                inverse.append(try field.subtracting(
                    field.multiplying(matrix[r1*3+c1],matrix[r2*3+c2],using:&admission),
                    field.multiplying(matrix[r1*3+c2],matrix[r2*3+c1],using:&admission), using:&admission))
            }
        }
        var determinant = zero
        for column in 0..<3 {
            try admission.consumeWork(1)
            determinant = try field.adding(determinant,
                field.multiplying(matrix[column],inverse[column*3],using:&admission),using:&admission)
        }
        guard try field.sign(of: determinant, using: &admission) != .zero else {
            throw OriginalSourceIssuanceFailure.invalidSource
        }
        for index in inverse.indices {
            try admission.consumeWork(1)
            inverse[index] = try field.dividing(inverse[index],determinant,using:&admission)
        }
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: ExactPolynomial<Field>.self))
        var relative: [ExactPolynomial<Field>] = [], local: [ExactPolynomial<Field>] = []
        relative.reserveCapacity(3); local.reserveCapacity(3)
        for axis in 0..<3 {
            try admission.consumeWork(1)
            let center = try field.binary64(exactly: original.center(in: axis), using: &admission)
            relative.append(try ring.subtracting(ring.variable(axis,using:&admission),
                ring.constant(center,using:&admission),using:&admission))
        }
        for row in 0..<3 {
            var value = try ring.zero(using:&admission)
            for column in 0..<3 {
                try admission.consumeWork(1)
                value = try ring.adding(value,ring.scaled(relative[column],
                    by:inverse[row*3+column],using:&admission),using:&admission)
            }
            local.append(value)
        }
        self.ring = ring; self.local = local; self.determinant = determinant
    }
}
