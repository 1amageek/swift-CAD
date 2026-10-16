import CADCore


/// Rational whole-cell proof for the strict original principal-chart capability.
struct OriginalBoundedSphereConeFiniteArcCertifier {
    typealias I = OriginalPhysicalAngleInterval
    /// Scheduling hints do not establish any selected or excluded subset.
    enum UnresolvedReason: Equatable, Sendable {
        case discriminant
        case slant
        case spherePositiveX
        case sphereAzimuthLower
        case sphereAzimuthUpper
        case sphereLatitudeLower
        case sphereLatitudeUpper
    }

    enum Decision: Sendable {
        case selected(CellProof)
        case boundaryCandidate(CellProof)
        case wholeCellExcluded
        case unresolved(reason: UnresolvedReason)
    }

    private enum Outcome {
        case selected(branch: Int)
        case boundaryCandidate(branch: Int, guardReason: UnresolvedReason, slant: I, height: I)
        case wholeCellExcluded
        case unresolved(reason: UnresolvedReason)
    }

    /// A selected cell or unique-guard candidate from one actual checked decision.
    struct CellProof: Sendable {
        enum Kind: Equatable, Sendable {
            case selected
            case boundaryCandidate(guardReason: UnresolvedReason)
        }
        let source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>
        let firstBox: SurfaceParameterBox
        let secondBox: SurfaceParameterBox
        let coneU: ClosedRange<Double>
        let coneCycle: ExactRationalCoefficient
        let sphereCycle: ExactRationalCoefficient
        let principalConeLower: ExactRationalCoefficient
        let principalConeUpper: ExactRationalCoefficient
        let principalSphereLower: ExactRationalCoefficient
        let principalSphereUpper: ExactRationalCoefficient
        let branch: Int
        let kind: Kind
        let proofDepth: ExactScalarDepth
        private let necessarySlantBounds: ScalarInterval?
        private let necessarySphereVBounds: ScalarInterval?

        private init(certifier c: OriginalBoundedSphereConeFiniteArcCertifier,
            branch: Int, kind: Kind, necessarySlantBounds: ScalarInterval?, necessarySphereVBounds: ScalarInterval?, proofDepth: ExactScalarDepth) {
            source = c.binding
            firstBox = c.source.sphereIsFirst ? c.sphere : c.cone
            secondBox = c.source.sphereIsFirst ? c.cone : c.sphere
            coneU = c.cone.u.lower...c.cone.u.upper
            coneCycle = c.coneCycle; sphereCycle = c.sphereCycle
            principalConeLower = c.lower; principalConeUpper = c.upper
            principalSphereLower = c.sphereLower; principalSphereUpper = c.sphereUpper
            self.branch = branch; self.kind = kind; self.proofDepth = proofDepth
            self.necessarySlantBounds = necessarySlantBounds
            self.necessarySphereVBounds = necessarySphereVBounds
        }

        private init(first: Self, last: Self, cone: SurfaceParameterBox,
            necessarySlantBounds: ScalarInterval, necessarySphereVBounds: ScalarInterval, proofDepth: ExactScalarDepth) {
            source = first.source
            firstBox = source.original.sphereIsFirst ? first.firstBox : cone
            secondBox = source.original.sphereIsFirst ? cone : first.secondBox
            coneU = first.coneU.lowerBound...last.coneU.upperBound
            coneCycle = first.coneCycle; sphereCycle = first.sphereCycle
            principalConeLower = first.principalConeLower; principalConeUpper = last.principalConeUpper
            principalSphereLower = first.principalSphereLower; principalSphereUpper = first.principalSphereUpper
            branch = first.branch; kind = first.kind; self.proofDepth = proofDepth
            self.necessarySlantBounds = necessarySlantBounds
            self.necessarySphereVBounds = necessarySphereVBounds
        }

