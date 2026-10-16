import CADCore

/// Reuses source-owned coefficient bounds and original primitive coordinate laws.
public struct OriginalCommonApexConeSnapshotProvider: OriginalSourceSnapshotting {
    public let reference: OriginalPhysicalAngleScalarDomain
    public let parameterized: OriginalPhysicalAngleScalarDomain
    public let maximumExtensionLevel: Int
    public let tolerance: ModelingTolerance
    public init(reference: OriginalPhysicalAngleScalarDomain, parameterized: OriginalPhysicalAngleScalarDomain,
        maximumExtensionLevel: Int, tolerance: ModelingTolerance) {
        self.reference = reference; self.parameterized = parameterized
        self.maximumExtensionLevel = maximumExtensionLevel; self.tolerance = tolerance
    }
    public static func pair(_ input: OriginalCommonApexConeInput) -> (reference: Surface3D, parameterized: Surface3D, referenceFirst: Bool)? {
        guard case .analytic(.cone(let firstApex, let firstAxis, let firstAngle))=input.first,
            case .analytic(.cone(let secondApex, let secondAxis, let secondAngle))=input.second,
            firstApex==secondApex, firstAngle>0,firstAngle<=0.5,secondAngle>0,secondAngle<=0.5,
            let firstRank=cardinal(firstAxis),let secondRank=cardinal(secondAxis),
            abs(firstRank) != abs(secondRank) || firstAngle != secondAngle else { return nil }
        let firstReference = abs(firstRank)>abs(secondRank) ||
            (abs(firstRank)==abs(secondRank) && firstAngle>secondAngle)
        return firstReference ? (input.first,input.second,true) : (input.second,input.first,false)
    }
    private static func cardinal(_ axis: Vector3D) -> Int? {
        if axis == .unitX { return 1 };if axis == .unitY { return 2 };if axis == .unitZ { return 3 }
        if axis == .init(x:-1,y:0,z:0) { return -1 }
        if axis == .init(x:0,y:-1,z:0) { return -2 }
        if axis == .init(x:0,y:0,z:-1) { return -3 }
        return nil
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalCommonApexConeInput,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCommonApexConeSnapshot> {
        let input = copy input
        do {
            return try a.withProofScope { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard limits.remainingSourceDepth >= 1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard let pair = Self.pair(input), case .analytic(.cone(let apex, let referenceAxis, let alpha)) = pair.reference,
                    case .analytic(.cone(_, let parameterizedAxis, let beta)) = pair.parameterized else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                guard reference.originalRadians == alpha, parameterized.originalRadians == beta else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let sa = try reference.sine(using: &a), ca = try reference.cosine(using: &a)
                let sb = try parameterized.sine(using: &a), cb = try parameterized.cosine(using: &a)
                // On(0,1/2], independent physical Taylor receipts certify this bound.
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:(OriginalPhysicalAngleScalarDomain,OriginalPhysicalAngleValue).self))
                for (field,cosine) in [(reference,ca),(parameterized,cb)] {
                    let lower=try field.dividing(field.integer(7,using:&a),field.integer(8,using:&a),using:&a)
                    guard try field.compare(cosine,lower,using:&a) == .greater else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                }
                let kind: OriginalCommonApexConeSnapshot.Exclusion
                guard let ar=Self.cardinal(referenceAxis),let br=Self.cardinal(parameterizedAxis) else { throw OriginalSourceIssuanceFailure.invalidSource }
                if abs(ar) != abs(br) { kind = .orthogonalDirections }
                else {
                    // Strict cosine monotonicity forbids any common nonzero direction.
                    guard alpha != beta else { throw OriginalSourceIssuanceFailure.invalidSource }
                    kind = .distinctPhysicalAngles
                }
                typealias Field = OriginalCommonApexConeSnapshot.Field
                let f = Field()
                let primitive = DefaultOriginalSourceBindingIssuer(provider: OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance: tolerance))
                let first = try primitive.bind(input.first, limits: .init(remainingSourceDepth: 0), using: &a)
                let second = try primitive.bind(input.second, limits: .init(remainingSourceDepth: 0), using: &a)
                let issuer = DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot, Field>()
                let firstLaw = try issuer.issue(source: first, field: f, limits: limits, using: &a)
                let secondLaw = try issuer.issue(source: second, field: f, limits: limits, using: &a)
                let period = try f.binary64(exactly: 2 * Double.pi, using: &a)
                let position=(x:try f.binary64(exactly:apex.x,using:&a),y:try f.binary64(exactly:apex.y,using:&a),z:try f.binary64(exactly:apex.z,using:&a))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCommonApexConeSnapshot.self))
                let result = OriginalCommonApexConeSnapshot(original: input, firstLaw: firstLaw, secondLaw: secondLaw,
                    referenceIsFirst: pair.referenceFirst, field: f, referenceField: reference, parameterizedField: parameterized,
                    referenceSine: sa, referenceCosine: ca, parameterizedSine: sb, parameterizedCosine: cb,
                    labelPeriod: period, position:position, exclusion:kind, proofDepth: try a.depth)
                try a.checkpoint(); return .init(original: result, sourceDepth: 1)
            }
        } catch { throw .init(preserving: error) }
    }
}
