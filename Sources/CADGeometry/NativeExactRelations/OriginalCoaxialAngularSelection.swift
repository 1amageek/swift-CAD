/// Exact modulo-one image of selected original angular labels.
struct OriginalCoaxialAngularSelection {
    typealias Field = OriginalPhysicalAngleScalarDomain
    typealias Value = Field.Value
    static func residue<A: ExactScalarAdmission & ~Copyable>(axis: ExactParameterSet<Field>, offset: Value,
        period: Value, field f: Field, domain: ExactParameterDomain<Field>, using a: inout A) throws -> ExactParameterSet<Field> {
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
        let whole = try domain.interval(lower: .finite(zero), upper: .finite(one), includesUpper: false, using: &a)
        var output: [ExactParameterInterval<Value>] = []
        for interval in axis.intervals where !interval.isEmpty {
            try a.consumeWork(1)
            guard case .finite(let rawLower) = interval.lower, case .finite(let rawUpper) = interval.upper else {
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Value>.self))
                return try domain.set(intervals: [whole], using: &a)
            }
            let lo = try f.dividing(f.subtracting(rawLower, offset, using: &a), period, using: &a)
            let hi = try f.dividing(f.subtracting(rawUpper, offset, using: &a), period, using: &a)
            let width = try f.subtracting(hi, lo, using: &a)
            let order = try f.compare(width, one, using: &a)
            if order == .greater || order == .equal && (interval.includesLower || interval.includesUpper) {
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Value>.self))
                return try domain.set(intervals: [whole], using: &a)
            }
            let cycle = try OriginalParameterCycle.floor(lo, field: f, using: &a).scalar(in: f, using: &a)
            let lower = try f.subtracting(lo, cycle, using: &a), upper = try f.subtracting(hi, cycle, using: &a)
            let upperOrder = try f.compare(upper, one, using: &a)
            let first = try domain.interval(lower: .finite(lower), upper: .finite(upperOrder == .less ? upper : one),
                includesLower: interval.includesLower, includesUpper: upperOrder == .less && interval.includesUpper, using: &a)
            if !first.isEmpty { try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Value>.self)); output.append(first) }
            if upperOrder == .greater || upperOrder == .equal && interval.includesUpper {
                let end = try f.subtracting(upper, one, using: &a)
                let second = try domain.interval(lower: .finite(zero), upper: .finite(end),
                    includesLower: true, includesUpper: interval.includesUpper, using: &a)
                if !second.isEmpty { try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<Value>.self)); output.append(second) }
            }
        }
        return try domain.set(intervals: output, using: &a)
    }
}