        /// Preserve one unique unresolved guard across an exactly adjacent cover.
        static func unionBoundaryCandidates<A: ExactScalarAdmission & ~Copyable>(
            _ proofs: borrowing [Self], limits: OriginalSourceIssuanceLimits,
            using a: inout A) throws -> Self {
            try a.withProofScope { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard let first = proofs.first, let last = proofs.last,
                    case .boundaryCandidate = first.kind else {
                    throw OriginalSourceIssuanceFailure.invalidSource
                }
                try first.admitProof(limits: limits, using: &a)
                guard let firstBounds = first.necessarySlantBounds,
                    let firstVBounds = first.necessarySphereVBounds else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                let sphereIsFirst = first.source.original.sphereIsFirst
                let sphere = sphereIsFirst ? first.firstBox : first.secondBox
                let firstCone = sphereIsFirst ? first.secondBox : first.firstBox
                guard firstBounds.lower >= firstCone.v.lower, firstBounds.upper <= firstCone.v.upper,
                    firstVBounds.lower >= sphere.v.lower, firstVBounds.upper <= sphere.v.upper else {
                    throw OriginalSourceIssuanceFailure.foreignBinding
                }
                if proofs.count == 1 { try a.checkpoint(); return first }
                let q = ExactRationalScalarDomain()
                var previousUpper = first.coneU.lowerBound
                var lower = firstBounds.lower, upper = firstBounds.upper
                var vLower = firstVBounds.lower, vUpper = firstVBounds.upper
                var index = 0
                while index < proofs.count {
                    let proof = proofs[index]
                    try a.checkpoint(); try a.consumeWork(1)
                    if index != 0 { try proof.admitProof(limits: limits, using: &a) }
                    let proofSphere = sphereIsFirst ? proof.firstBox : proof.secondBox
                    let proofCone = sphereIsFirst ? proof.secondBox : proof.firstBox
                    guard proof.kind == first.kind, proof.source.owner === first.source.owner,
                        proof.branch == first.branch, proofSphere == sphere, proofCone.v == firstCone.v,
                        proof.coneU.lowerBound == previousUpper,
                        proof.coneU.lowerBound < proof.coneU.upperBound,
                        try q.compare(proof.coneCycle, first.coneCycle, using: &a) == .equal,
                        try q.compare(proof.sphereCycle, first.sphereCycle, using: &a) == .equal,
                        let bounds = proof.necessarySlantBounds,
                        bounds.lower >= firstCone.v.lower, bounds.upper <= firstCone.v.upper,
                        let vBounds = proof.necessarySphereVBounds,
                        vBounds.lower >= sphere.v.lower, vBounds.upper <= sphere.v.upper else {
                        throw OriginalSourceIssuanceFailure.foreignBinding
                    }
                    lower = min(lower, bounds.lower); upper = max(upper, bounds.upper)
                    vLower = min(vLower, vBounds.lower); vUpper = max(vUpper, vBounds.upper)
                    previousUpper = proof.coneU.upperBound
                    index += 1
                }
                let cone = SurfaceParameterBox(u: try ScalarInterval(lower: first.coneU.lowerBound,
                    upper: last.coneU.upperBound), v: firstCone.v)
                let bounds = try ScalarInterval(lower: lower, upper: upper)
                let vBounds = try ScalarInterval(lower: vLower, upper: vUpper)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
                let result = Self(first: first, last: last, cone: cone,
                    necessarySlantBounds: bounds, necessarySphereVBounds: vBounds, proofDepth: try a.depth)
                try a.checkpoint(); return result
            }
        }

