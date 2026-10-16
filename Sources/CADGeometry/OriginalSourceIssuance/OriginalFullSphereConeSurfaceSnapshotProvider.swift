import CADCore

/// Reuses the original physical coefficient bounds and primitive source laws.
public struct OriginalFullSphereConeSurfaceSnapshotProvider: OriginalSourceSnapshotting {
    public let physical: OriginalPhysicalAngleScalarDomain
    public let maximumExtensionLevel: Int
    public let tolerance: ModelingTolerance
    public init(physical: OriginalPhysicalAngleScalarDomain, maximumExtensionLevel: Int,
        tolerance: ModelingTolerance) {
        self.physical = physical; self.maximumExtensionLevel = maximumExtensionLevel; self.tolerance = tolerance
    }
    public static func pair(_ input: OriginalFullSphereConeSurfaceInput) -> (sphere: Surface3D, cone: Surface3D, sphereFirst: Bool)? {
        let sphere:Surface3D,cone:Surface3D,first:Bool
        if case .analytic(.sphere)=input.first,case .analytic(.cone)=input.second {
            sphere=input.first;cone=input.second;first=true
        } else if case .analytic(.sphere)=input.second,case .analytic(.cone)=input.first {
            sphere=input.second;cone=input.first;first=false
        } else { return nil }
        guard case .analytic(.sphere(_,let radius))=sphere,radius.isFinite,radius>0,
            case .analytic(.cone(_,let axis,let angle))=cone,axis == .unitZ,
            angle.isFinite,angle>0,angle<Double.pi*0.5 else { return nil }
        return (sphere,cone,first)
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalFullSphereConeSurfaceInput,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalFullSphereConeSurfaceSnapshot> {
        let input = copy input
        do {
            return try a.withProofScope { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard limits.remainingSourceDepth >= 1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard let pair = Self.pair(input), case .analytic(.cone(_, _, let angle)) = pair.cone else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            guard physical.originalRadians == angle else { throw OriginalSourceIssuanceFailure.foreignBinding }
            let s = try physical.sine(using: &a), c = try physical.cosine(using: &a)
            guard try physical.sign(of:s,using:&a) == .positive,try physical.sign(of:c,using:&a) == .positive else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            try Self.admitFullPair(pair.sphere,pair.cone,field:physical,sine:s,cosine:c,using:&a)
            typealias Field = OriginalFullSphereConeSurfaceSnapshot.Field
            let base = try Field.base(field: physical, maximumExtensionLevel: maximumExtensionLevel, using: &a)
            let primitive = DefaultOriginalSourceBindingIssuer(provider: OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance: tolerance))
            let first = try primitive.bind(input.first, limits: .init(remainingSourceDepth: 0), using: &a)
            let second = try primitive.bind(input.second, limits: .init(remainingSourceDepth: 0), using: &a)
            let issuer = DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot, Field>()
            let firstLaw = try issuer.issue(source: first, field: base, limits: limits, using: &a)
            let secondLaw = try issuer.issue(source: second, field: base, limits: limits, using: &a)
            let sine = try base.importingBase(s, using: &a), cosine = try base.importingBase(c, using: &a)
            let period = try base.binary64(exactly: 2 * Double.pi, using: &a), depth = try a.depth
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalFullSphereConeSurfaceSnapshot.self))
            let result = OriginalFullSphereConeSurfaceSnapshot(original: input, firstLaw: firstLaw, secondLaw: secondLaw,
                sphereIsFirst: pair.sphereFirst, field: base, sine: sine, cosine: cosine,
                labelPeriod: period, proofDepth: depth)
            try a.checkpoint(); return .init(original: result, sourceDepth: 1)
            }
        } catch { throw .init(preserving: error) }
    }
    private static func admitFullPair<A:ExactScalarAdmission & ~Copyable>(_ sphere:Surface3D,_ cone:Surface3D,
        field f:OriginalPhysicalAngleScalarDomain,sine:OriginalPhysicalAngleValue,cosine:OriginalPhysicalAngleValue,
        using a:inout A) throws {
        guard case .analytic(.sphere(let center,let radius))=sphere,
            case .analytic(.cone(let apex,_,_))=cone else { throw OriginalSourceIssuanceFailure.invalidSource }
        let dx=try f.subtracting(f.binary64(exactly:apex.x,using:&a),f.binary64(exactly:center.x,using:&a),using:&a)
        let dy=try f.subtracting(f.binary64(exactly:apex.y,using:&a),f.binary64(exactly:center.y,using:&a),using:&a)
        let dz=try f.subtracting(f.binary64(exactly:apex.z,using:&a),f.binary64(exactly:center.z,using:&a),using:&a)
        let radial=try f.adding(f.multiplying(dx,dx,using:&a),f.multiplying(dy,dy,using:&a),using:&a)
        let rr=try f.binary64(exactly:radius,using:&a)
        let constant=try f.subtracting(f.adding(radial,f.multiplying(dz,dz,using:&a),using:&a),f.multiplying(rr,rr,using:&a),using:&a)
        let sign=try f.sign(of:constant,using:&a)
        if sign == .negative { return }
        // FIXME(INCOMPLETE_IMPLEMENTATION): General apex and bounded/open source pairs
        // need their own topology receipt; this full-pair issuer cannot certify them.
        guard sign == .positive else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
        let m=try f.multiplying(dz,cosine,using:&a),m2=try f.multiplying(m,m,using:&a)
        let h2=try f.multiplying(radial,f.multiplying(sine,sine,using:&a),using:&a)
        let margin=try f.subtracting(f.adding(m2,h2,using:&a),constant,using:&a)
        guard try f.compare(m2,h2,using:&a) == .greater,try f.sign(of:margin,using:&a) == .positive,
            try f.compare(f.multiplying(margin,margin,using:&a),f.multiplying(f.integer(4,using:&a),f.multiplying(m2,h2,using:&a),using:&a),using:&a) == .greater else {
            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
        }
    }

}
