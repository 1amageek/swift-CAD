import CADCore

/// Complete original finite arc selected by the caller's raw UV boxes.
public struct OriginalBoundedSphereConeSurfaceFiniteArcReceipt: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    public let source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>
    public let firstBox: SurfaceParameterBox
    public let secondBox: SurfaceParameterBox
    public let coneU: ClosedRange<Double>
    public let coneCycle: ExactRationalCoefficient
    public let sphereCycle: ExactRationalCoefficient
    public let principalConeLower: ExactRationalCoefficient
    public let principalConeUpper: ExactRationalCoefficient
    public let principalSphereLower: ExactRationalCoefficient
    public let principalSphereUpper: ExactRationalCoefficient
    public let branch: Int
    public let proofDepth: ExactScalarDepth
    public var imageDimension: Int { coneU.lowerBound == coneU.upperBound ? 0 : 1 }

    private init(source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>,
        firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox, coneU: ClosedRange<Double>,
        coneCycle:ExactRationalCoefficient,sphereCycle:ExactRationalCoefficient,
        principalConeLower:ExactRationalCoefficient,principalConeUpper:ExactRationalCoefficient,
        principalSphereLower:ExactRationalCoefficient,principalSphereUpper:ExactRationalCoefficient,
        branch: Int, proofDepth: ExactScalarDepth) {
        self.source=source; self.firstBox=firstBox; self.secondBox=secondBox
        self.coneU=coneU; self.branch=branch; self.proofDepth=proofDepth
        self.coneCycle=coneCycle; self.sphereCycle=sphereCycle
        self.principalConeLower=principalConeLower; self.principalConeUpper=principalConeUpper
        self.principalSphereLower=principalSphereLower; self.principalSphereUpper=principalSphereUpper
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary/prepared finite bounded SSI
    // consumes this strict periodically reduced chart cover. Boundary-root clipping and
    // other original charts require complete source coverage before success.
    public static func issue<A: ExactScalarAdmission & ~Copyable>(
        source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>,
        firstBox: SurfaceParameterBox?, secondBox: SurfaceParameterBox?, using a: inout A) throws -> Self {
        try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try a.checkpoint(); try a.consumeWork(1)
            guard let firstBox, let secondBox else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            let s=source.original
            let sphere=s.sphereIsFirst ? firstBox:secondBox, cone=s.sphereIsFirst ? secondBox:firstBox
            let certifier=try OriginalBoundedSphereConeFiniteArcCertifier(source:s,
                sphere:sphere,cone:cone,using:&a)
            let branch=try certifier.certify(using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Self.self))
            let result=Self(source:source,firstBox:firstBox,secondBox:secondBox,
                coneU:cone.u.lower...cone.u.upper,coneCycle:certifier.coneCycle,sphereCycle:certifier.sphereCycle,
                principalConeLower:certifier.lower,principalConeUpper:certifier.upper,
                principalSphereLower:certifier.sphereLower,principalSphereUpper:certifier.sphereUpper,
                branch:branch,proofDepth:try a.depth)
            try a.checkpoint(); return result
        }
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws {
        try a.checkpoint(); try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
        try a.checkpoint()
    }

    public func contains<A: ExactScalarAdmission & ~Copyable>(_ rawU: Field.Value, using a: inout A) throws -> Bool {
        try admitProof(using:&a)
        let f=source.original.field, u=try f.importing(rawU,using:&a)
        return try f.compare(u,f.binary64(exactly:coneU.lowerBound,using:&a),using:&a) != .less
            && f.compare(u,f.binary64(exactly:coneU.upperBound,using:&a),using:&a) != .greater
    }

    public func accepts<A:ExactScalarAdmission & ~Copyable>(coneCycle requestedCone:ExactRationalCoefficient,
        sphereCycle requestedSphere:ExactRationalCoefficient,using a:inout A) throws -> Bool {
        try admitProof(using:&a)
        guard requestedCone.canonicalDenominatorWords == [1],requestedSphere.canonicalDenominatorWords == [1] else { return false }
        let q=ExactRationalScalarDomain()
        let accepted=try q.compare(requestedCone,coneCycle,using:&a) == .equal
            && q.compare(requestedSphere,sphereCycle,using:&a) == .equal
        try a.checkpoint(); return accepted
    }

    public func position<A: ExactScalarAdmission & ~Copyable>(coneU rawU: Field.Value,
        using a: inout A) throws -> OriginalBoundedSphereConeSurfaceFiniteArcPosition {
        try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            guard try contains(rawU,using:&a) else { throw OriginalSourceIssuanceFailure.invalidSource }
            let s=source.original,f=s.field,u=try f.importing(rawU,using:&a)
            let coneOffset=try f.multiplying(OriginalSourceRationalImport.value(coneCycle,field:f,using:&a),s.labelPeriod,using:&a)
            let sphereOffset=try f.multiplying(OriginalSourceRationalImport.value(sphereCycle,field:f,using:&a),s.labelPeriod,using:&a)
            let principalU=try f.subtracting(u,coneOffset,using:&a)
            let ax=try f.binary64(exactly:s.apex.x,using:&a),ay=try f.binary64(exactly:s.apex.y,using:&a)
            let az=try f.binary64(exactly:s.apex.z,using:&a)
            let ox=try f.binary64(exactly:s.sphereCenter.x,using:&a),oy=try f.binary64(exactly:s.sphereCenter.y,using:&a)
            let oz=try f.binary64(exactly:s.sphereCenter.z,using:&a),radius=try f.binary64(exactly:s.sphereRadius,using:&a)
            let dx=try f.subtracting(ax,ox,using:&a),dz=try f.subtracting(oz,az,using:&a)
            let constant=try f.subtracting(f.adding(f.multiplying(dx,dx,using:&a),f.multiplying(dz,dz,using:&a),using:&a),
                f.multiplying(radius,radius,using:&a),using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalBoundedSphereConeSurfaceFiniteArcSlant.self))
            let root=OriginalBoundedSphereConeSurfaceFiniteArcSlant(middleOffset:try f.multiplying(dz,s.cosine,using:&a),
                sineCoefficient:try f.multiplying(dx,s.sine,using:&a),constant:constant,
                coneU:u,principalConeU:principalU,labelPeriod:s.labelPeriod,branch:branch)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalBoundedSphereConeSurfaceFiniteArcCoordinate.self))
            let x=OriginalBoundedSphereConeSurfaceFiniteArcCoordinate(axis:0,apex:ax,sourceSine:s.sine,sourceCosine:s.cosine,slant:root)
            let y=OriginalBoundedSphereConeSurfaceFiniteArcCoordinate(axis:1,apex:ay,sourceSine:s.sine,sourceCosine:s.cosine,slant:root)
            let z=OriginalBoundedSphereConeSurfaceFiniteArcCoordinate(axis:2,apex:az,sourceSine:s.sine,sourceCosine:s.cosine,slant:root)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalBoundedSphereConeSurfaceFiniteArcSphereUV.self))
            let uv=OriginalBoundedSphereConeSurfaceFiniteArcSphereUV(x:x,y:y,z:z,centerX:ox,centerY:oy,centerZ:oz,radius:radius,
                labelPeriod:s.labelPeriod,azimuthOffset:sphereOffset,sphereCycle:sphereCycle)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalBoundedSphereConeSurfaceFiniteArcPosition.self))
            let result=OriginalBoundedSphereConeSurfaceFiniteArcPosition(source:source,coneU:u,principalConeU:principalU,
                coneCycle:coneCycle,sphereCycle:sphereCycle,branch:branch,
                slant:root,x:x,y:y,z:z,sphereInverse:uv,proofDepth:try a.depth)
            try a.checkpoint(); return result
        }
    }
}
