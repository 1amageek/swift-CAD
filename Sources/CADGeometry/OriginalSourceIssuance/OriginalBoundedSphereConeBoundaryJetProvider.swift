import CADCore

struct OriginalBoundedSphereConeBoundaryJetProvider: Sendable {
    typealias Source = OriginalBoundedSphereConeSurfaceSnapshot
    typealias RationalLaw = OriginalAnalyticCoordinateLawReceipt<
        OriginalAnalyticCoordinateSnapshot, ExactRationalScalarDomain>

    let source: OriginalSourceBinding<Source>
    private let sphereLaw: RationalLaw
    private let coneLaw: RationalLaw
    let proofDepth: ExactScalarDepth

    init<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<Source>,
        limits: OriginalSourceIssuanceLimits, using a: inout A) throws {
        try a.checkpoint()
        try source.require(limits)
        let original = source.original
        try a.admitDepth(value: original.proofDepth.value,
            coefficient: original.proofDepth.coefficient)
        let sphere = original.sphereIsFirst ? original.firstLaw : original.secondLaw
        let cone = original.sphereIsFirst ? original.secondLaw : original.firstLaw
        try sphere.admitProof(limits: limits, using: &a)
        try cone.admitProof(limits: limits, using: &a)
        guard sphere.source.original.coordinateKind == .sphere,
            cone.source.original.coordinateKind == .cone,
            cone.source.original.coneHalfAngle.bitPattern == original.physical.originalRadians.bitPattern
        else { throw OriginalSourceIssuanceFailure.foreignBinding }
        func requireIntrinsic(_ snapshot: OriginalAnalyticCoordinateSnapshot,
            using a: inout A) throws {
            for axis in 0..<2 {
                try a.consumeWork(1)
                guard case .intrinsic = snapshot.angularMap(axis: axis) else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
            }
        }
        try requireIntrinsic(sphere.source.original, using: &a)
        try requireIntrinsic(cone.source.original, using: &a)
        let q = ExactRationalScalarDomain()
        let period = try q.binary64(exactly: 2 * Double.pi, using: &a)
        let embeddedPeriod = try OriginalSourceRationalImport.value(period,
            field: original.field, using: &a)
        guard try original.field.compare(embeddedPeriod, original.labelPeriod, using: &a) == .equal else {
            throw OriginalSourceIssuanceFailure.foreignBinding
        }
        // Reissue the same immutable original child bindings over Q. Physical
        // cone sine/cosine remain coordinate functions, not rounded coefficients.
        let issuer = DefaultOriginalAnalyticCoordinateIssuer<
            OriginalAnalyticCoordinateSnapshot, ExactRationalScalarDomain>()
        let sphereRational = try issuer.issue(source: sphere.source, field: q, limits: limits, using: &a)
        let coneRational = try issuer.issue(source: cone.source, field: q, limits: limits, using: &a)
        guard sphereRational.source.owner === sphere.source.owner,
            coneRational.source.owner === cone.source.owner else {
            throw OriginalSourceIssuanceFailure.foreignBinding
        }
        self.source = source
        sphereLaw = sphereRational
        coneLaw = coneRational
        proofDepth = try a.depth
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        try a.checkpoint()
    }

    func makeSession<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws -> Session {
        try admit(limits: limits, using: &a)
        let pi = try OriginalPiRefinement(&a)
        try a.retainStorage(bytes: MemoryLayout<Session>.stride)
        let physical = try OriginalPhysicalAngleEnclosure(domain: source.original.physical, using: &a)
        return Session(provider: self, pi: pi, physical: physical)
    }

    private func admit<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws {
        try a.checkpoint()
        try source.require(limits)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try sphereLaw.admitProof(limits: limits, using: &a)
        try coneLaw.admitProof(limits: limits, using: &a)
    }

    /// Bounds of one original law, not a root or an intersection certificate.
    struct Jet: Sendable {
        let source: OriginalSourceBinding<Source>
        let isFirst: Bool
        let parameters: SurfaceParameterBox
        let coefficientDepth: Int
        let value: SurfaceIntervalVectorJet
        let proofDepth: ExactScalarDepth
    }

    /// Exclusive query continuation. It stores no execution, callbacks, or budget.
    struct Session: ~Copyable {
        let provider: OriginalBoundedSphereConeBoundaryJetProvider
        private var physical: OriginalPhysicalAngleEnclosure
        private var pi: OriginalPiRefinement
        private var piEvidence: OriginalPiRefinement.Evidence?
        private var physicalBounds: (sine: OriginalPhysicalAngleRationalBounds,
            cosine: OriginalPhysicalAngleRationalBounds)?
        private(set) var coefficientDepth = 0
        private enum IntrinsicAxis: Equatable { case sphereU, sphereV, coneU }
        private struct CachedHarmonics {
            let source: OriginalSourceBinding<Source>
            let axis: IntrinsicAxis
            let lowerBits: UInt64
            let upperBits: UInt64
            let coefficientDepth: Int
            let proofDepth: ExactScalarDepth
            let sine: SurfaceIntervalJet
            let cosine: SurfaceIntervalJet
        }
        private var sphereU: CachedHarmonics?
        private var sphereV: CachedHarmonics?
        private var coneU: CachedHarmonics?

        fileprivate init(provider: OriginalBoundedSphereConeBoundaryJetProvider,
            pi: OriginalPiRefinement, physical: consuming OriginalPhysicalAngleEnclosure) {
            self.provider = provider
            self.pi = pi
            self.physical = physical
        }

        /// Accepts closed boxes including singleton axes. Derivatives are with
        /// respect to the original raw U/V labels, never normalized box fractions.
        mutating func intervalJet<A: ExactScalarAdmission & ~Copyable>(isFirst: Bool,
            overClosedBox box: SurfaceParameterBox, refinementDepth: Int,
            limits: OriginalSourceIssuanceLimits, using a: inout A) throws -> Jet {
            try provider.admit(limits: limits, using: &a)
            try validate(box, isSphere: isFirst == provider.source.original.sphereIsFirst)
            try refine(to: refinementDepth, using: &a)
            let isSphere = isFirst == provider.source.original.sphereIsFirst
            let law = isSphere ? provider.sphereLaw : provider.coneLaw
            let functions = try functionJets(law, isSphere: isSphere, box: box, using: &a)
            guard law.position.count == 3 else { throw OriginalSourceIssuanceFailure.invalidSource }
            let result = try SurfaceIntervalVectorJet(
                x: evaluated(law.position[0], functions: functions, using: &a),
                y: evaluated(law.position[1], functions: functions, using: &a),
                z: evaluated(law.position[2], functions: functions, using: &a))
            guard finite(result.x), finite(result.y), finite(result.z) else {
                throw ExactScalarFailure.unresolved
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Jet.self))
            let receipt = Jet(source: provider.source, isFirst: isFirst, parameters: box,
                coefficientDepth: coefficientDepth, value: result, proofDepth: try a.depth)
            try a.checkpoint()
            return receipt
        }

        mutating func pointJet<A: ExactScalarAdmission & ~Copyable>(isFirst: Bool,
            u: Double, v: Double, refinementDepth: Int,
            limits: OriginalSourceIssuanceLimits, using a: inout A) throws -> Jet {
            let box = SurfaceParameterBox(u: try .init(lower: u, upper: u),
                v: try .init(lower: v, upper: v))
            return try intervalJet(isFirst: isFirst, overClosedBox: box,
                refinementDepth: refinementDepth, limits: limits, using: &a)
        }

        private func validate(_ box: SurfaceParameterBox, isSphere: Bool) throws {
            guard box.u.lower.isFinite, box.u.upper.isFinite,
                box.v.lower.isFinite, box.v.upper.isFinite,
                box.u.lower <= box.u.upper, box.v.lower <= box.v.upper else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            if isSphere {
                guard box.v.lower >= -Double.pi * 0.5, box.v.upper <= Double.pi * 0.5 else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
            } else if box.v.lower < 0 { throw OriginalSourceIssuanceFailure.invalidChart }
        }

        private mutating func refine<A: ExactScalarAdmission & ~Copyable>(to depth: Int,
            using a: inout A) throws {
            guard depth > 0, depth >= coefficientDepth else { throw ExactScalarFailure.invalidEvidence }
            // Reuse cannot escape a later reader's lower coefficient capability.
            try a.admitDepth(value: 0, coefficient: coefficientDepth)
            if physicalBounds != nil, depth == physical.refinementDepth {
                try physical.admitProof(using: &a)
            } else {
                physicalBounds = try physical.enclosing(refinementDepth: depth, using: &a)
            }
            while coefficientDepth < depth {
                let evidence = try pi.nextEvidence(&a)
                piEvidence = evidence
                coefficientDepth = evidence.coefficientDepth
            }
        }

        private mutating func functionJets<A: ExactScalarAdmission & ~Copyable>(_ law: RationalLaw,
            isSphere: Bool, box: SurfaceParameterBox, using a: inout A) throws -> [SurfaceIntervalJet] {
            guard let physicalBounds, let piEvidence else { throw ExactScalarFailure.invalidEvidence }
            try piEvidence.admitProof(using: &a)
            let piBounds = piEvidence.interval
            let q = ExactRationalScalarDomain()
            let period = try q.binary64(exactly: 2 * Double.pi, using: &a)
            let scaleBounds = try piBounds.multiplying(
                .init(q.dividing(q.integer(2, using: &a), period, using: &a)), q, &a)
            let scale = try outward(scaleBounds, using: &a)
            let scale2 = scale * scale, scale3 = scale2 * scale
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: law.functions.count,
                of: SurfaceIntervalJet.self))
            var result: [SurfaceIntervalJet] = []
            result.reserveCapacity(law.functions.count)
            var uHarmonics: (sine: SurfaceIntervalJet, cosine: SurfaceIntervalJet)?
            var vHarmonics: (sine: SurfaceIntervalJet, cosine: SurfaceIntervalJet)?
            for function in law.functions {
                try a.checkpoint()
                try a.consumeWork(1)
                switch function {
                case .authoredCoordinate(let axis):
                    guard axis == 0 || axis == 1 else { throw ExactScalarFailure.invalidEvidence }
                    result.append(axis == 0 ? .parameterU(box.u) : .parameterV(box.v))
                case .intrinsicCosine(let axis), .intrinsicSine(let axis):
                    guard axis == 0 || axis == 1 else { throw ExactScalarFailure.invalidEvidence }
                    let pair: (sine: SurfaceIntervalJet, cosine: SurfaceIntervalJet)
                    if axis == 0 {
                        if let cached = uHarmonics { pair = cached }
                        else {
                            pair = try cachedNormalizedJets(axis: isSphere ? .sphereU : .coneU,
                                range: box.u, alongU: true, period: period,
                                scale: scale, scale2: scale2, scale3: scale3, using: &a)
                            uHarmonics = pair
                        }
                    } else {
                        guard isSphere else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                        if let cached = vHarmonics { pair = cached }
                        else {
                            pair = try cachedNormalizedJets(axis: .sphereV,
                                range: box.v, alongU: false, period: period,
                                scale: scale, scale2: scale2, scale3: scale3, using: &a)
                            vHarmonics = pair
                        }
                    }
                    if case .intrinsicCosine = function { result.append(pair.cosine) }
                    else { result.append(pair.sine) }
                case .physicalConstantSine(let radians):
                    guard radians.bitPattern == provider.source.original.physical.originalRadians.bitPattern else {
                        throw OriginalSourceIssuanceFailure.foreignBinding
                    }
                    result.append(.constant(try outward(physicalBounds.sine.interval, using: &a)))
                case .physicalConstantCosine(let radians):
                    guard radians.bitPattern == provider.source.original.physical.originalRadians.bitPattern else {
                        throw OriginalSourceIssuanceFailure.foreignBinding
                    }
                    result.append(.constant(try outward(physicalBounds.cosine.interval, using: &a)))
                default: throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
            }
            return result
        }

        private mutating func cachedNormalizedJets<A: ExactScalarAdmission & ~Copyable>(
            axis: IntrinsicAxis, range: ScalarInterval, alongU: Bool,
            period: ExactRationalCoefficient, scale: OutwardScalarInterval,
            scale2: OutwardScalarInterval, scale3: OutwardScalarInterval,
            using a: inout A) throws -> (sine: SurfaceIntervalJet, cosine: SurfaceIntervalJet) {
            try a.checkpoint()
            try a.consumeWork(1)
            let cached: CachedHarmonics?
            switch axis {
            case .sphereU: cached = sphereU
            case .sphereV: cached = sphereV
            case .coneU: cached = coneU
            }
            if let cached, cached.axis == axis,
                cached.source.owner === provider.source.owner,
                cached.lowerBits == range.lower.bitPattern,
                cached.upperBits == range.upper.bitPattern,
                cached.coefficientDepth == coefficientDepth {
                try a.admitDepth(value: cached.proofDepth.value,
                    coefficient: cached.proofDepth.coefficient)
                try a.checkpoint()
                return (cached.sine, cached.cosine)
            }
            let pair = try normalizedJets(range: range, alongU: alongU, period: period,
                scale: scale, scale2: scale2, scale3: scale3, using: &a)
            let entry = CachedHarmonics(source: provider.source, axis: axis,
                lowerBits: range.lower.bitPattern, upperBits: range.upper.bitPattern,
                coefficientDepth: coefficientDepth, proofDepth: try a.depth,
                sine: pair.sine, cosine: pair.cosine)
            switch axis {
            case .sphereU: sphereU = entry
            case .sphereV: sphereV = entry
            case .coneU: coneU = entry
            }
            try a.checkpoint()
            return pair
        }

        private func normalizedJets<A: ExactScalarAdmission & ~Copyable>(
            range: ScalarInterval, alongU: Bool, period: ExactRationalCoefficient,
            scale: OutwardScalarInterval, scale2: OutwardScalarInterval,
            scale3: OutwardScalarInterval, using a: inout A) throws
            -> (sine: SurfaceIntervalJet, cosine: SurfaceIntervalJet) {
            guard let piEvidence else { throw ExactScalarFailure.invalidEvidence }
            let q = ExactRationalScalarDomain()
            let harmonic = try OriginalPhysicalAngleRationalEnclosures.normalizedLabelSineCosine(
                lower: q.binary64(exactly: range.lower, using: &a),
                upper: q.binary64(exactly: range.upper, using: &a),
                labelPeriod: period, refinementDepth: coefficientDepth,
                piEvidence: piEvidence, using: &a)
            let sine = try outward(harmonic.sine.interval, using: &a)
            let cosine = try outward(harmonic.cosine.interval, using: &a)
            let argument: SurfaceIntervalJet = alongU ? .parameterU(range) : .parameterV(range)
            return (
                .applyingUnaryFunction(to: argument, value: sine,
                    firstDerivative: cosine * scale, secondDerivative: -sine * scale2,
                    thirdDerivative: -cosine * scale3),
                .applyingUnaryFunction(to: argument, value: cosine,
                    firstDerivative: -sine * scale, secondDerivative: -cosine * scale2,
                    thirdDerivative: sine * scale3))
        }

        private func finite(_ jet: SurfaceIntervalJet) -> Bool {
            jet.value.isFinite && jet.derivativeU.isFinite && jet.derivativeV.isFinite
                && jet.secondDerivativeUU.isFinite && jet.secondDerivativeUV.isFinite
                && jet.secondDerivativeVV.isFinite && jet.thirdDerivativeUUU.isFinite
                && jet.thirdDerivativeUUV.isFinite && jet.thirdDerivativeUVV.isFinite
                && jet.thirdDerivativeVVV.isFinite
        }

        private func outward<A: ExactScalarAdmission & ~Copyable>(
            _ bounds: OriginalPhysicalAngleInterval, using a: inout A) throws -> OutwardScalarInterval {
            let lower = try bounds.lower.outwardInterval(usage: &a)
            let upper = try bounds.upper.outwardInterval(usage: &a)
            guard lower.lower.isFinite, upper.upper.isFinite, lower.lower <= upper.upper else {
                throw ExactScalarFailure.unresolved
            }
            return .init(lower: lower.lower, upper: upper.upper)
        }

        private func evaluated<A: ExactScalarAdmission & ~Copyable>(
            _ polynomial: ExactPolynomial<ExactRationalScalarDomain>,
            functions: [SurfaceIntervalJet], using a: inout A) throws -> SurfaceIntervalJet {
            try a.admitDepth(value: polynomial.depth.value, coefficient: polynomial.depth.coefficient)
            guard polynomial.variableCount == functions.count else { throw ExactScalarFailure.invalidEvidence }
            var result = SurfaceIntervalJet.constant(0)
            for term in polynomial.terms {
                try a.checkpoint()
                try a.consumeWork(1)
                guard term.powers.count == functions.count else { throw ExactScalarFailure.invalidEvidence }
                var value = SurfaceIntervalJet.constant(try term.coefficient.outwardInterval(usage: &a))
                for axis in functions.indices {
                    var power = term.powers[axis]
                    guard power >= 0 else { throw ExactScalarFailure.invalidEvidence }
                    var factor = functions[axis]
                    while power > 0 {
                        try a.consumeWork(1)
                        if power & 1 != 0 { value = value * factor }
                        power >>= 1
                        if power > 0 { factor = factor * factor }
                    }
                }
                result = result + value
            }
            return result
        }
    }
}
