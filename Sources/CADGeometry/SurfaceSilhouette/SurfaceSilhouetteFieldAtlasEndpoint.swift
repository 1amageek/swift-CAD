import CADCore

/// Original ordered-field station or fiber; equality is exact UV source equality.
struct SurfaceSilhouetteFieldAtlasEndpoint: Sendable {
    enum Location: Sendable {
        case station(OriginalSingularFieldSystemRoot, completeHalfBranchCount: Int)
        case fiber(ExactRationalCoefficient, OriginalSingularFieldRoot)
    }
    let original: OriginalSingularFieldPlanePolynomial
    let location: Location
    let completeIncidenceCount: Int

    init(original: OriginalSingularFieldPlanePolynomial, location: Location,
        completeIncidenceCount: Int = 0) {
        self.original = original; self.location = location
        self.completeIncidenceCount = completeIncidenceCount
    }

    func retainingCompleteIncidence(_ count: Int) -> Self {
        Self(original: original, location: location, completeIncidenceCount: count)
    }

    private var incidenceCount: Int {
        if completeIncidenceCount > 0 { return completeIncidenceCount }
        if case .station(_, let count) = location { return count }
        return 0
    }

    func parameters(usage: inout SurfaceSilhouetteUsage)
        throws -> (u: OriginalSingularFieldElement, v: OriginalSingularFieldElement) {
        switch location {
        case .station(let root, _):
            return (try root.u.embedded(in: root.v.context, maximumDepth: usage.maximumDepth, usage: &usage), root.v)
        case .fiber(let u, let v):
            let second = try v.value(maximumDepth: usage.maximumDepth, usage: &usage)
            return (try .constant(u, in: second.context, maximumDepth: usage.maximumDepth, usage: &usage), second)
        }
    }

    func sign(of expression: ExactBivariatePolynomial, usage: inout SurfaceSilhouetteUsage)
        throws -> ExactAlgebraicRealRoot.Sign {
        let point = try parameters(usage: &usage)
        let lifted = try OriginalFieldHomogeneousImage.lift(expression, into: point.v.context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        return try lifted.evaluated(atU: point.u, v: point.v,
            maximumDepth: usage.maximumDepth, usage: &usage).sign(maximumDepth: usage.maximumDepth, usage: &usage)
    }

    func hasSameValue(as other: Self, usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        let a = try parameters(usage: &usage), b = try other.parameters(usage: &usage)
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(b.v.context, into: a.v.context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let u = try a.u.embedded(in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let v = try a.v.embedded(in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let x = try transport.applying(to: b.u, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let y = try transport.applying(to: b.v, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        guard case .zero = try u.subtracting(x, maximumDepth: usage.maximumDepth, usage: &usage)
            .sign(maximumDepth: usage.maximumDepth, usage: &usage),
            case .zero = try v.subtracting(y, maximumDepth: usage.maximumDepth, usage: &usage)
                .sign(maximumDepth: usage.maximumDepth, usage: &usage) else { return false }
        return true
    }

    func hasSameValue(as other: SurfaceSilhouetteAtlasEndpoint,
        usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        try matches(other.originalFieldParameters(usage: &usage), translatingOther: nil, usage: &usage)
    }

    func coordinateEquals(_ value: Double, alongU: Bool, usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        let point = try parameters(usage: &usage)
        let coordinate = alongU ? point.u : point.v
        let raw = try OriginalSingularFieldElement.constant(.originalDouble(value, usage: &usage),
            in: coordinate.context, maximumDepth: usage.maximumDepth, usage: &usage)
        if case .zero = try coordinate.subtracting(raw, maximumDepth: usage.maximumDepth, usage: &usage)
            .sign(maximumDepth: usage.maximumDepth, usage: &usage) { return true }
        return false
    }

    func hasSameValue(as other: Self, translatingOther translation: (alongU: Bool, amount: ExactRationalCoefficient),
        usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        try matches(other.parameters(usage: &usage), translatingOther: translation, usage: &usage)
    }

    private func matches(_ b: (u: OriginalSingularFieldElement, v: OriginalSingularFieldElement),
        translatingOther translation: (alongU: Bool, amount: ExactRationalCoefficient)?,
        usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        let a = try parameters(usage: &usage)
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(b.v.context, into: a.v.context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let first = try a.u.embedded(in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let second = try a.v.embedded(in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        var u = try transport.applying(to: b.u, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        var v = try transport.applying(to: b.v, in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        if let translation {
            let amount = try OriginalSingularFieldElement.constant(translation.amount, in: context,
                maximumDepth: usage.maximumDepth, usage: &usage)
            // The second source chart is at first+amount; express it in first's chart.
            if translation.alongU { u = try u.subtracting(amount, maximumDepth: usage.maximumDepth, usage: &usage) }
            else { v = try v.subtracting(amount, maximumDepth: usage.maximumDepth, usage: &usage) }
        }
        guard case .zero = try first.subtracting(u, maximumDepth: usage.maximumDepth, usage: &usage)
            .sign(maximumDepth: usage.maximumDepth, usage: &usage),
            case .zero = try second.subtracting(v, maximumDepth: usage.maximumDepth, usage: &usage)
                .sign(maximumDepth: usage.maximumDepth, usage: &usage) else { return false }
        return true
    }

    func certifiesStationIncidence(with other: Self, usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        guard original.context === other.original.context,
            incidenceCount > 0, incidenceCount == other.incidenceCount else { return false }
        guard try original.subtracting(other.original, maximumDepth: usage.maximumDepth, usage: &usage).isZero else { return false }
        return try hasSameValue(as: other, usage: &usage)
    }

    func isSingularStation(usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        guard case .station(let root, _) = location else { return false }
        let u = try original.differentiated(alongU: true, maximumDepth: usage.maximumDepth, usage: &usage)
        let v = try original.differentiated(alongU: false, maximumDepth: usage.maximumDepth, usage: &usage)
        if case .zero = try root.sign(of: u, maximumDepth: usage.maximumDepth, usage: &usage),
            case .zero = try root.sign(of: v, maximumDepth: usage.maximumDepth, usage: &usage) { return true }
        return false
    }
}
