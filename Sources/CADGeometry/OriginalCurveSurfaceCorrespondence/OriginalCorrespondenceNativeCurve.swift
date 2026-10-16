import CADCore

/// Original coefficient slices, with no extraction, insertion or rounded trimming.
struct OriginalCorrespondenceNativeCurve {
    struct Span {
        let lower: Double
        let upper: Double
        let firstControl: Int
    }
    let source: BSplineCurve3D
    let spans: [Span]
    let lower: Double
    let upper: Double

    init(source: BSplineCurve3D, maximumDegree: Int, policy: OriginalCorrespondencePolicy, using execution: inout OriginalQueryExecution) throws {
        guard !source.isPeriodic, (1...maximumDegree).contains(source.degree) else { throw policy.unsupported() }
        try source.validate(tolerance: policy.tolerance, using: &execution)
        guard source.knots.prefix(source.degree + 1).allSatisfy({ $0 == source.knots[source.degree] }),
              source.knots.suffix(source.degree + 1).allSatisfy({ $0 == source.knots[source.controlPointCount] }) else {
            throw policy.unsupported()
        }
        lower = source.knots[source.degree]
        upper = source.knots[source.controlPointCount]
        self.source = source
        var index = source.degree + 1
        while index < source.controlPointCount {
            var end = index + 1
            while end < source.controlPointCount, source.knots[end] == source.knots[index] { end += 1 }
            guard end - index == source.degree else { throw policy.unsupported() }
            index = end
        }
        let capacity = source.controlPointCount - source.degree
        try OriginalCoefficientAllocation.reserve(count: capacity, of: Span.self, using: &execution)
        var records: [Span] = []
        records.reserveCapacity(capacity)
        for index in source.degree..<source.controlPointCount where source.knots[index] < source.knots[index + 1] {
            try policy.charge(using: &execution)
            records.append(Span(lower: source.knots[index], upper: source.knots[index + 1],
                firstControl: index - source.degree))
        }
        spans = records
    }

    func enclose(parameter: OriginalCorrespondenceScalarJet,
                 policy: OriginalCorrespondencePolicy, using execution: inout OriginalQueryExecution) throws -> [OriginalCorrespondenceScalarJet] {
        // Caller has independently established that the exact parameter stays in this domain.
        let parameter = try parameter.contained(in: OutwardScalarInterval(lower: lower, upper: upper),
            tolerance: policy.tolerance)
        var first = 0, last = spans.count
        while first < last {
            let mid = first + (last - first) / 2
            if spans[mid].upper < parameter.value.lower { first = mid + 1 } else { last = mid }
        }
        var result: [OriginalCorrespondenceScalarJet]?
        var index = first
        while index < spans.count, spans[index].lower <= parameter.value.upper {
            try policy.charge(using: &execution)
            let span = spans[index]
            let selected = try parameter.contained(in: OutwardScalarInterval(lower: span.lower, upper: span.upper),
                tolerance: policy.tolerance)
            let q = try (selected - .constant(span.lower)).divided(
                by: .constant(span.upper) - .constant(span.lower), tolerance: policy.tolerance)
                .contained(in: OutwardScalarInterval(lower: 0, upper: 1), tolerance: policy.tolerance)
            let jets = try patch(span, at: q, tolerance: policy.tolerance, using: &execution)
            if let old = result { try OriginalCoefficientAllocation.reserve(count: old.count, of: OriginalCorrespondenceScalarJet.self, using: &execution); result = zip(old, jets).map { $0.union($1) } } else { result = jets }
            index += 1
        }
        guard let result else {
            throw OriginalCorrespondencePolicy.failure(.invalidInput, policy.tolerance,
                "The original parameter does not intersect a retained native curve span.")
        }
        return result
    }

    private func patch(_ span: Span, at q: OriginalCorrespondenceScalarJet,
                       tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [OriginalCorrespondenceScalarJet] {
        let indices = span.firstControl...(span.firstControl + source.degree)
        var weightLower = Double.infinity, weightUpper = -Double.infinity
        for index in indices {
            weightLower = min(weightLower, source.weights[index])
            weightUpper = max(weightUpper, source.weights[index])
        }
        try OriginalCoefficientAllocation.reserve(count: indices.count, of: OriginalCorrespondenceScalarJet.self, using: &execution)
        var weights = indices.map { OriginalCorrespondenceScalarJet.constant(source.weights[$0]) }
        let commonWeight = weightLower == weightUpper
        let weight = commonWeight ? OriginalCorrespondenceScalarJet.constant(weightLower)
            : try evaluate(&weights, at: q, using: &execution).contained(
                in: OutwardScalarInterval(lower: weightLower, upper: weightUpper), tolerance: tolerance)
        try OriginalCoefficientAllocation.reserve(count: 3, of: OriginalCorrespondenceScalarJet.self, using: &execution)
        var result: [OriginalCorrespondenceScalarJet] = []
        result.reserveCapacity(3)
        for axis in 0..<3 {
            func coordinate(_ index: Int) -> Double {
                let p = source.controlPoints[index]
                return axis == 0 ? p.x : axis == 1 ? p.y : p.z
            }
            var low = Double.infinity, high = -Double.infinity
            try OriginalCoefficientAllocation.reserve(count: indices.count, of: OriginalCorrespondenceScalarJet.self, using: &execution)
            var controls: [OriginalCorrespondenceScalarJet] = []
            controls.reserveCapacity(indices.count)
            for index in indices {
                let value = coordinate(index)
                low = min(low, value); high = max(high, value)
                controls.append(.constant(value) * .constant(source.weights[index]))
            }
            // A common Cartesian coordinate is an exact rational identity.
            if low == high { result.append(.constant(low)); continue }
            let value = try evaluate(&controls, at: q, using: &execution).divided(by: weight, tolerance: tolerance)
                .contained(in: OutwardScalarInterval(lower: low, upper: high), tolerance: tolerance)
            result.append(value)
        }
        return result
    }

    private func evaluate(_ level: inout [OriginalCorrespondenceScalarJet],
                          at q: OriginalCorrespondenceScalarJet, using execution: inout OriginalQueryExecution) throws -> OriginalCorrespondenceScalarJet {
        var count = level.count
        let complement = OriginalCorrespondenceScalarJet.constant(1) - q
        while count > 1 {
            for index in 0..<(count - 1) { try execution.consumeWork(1); level[index] = level[index] * complement + level[index + 1] * q }
            count -= 1
        }
        return level[0]
    }
}