        fileprivate static func check<A: ExactScalarAdmission & ~Copyable>(
            certifier c: OriginalBoundedSphereConeFiniteArcCertifier,
            coefficients: Coefficients, using a: inout A) throws -> Decision {
            let outcome = try c.decide(Cell(lower: c.lower, upper: c.upper),
                coefficients: coefficients, using: &a)
            switch outcome {
            case .selected(let branch):
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
                return .selected(Self(certifier: c, branch: branch, kind: .selected, necessarySlantBounds: nil, necessarySphereVBounds: nil, proofDepth: try a.depth))
            case .boundaryCandidate(let branch, let reason, let slant, let height):
                let lower = try slant.lower.outwardInterval(usage: &a).lower
                let upper = try slant.upper.outwardInterval(usage: &a).upper
                let bounds = try ScalarInterval(lower: max(c.cone.v.lower, lower),
                    upper: min(c.cone.v.upper, upper))
                let vBounds = try c.necessarySphereVBounds(height: height,
                    depth: coefficients.depth, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
                return .boundaryCandidate(Self(certifier: c, branch: branch,
                    kind: .boundaryCandidate(guardReason: reason),
                    necessarySlantBounds: bounds, necessarySphereVBounds: vBounds, proofDepth: try a.depth))
            case .wholeCellExcluded: return .wholeCellExcluded
            case .unresolved(let reason): return .unresolved(reason: reason)
            }
        }

        /// Necessary chosen-root bounds, never a sampled root or replacement request.
        func candidateSlantBounds<A: ExactScalarAdmission & ~Copyable>(
            limits: OriginalSourceIssuanceLimits, using a: inout A) throws -> ScalarInterval {
            try admitProof(limits: limits, using: &a)
            guard case .boundaryCandidate = kind, let necessarySlantBounds else {
                throw OriginalSourceIssuanceFailure.unresolvedAuthority
            }
            try a.consumeWork(1); try a.checkpoint()
            return necessarySlantBounds
        }

        /// Necessary original-latitude bounds; the original request remains authoritative.
        func candidateSphereVBounds<A: ExactScalarAdmission & ~Copyable>(
            limits: OriginalSourceIssuanceLimits, using a: inout A) throws -> ScalarInterval {
            try admitProof(limits: limits, using: &a)
            guard case .boundaryCandidate = kind, let necessarySphereVBounds else {
                throw OriginalSourceIssuanceFailure.unresolvedAuthority
            }
            try a.consumeWork(1); try a.checkpoint()
            return necessarySphereVBounds
        }

        func admitProof<A: ExactScalarAdmission & ~Copyable>(
            limits: OriginalSourceIssuanceLimits, using a: inout A) throws {
            try a.checkpoint(); try source.require(limits)
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            try a.checkpoint()
        }
    }

    private enum SphereGuardDecision {
        case inside
        case wholeCellExcluded
        case uniqueUnresolved(reason: UnresolvedReason, height: I)
        case unresolved(reason: UnresolvedReason)
    }

    private enum BranchDecision {
        case selected
        case excluded
        case boundaryCandidate(reason: UnresolvedReason, height: I)
        case unresolved(reason: UnresolvedReason)
    }

    let binding: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>
    let source: OriginalBoundedSphereConeSurfaceSnapshot
    let sphere: SurfaceParameterBox
    let cone: SurfaceParameterBox
    let q = ExactRationalScalarDomain()
    let period: ExactRationalCoefficient
    let lower: ExactRationalCoefficient
    let upper: ExactRationalCoefficient
    let sphereLower: ExactRationalCoefficient
    let sphereUpper: ExactRationalCoefficient
    let coneCycle: ExactRationalCoefficient
    let sphereCycle: ExactRationalCoefficient
    let dx: I
    let dz: I
    let radius: I
    let constant: I
    private struct Cell {
        let lower: ExactRationalCoefficient
        let upper: ExactRationalCoefficient
    }
    /// Immutable coefficients for one query-local refinement depth.
    fileprivate struct Coefficients {
        let depth: Int
        let sine: I
        let cosine: I
        let middle: I
        let radial: I
        let azimuthLower: (sine:I,cosine:I)
        let azimuthUpper: (sine:I,cosine:I)
        let latitudeLower: I
        let latitudeUpper: I
        let largestTrigWidth: ExactRationalCoefficient
    }

    struct CoefficientContinuation: ~Copyable {
        fileprivate let binding: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>
        fileprivate let sphere: SurfaceParameterBox
        fileprivate var physical: OriginalPhysicalAngleEnclosure
        fileprivate var coefficients: Coefficients?
        fileprivate var proofDepth: ExactScalarDepth

