import CADCore

/// Issues the whole original single bounded arc from actual parent coefficients.
public struct OriginalBoundedSphereConeSurfaceSnapshotProvider: OriginalSourceSnapshotting {
    public let physical: OriginalPhysicalAngleScalarDomain
    public let maximumExtensionLevel: Int
    public let tolerance: ModelingTolerance
    public init(physical: OriginalPhysicalAngleScalarDomain, maximumExtensionLevel: Int,
        tolerance: ModelingTolerance) {
        self.physical=physical;self.maximumExtensionLevel=maximumExtensionLevel;self.tolerance=tolerance
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary/prepared SSI consumes only
    // the proved aligned single-arc capability here. Other bounded topologies
    // and original frames require their own complete source-domain receipts.
    public static func pair(_ input:OriginalBoundedSphereConeSurfaceInput) -> (sphere:Surface3D,cone:Surface3D,sphereFirst:Bool)? {
        let sphere:Surface3D,cone:Surface3D,first:Bool
        if case .analytic(.sphere)=input.first,case .analytic(.cone)=input.second {
            sphere=input.first;cone=input.second;first=true
        } else if case .analytic(.sphere)=input.second,case .analytic(.cone)=input.first {
            sphere=input.second;cone=input.first;first=false
        } else { return nil }
        guard case .analytic(.sphere(let center,let radius))=sphere,radius.isFinite,radius>0,
            case .analytic(.cone(let apex,let axis,let angle))=cone,axis == .unitZ,
            apex.y==center.y,apex.x>center.x,apex.z<center.z,
            angle.isFinite,angle>0,angle<Double.pi*0.5 else { return nil }
        return(sphere,cone,first)
    }
    public static func admitsSingleArc<A:ExactScalarAdmission & ~Copyable>(_ input:OriginalBoundedSphereConeSurfaceInput,
        physical f:OriginalPhysicalAngleScalarDomain,using a:inout A) throws -> Bool {
        guard let pair=pair(input),case .analytic(.sphere(let center,let radius))=pair.sphere,
            case .analytic(.cone(let apex,_,let angle))=pair.cone else { return false }
        guard angle==f.originalRadians else { throw OriginalSourceIssuanceFailure.foreignBinding }
        let dx=try f.subtracting(f.binary64(exactly:apex.x,using:&a),f.binary64(exactly:center.x,using:&a),using:&a)
        let dz=try f.subtracting(f.binary64(exactly:center.z,using:&a),f.binary64(exactly:apex.z,using:&a),using:&a)
        let rr=try f.binary64(exactly:radius,using:&a)
        let constant=try f.subtracting(f.adding(f.multiplying(dx,dx,using:&a),f.multiplying(dz,dz,using:&a),using:&a),f.multiplying(rr,rr,using:&a),using:&a)
        let r=try f.multiplying(dx,f.sine(using:&a),using:&a),m=try f.multiplying(dz,f.cosine(using:&a),using:&a)
        let maximum=try f.adding(m,r,using:&a)
        return try f.sign(of:r,using:&a) == .positive && f.compare(m,r,using:&a) == .greater
            && f.compare(constant,f.multiplying(m,m,using:&a),using:&a) == .greater
            && f.compare(constant,f.multiplying(maximum,maximum,using:&a),using:&a) == .less
    }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OriginalBoundedSphereConeSurfaceInput,
        limits:OriginalSourceIssuanceLimits,using admission:inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalBoundedSphereConeSurfaceSnapshot> {
        let input=copy input
        do {
            return try admission.withProofScope { a in
                try a.checkpoint();try a.consumeWork(1)
                guard limits.remainingSourceDepth>=1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard let pair=Self.pair(input),case .analytic(.sphere(let center,let radius))=pair.sphere,
                    case .analytic(.cone(let apex,_,_))=pair.cone,
                    try Self.admitsSingleArc(input,physical:physical,using:&a) else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                typealias Field=OriginalBoundedSphereConeSurfaceSnapshot.Field
                let base=try Field.base(field:physical,maximumExtensionLevel:maximumExtensionLevel,using:&a)
                let dx=try base.subtracting(base.binary64(exactly:apex.x,using:&a),base.binary64(exactly:center.x,using:&a),using:&a)
                let dz=try base.subtracting(base.binary64(exactly:center.z,using:&a),base.binary64(exactly:apex.z,using:&a),using:&a)
                let rr=try base.binary64(exactly:radius,using:&a)
                let constant=try base.subtracting(base.adding(base.multiplying(dx,dx,using:&a),base.multiplying(dz,dz,using:&a),using:&a),base.multiplying(rr,rr,using:&a),using:&a)
                let sine=try base.importingBase(physical.sine(using:&a),using:&a)
                let cosine=try base.importingBase(physical.cosine(using:&a),using:&a)
                let delta=apex-center
                let candidate=(delta.dot(delta)-radius*radius).squareRoot()
                let radialField:Field,root:Field.Value
                if candidate.isFinite,candidate>0,
                    try base.compare(base.multiplying(base.binary64(exactly:candidate,using:&a),base.binary64(exactly:candidate,using:&a),using:&a),constant,using:&a) == .equal {
                    radialField=base;root=try base.binary64(exactly:candidate,using:&a)
                } else {
                    var lower=try base.integer(0,using:&a)
                    var upper=try base.adding(base.integer(1,using:&a),constant,using:&a)
                    let candidateLower=candidate.rounded(.down),candidateUpper=candidateLower+1
                    if candidateLower.isFinite,candidateUpper.isFinite,candidateUpper>candidateLower {
                        let lo=try base.binary64(exactly:candidateLower,using:&a),hi=try base.binary64(exactly:candidateUpper,using:&a)
                        if try base.sign(of:lo,using:&a) != .negative,
                            try base.compare(base.multiplying(lo,lo,using:&a),constant,using:&a) == .less,
                            try base.compare(base.multiplying(hi,hi,using:&a),constant,using:&a) == .greater {
                            lower=lo;upper=hi
                        }
                    }
                    let extended=try Self.positiveSquareRoot(constant,in:base,lower:lower,upper:upper,using:&a)
                    radialField=extended.domain;root=extended.generator
                }
                let f=radialField
                let r=try f.multiplying(f.importing(dx,using:&a),f.importing(sine,using:&a),using:&a)
                let m=try f.multiplying(f.importing(dz,using:&a),f.importing(cosine,using:&a),using:&a)
                let shift=try f.subtracting(root,m,using:&a)
                let h2=try f.subtracting(f.multiplying(r,r,using:&a),f.multiplying(shift,shift,using:&a),using:&a)
                let extended=try Self.positiveSquareRoot(h2,in:f,upper:r,using:&a),g=extended.domain
                let mBase=try base.multiplying(dz,cosine,using:&a)
                let norm=try base.subtracting(constant,base.multiplying(mBase,mBase,using:&a),using:&a)
                let inverseNorm=try base.dividing(base.integer(1,using:&a),norm,using:&a)
                let inverseShift=try f.multiplying(f.adding(root,m,using:&a),f.importing(inverseNorm,using:&a),using:&a)
                let inverse=try g.importing(inverseShift,using:&a),radial=try g.importing(r,using:&a)
                let lower=try g.multiplying(g.subtracting(radial,extended.generator,using:&a),inverse,using:&a)
                let upper=try g.multiplying(g.adding(radial,extended.generator,using:&a),inverse,using:&a)
                let baseRadial=try base.multiplying(dx,sine,using:&a)
                let inverseRadial=try base.dividing(base.integer(1,using:&a),baseRadial,using:&a)
                let endpointSine=try g.importing(f.multiplying(shift,f.importing(inverseRadial,using:&a),using:&a),using:&a)
                let endpointCosine=try g.multiplying(extended.generator,g.importing(inverseRadial,using:&a),using:&a)
                let endpointSlant=try g.importing(root,using:&a)
                let primitive=DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance:tolerance))
                let first=try primitive.bind(input.first,limits:.init(remainingSourceDepth:0),using:&a)
                let second=try primitive.bind(input.second,limits:.init(remainingSourceDepth:0),using:&a)
                let issuer=DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot,Field>()
                let firstLaw=try issuer.issue(source:first,field:base,limits:limits,using:&a)
                let secondLaw=try issuer.issue(source:second,field:base,limits:limits,using:&a)
                let period=try base.binary64(exactly:2*Double.pi,using:&a),depth=try a.depth
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalBoundedSphereConeSurfaceSnapshot.self))
                let result=OriginalBoundedSphereConeSurfaceSnapshot(original:input,firstLaw:firstLaw,secondLaw:secondLaw,
                    sphereIsFirst:pair.sphereFirst,physical:physical,field:base,criticalField:g,sine:sine,cosine:cosine,
                    lowerHalfAngle:lower,upperHalfAngle:upper,labelPeriod:period,proofDepth:depth,
                    endpointSine:endpointSine,endpointCosine:endpointCosine,endpointSlant:endpointSlant)
                try a.checkpoint();return .init(original:result,sourceDepth:1)
            }
        } catch { throw .init(preserving:error) }
    }
    private static func positiveSquareRoot<A:ExactScalarAdmission & ~Copyable>(_ radicand:OriginalBoundedSphereConeSurfaceSnapshot.Field.Value,
        in f:OriginalBoundedSphereConeSurfaceSnapshot.Field,lower:OriginalBoundedSphereConeSurfaceSnapshot.Field.Value? = nil,upper:OriginalBoundedSphereConeSurfaceSnapshot.Field.Value,using a:inout A)
        throws -> ExactAlgebraicExtension<OriginalPhysicalAngleScalarDomain> {
        let roots=try ExactRealRootDomain(field:f,using:&a),p=roots.polynomials
        let variable=try p.variable(0,using:&a)
        let law=try p.subtracting(p.multiplying(variable,variable,using:&a),p.constant(radicand,using:&a),using:&a)
        let domain=try roots.domain(lower:.finite(try lower ?? f.integer(0,using:&a)),upper:.finite(upper),includesLower:false,includesUpper:false,using:&a)
        let isolated=try roots.isolate(roots.bind(law,using:&a),in:domain,limits:.init(maximumRoots:1),using:&a)
        guard isolated.roots.count==1 else { throw OriginalSourceIssuanceFailure.invalidSource }
        return try f.adjoin(isolated.roots[0],using:&a)
    }
}
