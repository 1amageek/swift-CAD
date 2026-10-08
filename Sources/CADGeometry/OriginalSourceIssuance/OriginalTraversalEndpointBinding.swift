import CADCore

/// Only original retained endpoint definitions can create this coefficient binding.
struct OriginalTraversalEndpointBinding: Sendable {
    let original: OriginalCurveRootSpan3D
    let start: OriginalExactScalar
    let end: OriginalExactScalar
    let field: OriginalExactScalarDomain
    static func prepare<A: ExactScalarAdmission & ~Copyable>(_ traversals: [OriginalCurveRootSpan3D],
        field initial: borrowing OriginalExactScalarDomain, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [Self] {
        do {
            try admission.checkpoint()
            let count = traversals.count.multipliedReportingOverflow(by: 2)
            guard !count.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count.partialValue, of: OriginalExactScalar.self))
            var coefficients: [OriginalExactScalar] = []; coefficients.reserveCapacity(count.partialValue)
            var field = copy initial
            for traversal in traversals {
                for index in 0..<2 {
                    try admission.consumeWork(1)
                    let endpoint = index == 0 ? traversal.start : traversal.end
                    let value: OriginalExactScalar
                    switch endpoint {
                    case .authored(let station): value = try field.binary64(exactly: station, using: &admission)
                    case .algebraic(let boundary):
                        guard case .algebraic(let retained) = boundary.retainedRootEndpoint else {
                            throw OriginalSourceIssuanceFailure.invalidSource
                        }
                        var existing: OriginalExactScalar?
                        // Original definitions and prior coefficient indices are
                        // already owned. Reuse does not create another registry.
                        for prior in coefficients.indices {
                            try admission.consumeWork(1)
                            let owner = traversals[prior / 2]
                            let endpoint = prior % 2 == 0 ? owner.start : owner.end
                            guard case .algebraic(let boundary) = endpoint,
                                case .algebraic(let root) = boundary.retainedRootEndpoint else { continue }
                            if try sameRoot(retained, root, using: &admission) {
                                existing = try field.importing(coefficients[prior], using: &admission)
                                break
                            }
                        }
                        if let existing { value = existing }
                        else {
                            field = try .init(extending: field, root: retained, axis: .coefficient, using: &admission)
                            value = try field.generator(using: &admission)
                        }
                    }
                    coefficients.append(value)
                }
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: traversals.count, of: Self.self))
            var result: [Self] = []; result.reserveCapacity(traversals.count)
            for index in traversals.indices {
                try admission.consumeWork(1)
                let start = try field.importing(coefficients[index * 2], using: &admission)
                let end = try field.importing(coefficients[index * 2 + 1], using: &admission)
                result.append(.init(original: traversals[index], start: start, end: end, field: field))
            }
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
    private static func sameRoot<A: ExactScalarAdmission & ~Copyable>(
        _ lhs: ExactAlgebraicRealRoot, _ rhs: ExactAlgebraicRealRoot, using admission: inout A
    ) throws(ExactScalarFailure) -> Bool {
        try admission.consumeWork(1)
        guard lhs.isolation.isolationDepth == rhs.isolation.isolationDepth,
            lhs.isolation.excludesLowerEndpoint == rhs.isolation.excludesLowerEndpoint,
            lhs.isolation.excludesUpperEndpoint == rhs.isolation.excludesUpperEndpoint else { return false }
        return try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            guard try lhs.isolation.lower.subtracting(rhs.isolation.lower, usage: &usage).isZero,
                try lhs.isolation.upper.subtracting(rhs.isolation.upper, usage: &usage).isZero else { return false }
            return try lhs.polynomial.subtracting(rhs.polynomial, usage: &usage).isZero
        }.value
    }
}
