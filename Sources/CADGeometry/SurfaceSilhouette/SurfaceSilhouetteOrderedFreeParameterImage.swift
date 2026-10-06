import CADCore

/// Exact ordered-field free endpoints with a retained original normalized traversal.
struct SurfaceSilhouetteOrderedFreeParameterImage: Hashable, Sendable {
    let start: SurfaceSilhouetteTrimEndpoint
    let end: SurfaceSilhouetteTrimEndpoint
    let gain: OriginalSingularFieldElement
    let gainIsolation: OriginalSingularFieldValueIsolation?
    let width: ExactRationalCoefficient
    let sourceDepth: Int
    let normalizedDomain: ScalarInterval

    init(start: SurfaceSilhouetteTrimEndpoint, end: SurfaceSilhouetteTrimEndpoint,
        usage: inout SurfaceSilhouetteUsage) throws {
        guard try start.compare(to: end, usage: &usage) < 0 else {
            throw rationalAlgebraFailure("Original field free traversal needs strictly increasing source endpoints.")
        }
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(end.original.context, into: start.original.context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let a = try start.original.embedded(in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let b = try transport.applying(to: end.original, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        self.start = .init(a, depth: start.sourceDepth); self.end = .init(b, depth: end.sourceDepth)
        gain = try b.subtracting(a, maximumDepth: usage.maximumDepth, usage: &usage)
        gainIsolation = nil; width = .one
        sourceDepth = max(context.depth, max(start.sourceDepth, end.sourceDepth))
        normalizedDomain = try .init(lower: 0, upper: 1)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
    }

    private init(copy original: Self, start: SurfaceSilhouetteTrimEndpoint,
        end: SurfaceSilhouetteTrimEndpoint, isolation: OriginalSingularFieldValueIsolation,
        width: ExactRationalCoefficient) {
        self.start = start; self.end = end; gain = original.gain; gainIsolation = isolation
        self.width = width; sourceDepth = max(isolation.sourceDepth, max(start.sourceDepth, end.sourceDepth))
        normalizedDomain = original.normalizedDomain
    }

    static func == (a: Self, b: Self) -> Bool {
        OriginalSingularFieldIdentity.same(a.start.original, b.start.original)
            && OriginalSingularFieldIdentity.same(a.end.original, b.end.original)
    }
    func hash(into hasher: inout Hasher) {
        // Exact issued expression identity is conservative; field owners never
        // become floating-point coordinates or unchecked object identifiers.
        hasher.combine(normalizedDomain)
    }

    func refined(usage: inout SurfaceSilhouetteUsage) throws -> Self {
        let width = try width.divided(by: .natural(2, usage: &usage), usage: &usage)
        let first = try start.refined(maximumWidth: width, usage: &usage)
        let last = try end.refined(maximumWidth: width, usage: &usage)
        let old = try gainIsolation ?? .init(original: gain, inheritedDepth: sourceDepth,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let retained = try old.inheriting(depth: max(first.sourceDepth, last.sourceDepth),
            maximumDepth: usage.maximumDepth, usage: &usage).refined(maximumWidth: width,
                maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(copy: self, start: first, end: last, isolation: retained, width: width)
    }

    func mapped(over range: ScalarInterval, nativeCover: ScalarInterval,
        usage: inout SurfaceSilhouetteUsage) throws -> (parameter: ScalarInterval, derivative: OutwardScalarInterval) {
        guard range.lower >= 0, range.upper <= 1 else {
            throw rationalAlgebraFailure("Original field free query exceeds normalized source fractions.")
        }
        let slope = try gainIsolation?.enclosure(usage: &usage)
            ?? gain.enclosure(maximumWidth: width, inheritedDepth: sourceDepth,
                maximumDepth: usage.maximumDepth, usage: &usage)
        func coordinate(_ t: Double) throws -> OutwardScalarInterval {
            if t == 0 || t == 1 {
                let endpoint = t == 0 ? start : end
                let bounds = try endpoint.enclosure(maximumWidth: width, usage: &usage)
                return .init(lower: bounds.lower, upper: bounds.upper)
            }
            let scalar = try OriginalSingularFieldElement.constant(.originalDouble(t, usage: &usage),
                in: start.original.context, maximumDepth: usage.maximumDepth, usage: &usage)
            return try start.original.adding(gain.multiplied(by: scalar, maximumDepth: usage.maximumDepth,
                usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
                .enclosure(maximumWidth: width, inheritedDepth: sourceDepth, maximumDepth: usage.maximumDepth, usage: &usage)
        }
        let a = try coordinate(range.lower), b = try coordinate(range.upper)
        guard let enclosed = OutwardScalarInterval(lower: a.lower, upper: b.upper)
            .intersection(with: .init(lower: nativeCover.lower, upper: nativeCover.upper)) else {
            throw rationalAlgebraFailure("Original field free traversal missed its retained native chart.")
        }
        return try (.init(lower: enclosed.lower, upper: enclosed.upper), slope)
    }
}