        fileprivate init(binding: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>,
            sphere: SurfaceParameterBox, physical: consuming OriginalPhysicalAngleEnclosure,
            proofDepth: ExactScalarDepth) {
            self.binding = binding; self.sphere = sphere; self.physical = physical
            coefficients = nil; self.proofDepth = proofDepth
        }
    }

    init<A: ExactScalarAdmission & ~Copyable>(
        source binding: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>,
        sphere: SurfaceParameterBox,cone: SurfaceParameterBox,using a: inout A) throws {
        let source = binding.original
        self.binding = binding
        self.source=source; self.sphere=sphere; self.cone=cone
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:SurfaceParameterBox.self))
        for box in [sphere,cone] {
            guard box.u.lower.isFinite,box.u.upper.isFinite,box.v.lower.isFinite,box.v.upper.isFinite,
                box.u.lower<=box.u.upper,box.v.lower<=box.v.upper else { throw OriginalSourceIssuanceFailure.invalidSource }
        }
        period=try q.binary64(exactly:2*Double.pi,using:&a)
        try Self.requirePeriod(source.firstLaw,period:source.labelPeriod,using:&a)
        try Self.requirePeriod(source.secondLaw,period:source.labelPeriod,using:&a)
        guard try source.field.compare(source.field.binary64(exactly:2*Double.pi,using:&a),source.labelPeriod,using:&a) == .equal else {
            throw OriginalSourceIssuanceFailure.foreignBinding
        }
        let rawLower=try q.binary64(exactly:cone.u.lower,using:&a),rawUpper=try q.binary64(exactly:cone.u.upper,using:&a)
        let rawSphereLower=try q.binary64(exactly:sphere.u.lower,using:&a),rawSphereUpper=try q.binary64(exactly:sphere.u.upper,using:&a)
        coneCycle=try q.dyadicNeighbours(q.dividing(rawLower,period,using:&a),fractionalBits:0,using:&a).lower
        sphereCycle=try q.adding(q.dyadicNeighbours(q.dividing(rawSphereUpper,period,using:&a),fractionalBits:0,using:&a).lower,
            q.integer(1,using:&a),using:&a)
        let coneOffset=try q.multiplying(coneCycle,period,using:&a),sphereOffset=try q.multiplying(sphereCycle,period,using:&a)
        lower=try q.subtracting(rawLower,coneOffset,using:&a); upper=try q.subtracting(rawUpper,coneOffset,using:&a)
        sphereLower=try q.subtracting(rawSphereLower,sphereOffset,using:&a)
        sphereUpper=try q.subtracting(rawSphereUpper,sphereOffset,using:&a)
        let zero=try q.integer(0,using:&a),two=try q.integer(2,using:&a),four=try q.integer(4,using:&a)
        let half=try q.dividing(period,two,using:&a),quarter=try q.dividing(period,four,using:&a)
        guard try q.compare(lower,zero,using:&a) == .greater,
            try q.compare(upper,half,using:&a) == .less,
            try q.compare(q.binary64(exactly:cone.v.lower,using:&a),zero,using:&a) != .less,
            try q.compare(sphereLower,q.negated(half,using:&a),using:&a) == .greater,
            try q.compare(sphereUpper,zero,using:&a) == .less,
            try q.compare(q.binary64(exactly:sphere.v.lower,using:&a),q.negated(quarter,using:&a),using:&a) != .less,
            try q.compare(q.binary64(exactly:sphere.v.upper,using:&a),zero,using:&a) != .greater else {
            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
        }
        dx=try I(q.subtracting(q.binary64(exactly:source.apex.x,using:&a),q.binary64(exactly:source.sphereCenter.x,using:&a),using:&a))
        dz=try I(q.subtracting(q.binary64(exactly:source.sphereCenter.z,using:&a),q.binary64(exactly:source.apex.z,using:&a),using:&a))
        radius=try I(q.binary64(exactly:source.sphereRadius,using:&a))
        constant=try dx.multiplying(dx,q,&a).adding(dz.multiplying(dz,q,&a),q,&a).subtracting(radius.multiplying(radius,q,&a),q,&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Self.self))
    }

    private static func requirePeriod<A:ExactScalarAdmission & ~Copyable>(
        _ law:OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot,OriginalBoundedSphereConeSurfaceSnapshot.Field>,
        period:OriginalBoundedSphereConeSurfaceSnapshot.Field.Value,using a:inout A) throws {
        var found=false
        for proof in law.periods {
            try a.checkpoint(); try a.consumeWork(1)
            guard proof.axis == 0 else { continue }
            guard !found,law.source.owns(proof.anchor),proof.meaning == .intrinsicAngularLabel,
                try law.field.compare(proof.period,period,using:&a) == .equal else {
                throw OriginalSourceIssuanceFailure.foreignBinding
            }
            found=true
        }
        guard found else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
    }

    func makeCoefficientContinuation<A: ExactScalarAdmission & ~Copyable>(
        using a: inout A) throws -> CoefficientContinuation {
        try a.checkpoint()
        let physical = try source.physical.makeSineCosineEnclosure(using: &a)
        try a.retainStorage(bytes: MemoryLayout<CoefficientContinuation>.stride)
        return CoefficientContinuation(binding: binding, sphere: sphere,
            physical: physical, proofDepth: try a.depth)
    }

    /// Scheduling only: preserve the original width-to-trig refinement policy.
    func refinementDepth<A: ExactScalarAdmission & ~Copyable>(
        overClosedRawU interval: ScalarInterval, minimum: Int,
        continuation: borrowing CoefficientContinuation, using a: inout A) throws -> Int {
        try a.checkpoint(); try a.consumeWork(1)
        guard binding.owner === continuation.binding.owner, sphere == continuation.sphere else {
            throw OriginalSourceIssuanceFailure.foreignBinding
        }
        guard minimum > 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
        try a.admitDepth(value: continuation.proofDepth.value, coefficient: continuation.proofDepth.coefficient)
        guard let cached = continuation.coefficients else { try a.checkpoint(); return minimum }
        let lower = try q.binary64(exactly: interval.lower, using: &a)
        let upper = try q.binary64(exactly: interval.upper, using: &a)
        let normalizedWidth = try q.dividing(q.subtracting(upper, lower, using: &a), period, using: &a)
        let base = max(minimum, cached.depth)
        let result: Int
        if try q.compare(normalizedWidth, cached.largestTrigWidth, using: &a) != .greater {
            let next = base.addingReportingOverflow(1)
            guard !next.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            result = next.partialValue
        } else { result = base }
        try a.checkpoint(); return result
    }

    func decision<A: ExactScalarAdmission & ~Copyable>(refinementDepth: Int,
        continuation: inout CoefficientContinuation, using a: inout A) throws -> Decision {
        try a.checkpoint(); try a.consumeWork(1)
        guard binding.owner === continuation.binding.owner, sphere == continuation.sphere else {
            throw OriginalSourceIssuanceFailure.foreignBinding
        }
        guard refinementDepth > 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
        try a.admitDepth(value: continuation.proofDepth.value, coefficient: continuation.proofDepth.coefficient)
        try a.visitCell(axis: .value, depth: 0)
        let coefficients: Coefficients
        if let cached = continuation.coefficients, cached.depth >= refinementDepth {
            coefficients = cached
        } else {
            coefficients = try makeCoefficients(depth: refinementDepth,
                physical: &continuation.physical, using: &a)
            continuation.coefficients = coefficients
            continuation.proofDepth = try a.depth
        }
        let result = try CellProof.check(certifier: self, coefficients: coefficients, using: &a)
        try a.checkpoint(); return result
    }

    private func makeCoefficients<A:ExactScalarAdmission & ~Copyable>(depth:Int,
        physical:inout OriginalPhysicalAngleEnclosure,using a:inout A) throws -> Coefficients {
        let bounds=try physical.enclosing(refinementDepth:depth,using:&a)
        let sb=bounds.sine,cb=bounds.cosine
        let s=I(lower:sb.lower,upper:sb.upper),c=I(lower:cb.lower,upper:cb.upper)
        let m=try dz.multiplying(c,q,&a),r=try dx.multiplying(s,q,&a)
        let lo=try boundary(sphereLower,depth:depth,using:&a),hi=try boundary(sphereUpper,depth:depth,using:&a)
        let vlo=try boundary(q.binary64(exactly:sphere.v.lower,using:&a),depth:depth,using:&a)
        let vhi=try boundary(q.binary64(exactly:sphere.v.upper,using:&a),depth:depth,using:&a)
        let vLo=try vlo.sine.multiplying(radius,q,&a),vHi=try vhi.sine.multiplying(radius,q,&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:10,of:I.self))
        var width=try q.integer(0,using:&a)
        for bound in [s,c,lo.sine,lo.cosine,hi.sine,hi.cosine,vlo.sine,vlo.cosine,vhi.sine,vhi.cosine] {
            let candidate=try q.subtracting(bound.upper,bound.lower,using:&a)
            if try q.compare(candidate,width,using:&a) == .greater { width=candidate }
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Coefficients.self))
        return Coefficients(depth:depth,sine:s,cosine:c,middle:m,radial:r,
            azimuthLower:lo,azimuthUpper:hi,latitudeLower:vLo,latitudeUpper:vHi,largestTrigWidth:width)
    }

    private func decide<A: ExactScalarAdmission & ~Copyable>(_ cell:Cell,coefficients k:Coefficients,
        using a:inout A) throws -> Outcome {
        let depth=k.depth
        let phase=try OriginalPhysicalAngleRationalEnclosures.normalizedLabelSineCosine(lower:cell.lower,upper:cell.upper,
            labelPeriod:period,refinementDepth:depth,using:&a)
        let sn=I(lower:phase.sine.lower,upper:phase.sine.upper),cs=I(lower:phase.cosine.lower,upper:phase.cosine.upper)
        let b=try k.middle.adding(k.radial.multiplying(sn,q,&a),q,&a).outwardDyadic(q,&a)
        let discriminant=try b.multiplying(b,q,&a).subtracting(constant,q,&a).outwardDyadic(q,&a)
        if try q.sign(of:discriminant.upper,using:&a) == .negative { return .wholeCellExcluded }
        if try excludesRequestedSlant(b: b, using: &a) { return .wholeCellExcluded }
        guard try q.sign(of:discriminant.lower,using:&a) == .positive else { return .unresolved(reason: .discriminant) }
        let bounds=try OriginalPhysicalAngleRationalBounds(lower:discriminant.lower,upper:discriminant.upper,using:&a)
        let radical=try OriginalPhysicalAngleRationalEnclosures.positiveSquareRoot(bounds,refinementDepth:depth,using:&a)
        let d=I(lower:radical.lower,upper:radical.upper)
        let plus=try b.adding(d,q,&a),minus=try b.subtracting(d,q,&a)
        let plusDecision = try branchDecision(slant: plus, coefficients: k,
            phaseSine: sn, phaseCosine: cs, using: &a)
        let minusDecision = try branchDecision(slant: minus, coefficients: k,
            phaseSine: sn, phaseCosine: cs, using: &a)
        switch (plusDecision, minusDecision) {
        case (.excluded, .excluded): return .wholeCellExcluded
        case (.selected, .excluded): return .selected(branch: 0)
        case (.excluded, .selected): return .selected(branch: 1)
        case (.boundaryCandidate(let reason, let height), .excluded):
            return .boundaryCandidate(branch: 0, guardReason: reason, slant: plus, height: height)
        case (.excluded, .boundaryCandidate(let reason, let height)):
            return .boundaryCandidate(branch: 1, guardReason: reason, slant: minus, height: height)
        case (.unresolved(let reason), .excluded), (.excluded, .unresolved(let reason)):
            return .unresolved(reason: reason)
        default: return .unresolved(reason: .slant)
        }
    }

    private func branchDecision<A: ExactScalarAdmission & ~Copyable>(slant: I,
        coefficients: Coefficients, phaseSine: I, phaseCosine: I,
        using a: inout A) throws -> BranchDecision {
        if try outside(slant, cone.v.lower, cone.v.upper, using: &a) { return .excluded }
        let slantInside = try inside(slant, cone.v.lower, cone.v.upper, using: &a)
        switch try sphereGuards(slant: slant, coefficients: coefficients,
            phaseSine: phaseSine, phaseCosine: phaseCosine, using: &a) {
        case .wholeCellExcluded: return .excluded
        case .inside: return slantInside ? .selected : .unresolved(reason: .slant)
        case .uniqueUnresolved(let reason, let height):
            return slantInside ? .boundaryCandidate(reason: reason, height: height) : .unresolved(reason: .slant)
        case .unresolved(let reason): return .unresolved(reason: reason)
        }
    }

    /// Uses the existing monic slant quadratic; no root approximation is needed.
    private func excludesRequestedSlant<A: ExactScalarAdmission & ~Copyable>(b: I,
        using a: inout A) throws -> Bool {
        let lo = try q.binary64(exactly: cone.v.lower, using: &a)
        let hi = try q.binary64(exactly: cone.v.upper, using: &a)
        let two = try I(q.integer(2, using: &a))
        func quadratic(at endpoint: ExactRationalCoefficient, using a: inout A) throws -> I {
            let value = I(endpoint)
            return try value.multiplying(value, q, &a)
                .subtracting(two.multiplying(b, q, &a).multiplying(value, q, &a), q, &a)
                .adding(constant, q, &a)
        }
        let atLower = try quadratic(at: lo, using: &a)
        let atUpper = try quadratic(at: hi, using: &a)
        if try q.compare(hi, b.lower, using: &a) != .greater,
            try q.sign(of: atUpper.lower, using: &a) == .positive { return true }
        if try q.compare(lo, b.upper, using: &a) != .less,
            try q.sign(of: atLower.lower, using: &a) == .positive { return true }
        return try q.sign(of: atLower.upper, using: &a) == .negative
            && q.sign(of: atUpper.upper, using: &a) == .negative
    }

    private func sphereGuards<A:ExactScalarAdmission & ~Copyable>(slant:I,coefficients k:Coefficients,
        phaseSine:I,phaseCosine:I,using a:inout A) throws -> SphereGuardDecision {
        let radial=try slant.multiplying(k.sine,q,&a)
        let x=try dx.subtracting(radial.multiplying(phaseSine,q,&a),q,&a)
        let y=try radial.multiplying(phaseCosine,q,&a)
        let z=try slant.multiplying(k.cosine,q,&a).subtracting(dz,q,&a)
        guard try q.sign(of:x.lower,using:&a) == .positive else { return .unresolved(reason: .spherePositiveX) }
        let lo=k.azimuthLower,hi=k.azimuthUpper
        // det(d(lower),p)>=0 and det(p,d(upper))>=0 exactly select
        // the principal negative-angle wedge because relative X is positive.
        let lowCross=try lo.sine.negated(q,&a).multiplying(y,q,&a).subtracting(lo.cosine.multiplying(x,q,&a),q,&a)
        let highCross=try x.multiplying(hi.cosine,q,&a).adding(y.multiplying(hi.sine,q,&a),q,&a)
        // Strict opposite guards exclude the whole branch only in the proved
        // positive-X principal wedge. Evaluate every guard before a candidate.
        let lowExcluded = try q.sign(of: lowCross.upper, using: &a) == .negative
        let highExcluded = try q.sign(of: highCross.upper, using: &a) == .negative
        let latitudeLowExcluded = try q.compare(z.upper, k.latitudeLower.lower, using: &a) == .less
        let latitudeHighExcluded = try q.compare(z.lower, k.latitudeUpper.upper, using: &a) == .greater
        if lowExcluded || highExcluded || latitudeLowExcluded || latitudeHighExcluded {
            return .wholeCellExcluded
        }
        let lowInside = try q.sign(of: lowCross.lower, using: &a) != .negative
        let highInside = try q.sign(of: highCross.lower, using: &a) != .negative
        let latitudeLowInside = try q.compare(z.lower, k.latitudeLower.upper, using: &a) != .less
        let latitudeHighInside = try q.compare(z.upper, k.latitudeUpper.lower, using: &a) != .greater
        var unresolvedCount = 0
        var reason: UnresolvedReason = .sphereAzimuthLower
        if !lowInside { unresolvedCount += 1; reason = .sphereAzimuthLower }
        if !highInside { unresolvedCount += 1; reason = .sphereAzimuthUpper }
        if !latitudeLowInside { unresolvedCount += 1; reason = .sphereLatitudeLower }
        if !latitudeHighInside { unresolvedCount += 1; reason = .sphereLatitudeUpper }
        if unresolvedCount == 0 { return .inside }
        if unresolvedCount == 1 { return .uniqueUnresolved(reason: reason, height: z) }
        return .unresolved(reason: reason)
    }
    /// One nonrecursive necessary-bound check on the original monotone latitude law.
    private func necessarySphereVBounds<A: ExactScalarAdmission & ~Copyable>(height: I,
        depth: Int, using a: inout A) throws -> ScalarInterval {
        try a.checkpoint(); try a.consumeWork(1)
        let original = sphere.v
        let midpoint = original.midpoint
        let raw = try q.binary64(exactly: midpoint, using: &a)
        let lo = try q.binary64(exactly: original.lower, using: &a)
        let hi = try q.binary64(exactly: original.upper, using: &a)
        guard try q.compare(raw, lo, using: &a) != .less,
            try q.compare(raw, hi, using: &a) != .greater else {
            throw OriginalSourceIssuanceFailure.invalidSource
        }
        guard try q.compare(raw, lo, using: &a) == .greater,
            try q.compare(raw, hi, using: &a) == .less else {
            try a.checkpoint(); return original
        }
        // Constructor admission restricts V to [-B/4, 0], where the original
        // sine law is strictly increasing. Strict opposite height alone cuts.
        let atMidpoint = try boundary(raw, depth: depth, using: &a).sine.multiplying(radius, q, &a)
        let lower: Double, upper: Double
        if try q.compare(atMidpoint.upper, height.lower, using: &a) == .less {
            lower = midpoint; upper = original.upper
        } else if try q.compare(atMidpoint.lower, height.upper, using: &a) == .greater {
            lower = original.lower; upper = midpoint
        } else { lower = original.lower; upper = original.upper }
        let result = try ScalarInterval(lower: lower, upper: upper)
        try a.checkpoint(); return result
    }

    private func boundary<A:ExactScalarAdmission & ~Copyable>(_ u:ExactRationalCoefficient,depth:Int,
        using a:inout A) throws -> (sine:I,cosine:I) {
        let result=try OriginalPhysicalAngleRationalEnclosures.normalizedLabelSineCosine(lower:u,upper:u,labelPeriod:period,
            refinementDepth:depth,using:&a)
        return (I(lower:result.sine.lower,upper:result.sine.upper),I(lower:result.cosine.lower,upper:result.cosine.upper))
    }
    private func inside<A:ExactScalarAdmission & ~Copyable>(_ value:I,_ lower:Double,_ upper:Double,using a:inout A) throws -> Bool {
        try q.compare(value.lower,q.binary64(exactly:lower,using:&a),using:&a) != .less
            && q.compare(value.upper,q.binary64(exactly:upper,using:&a),using:&a) != .greater
    }
    private func outside<A:ExactScalarAdmission & ~Copyable>(_ value:I,_ lower:Double,_ upper:Double,using a:inout A) throws -> Bool {
        try q.compare(value.upper,q.binary64(exactly:lower,using:&a),using:&a) == .less
            || q.compare(value.lower,q.binary64(exactly:upper,using:&a),using:&a) == .greater
    }
}
