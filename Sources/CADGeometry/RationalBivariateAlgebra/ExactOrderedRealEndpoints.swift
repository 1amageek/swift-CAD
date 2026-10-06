/// Exact endpoint ordering without replacing original algebraic events by binary labels.
package struct ExactOrderedRealEndpoints {
    package static func compare<B: RationalAlgebraAdmitting>(_ a: inout ExactMonotoneGraphEndpoint,
        _ b: inout ExactMonotoneGraphEndpoint, maximumDepth: Int, usage: inout B) throws -> Int {
        if try a.hasSameValue(as: b, maximumDepth: maximumDepth, usage: &usage) { return 0 }
        while true {
            try usage.consumeExactWork(1)
            if try b.lower.subtracting(a.upper, usage: &usage).isPositive { return -1 }
            if try a.lower.subtracting(b.upper, usage: &usage).isPositive { return 1 }
            try refine(&a, maximumDepth: maximumDepth, usage: &usage)
            try refine(&b, maximumDepth: maximumDepth, usage: &usage)
        }
    }

    package static func between<B: RationalAlgebraAdmitting>(_ lower: inout ExactMonotoneGraphEndpoint,
        _ upper: inout ExactMonotoneGraphEndpoint, maximumDepth: Int, usage: inout B) throws -> ExactRationalCoefficient {
        guard try compare(&lower, &upper, maximumDepth: maximumDepth, usage: &usage) < 0 else {
            throw rationalAlgebraFailure("Original branch sector endpoints are not strictly ordered.")
        }
        while true {
            let gap = try upper.lower.subtracting(lower.upper, usage: &usage)
            if gap.isPositive {
                return try lower.upper.adding(upper.lower, usage: &usage)
                    .divided(by: .natural(2, usage: &usage), usage: &usage)
            }
            try refine(&lower, maximumDepth: maximumDepth, usage: &usage)
            try refine(&upper, maximumDepth: maximumDepth, usage: &usage)
        }
    }

    package static func ordered<B: RationalAlgebraAdmitting>(_ input: [ExactMonotoneGraphEndpoint],
        maximumDepth: Int, usage: inout B) throws -> [ExactMonotoneGraphEndpoint] {
        try usage.retainExactStorage(input.count)
        var output: [ExactMonotoneGraphEndpoint] = []
        for endpoint in input {
            var item = endpoint, insertion = output.count, duplicate = false
            for index in output.indices {
                var retained = output[index]
                let order = try compare(&item, &retained, maximumDepth: maximumDepth, usage: &usage)
                output[index] = retained
                if order == 0 { duplicate = true; break }
                if order < 0 { insertion = index; break }
            }
            if !duplicate { output.insert(item, at: insertion) }
        }
        return output
    }

    private static func refine<B: RationalAlgebraAdmitting>(_ endpoint: inout ExactMonotoneGraphEndpoint,
        maximumDepth: Int, usage: inout B) throws {
        if case .authored = endpoint { return }
        let width = try endpoint.upper.subtracting(endpoint.lower, usage: &usage)
        if width.isZero { return }
        endpoint = try endpoint.refined(maximumWidth: width.divided(by: .natural(2, usage: &usage), usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
    }
}
