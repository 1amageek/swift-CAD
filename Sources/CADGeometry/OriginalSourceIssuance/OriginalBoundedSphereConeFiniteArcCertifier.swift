import CADCore

/// Rational whole-cell proof for the strict original principal-chart capability.
struct OriginalBoundedSphereConeFiniteArcCertifier {
    typealias I = OriginalPhysicalAngleInterval
    let source: OriginalBoundedSphereConeSurfaceSnapshot
    let sphere: SurfaceParameterBox
    let cone: SurfaceParameterBox
    let q = ExactRationalScalarDomain()
    let period: ExactRationalCoefficient
    let lower: ExactRationalCoefficient
    let upper: ExactRationalCoefficient
    let dx: I
    let dz: I
    let radius: I
    let constant: I
    private struct Cell {
        let lower: ExactRationalCoefficient
        let upper: ExactRationalCoefficient
        let depth: Int
    }
    /// Immutable coefficients for one query-local refinement depth.
    private struct Coefficients {
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

    init<A: ExactScalarAdmission & ~Copyable>(source: OriginalBoundedSphereConeSurfaceSnapshot,
        sphere: SurfaceParameterBox,cone: SurfaceParameterBox,using a: inout A) throws {
        self.source=source; self.sphere=sphere; self.cone=cone
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:SurfaceParameterBox.self))
        for box in [sphere,cone] {
            guard box.u.lower.isFinite,box.u.upper.isFinite,box.v.lower.isFinite,box.v.upper.isFinite,
                box.u.lower<=box.u.upper,box.v.lower<=box.v.upper else { throw OriginalSourceIssuanceFailure.invalidSource }
        }
        period=try q.binary64(exactly:2*Double.pi,using:&a)
        lower=try q.binary64(exactly:cone.u.lower,using:&a); upper=try q.binary64(exactly:cone.u.upper,using:&a)
        let zero=try q.integer(0,using:&a),two=try q.integer(2,using:&a),four=try q.integer(4,using:&a)
        let half=try q.dividing(period,two,using:&a),quarter=try q.dividing(period,four,using:&a)
        guard try q.compare(lower,zero,using:&a) == .greater,
            try q.compare(upper,half,using:&a) == .less,
            try q.compare(q.binary64(exactly:cone.v.lower,using:&a),zero,using:&a) != .less,
            try q.compare(q.binary64(exactly:sphere.u.lower,using:&a),q.negated(half,using:&a),using:&a) == .greater,
            try q.compare(q.binary64(exactly:sphere.u.upper,using:&a),zero,using:&a) == .less,
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

    func certify<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws -> Int {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Cell.self))
        var pending=[Cell(lower:lower,upper:upper,depth:0)], selected:Int?
        var coefficients:Coefficients?
        while let cell=pending.popLast() {
            try a.checkpoint(); try a.visitCell(axis:.value,depth:cell.depth)
            if let current=coefficients {
                let normalizedWidth=try q.dividing(q.subtracting(cell.upper,cell.lower,using:&a),period,using:&a)
                if try q.compare(normalizedWidth,current.largestTrigWidth,using:&a) != .greater {
                    let next=current.depth.addingReportingOverflow(1)
                    guard !next.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                    coefficients=try makeCoefficients(depth:next.partialValue,using:&a)
                }
            } else { coefficients=try makeCoefficients(depth:2,using:&a) }
            guard let coefficients else { throw OriginalSourceIssuanceFailure.unresolvedAuthority }
            if let branch=try certify(cell,coefficients:coefficients,using:&a) {
                guard selected == nil || selected == branch else { throw OriginalSourceIssuanceFailure.unresolvedAuthority }
                selected=branch; continue
            }
            // A singleton has no domain subdivision; increasing coefficient
            // accuracy is the only legal refinement of its unresolved proof.
            let next=cell.depth.addingReportingOverflow(1)
            guard !next.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            let middle=try q.dividing(q.adding(cell.lower,cell.upper,using:&a),q.integer(2,using:&a),using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Cell.self))
            if try q.compare(cell.lower,cell.upper,using:&a) == .equal {
                pending.append(.init(lower:cell.lower,upper:cell.upper,depth:next.partialValue))
            } else {
                pending.append(.init(lower:middle,upper:cell.upper,depth:next.partialValue))
                pending.append(.init(lower:cell.lower,upper:middle,depth:next.partialValue))
            }
        }
        guard let selected else { throw OriginalSourceIssuanceFailure.unresolvedAuthority }
        try a.checkpoint(); return selected
    }

    private func makeCoefficients<A:ExactScalarAdmission & ~Copyable>(depth:Int,using a:inout A) throws -> Coefficients {
        let physical=source.physical
        let sb=try physical.enclosing(physical.sine(using:&a),refinementDepth:depth,using:&a)
        let cb=try physical.enclosing(physical.cosine(using:&a),refinementDepth:depth,using:&a)
        let s=I(lower:sb.lower,upper:sb.upper),c=I(lower:cb.lower,upper:cb.upper)
        let m=try dz.multiplying(c,q,&a),r=try dx.multiplying(s,q,&a)
        let lo=try boundary(sphere.u.lower,depth:depth,using:&a),hi=try boundary(sphere.u.upper,depth:depth,using:&a)
        let vlo=try boundary(sphere.v.lower,depth:depth,using:&a),vhi=try boundary(sphere.v.upper,depth:depth,using:&a)
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

    private func certify<A: ExactScalarAdmission & ~Copyable>(_ cell:Cell,coefficients k:Coefficients,
        using a:inout A) throws -> Int? {
        let depth=k.depth
        let phase=try OriginalPhysicalAngleRationalEnclosures.normalizedLabelSineCosine(lower:cell.lower,upper:cell.upper,
            labelPeriod:period,refinementDepth:depth,using:&a)
        let sn=I(lower:phase.sine.lower,upper:phase.sine.upper),cs=I(lower:phase.cosine.lower,upper:phase.cosine.upper)
        let b=try k.middle.adding(k.radial.multiplying(sn,q,&a),q,&a).outwardDyadic(q,&a)
        let discriminant=try b.multiplying(b,q,&a).subtracting(constant,q,&a).outwardDyadic(q,&a)
        guard try q.sign(of:discriminant.lower,using:&a) == .positive else { return nil }
        let bounds=try OriginalPhysicalAngleRationalBounds(lower:discriminant.lower,upper:discriminant.upper,using:&a)
        let radical=try OriginalPhysicalAngleRationalEnclosures.positiveSquareRoot(bounds,refinementDepth:depth,using:&a)
        let d=I(lower:radical.lower,upper:radical.upper)
        let plus=try b.adding(d,q,&a),minus=try b.subtracting(d,q,&a)
        if try outside(plus,cone.v.lower,cone.v.upper,using:&a),
            try outside(minus,cone.v.lower,cone.v.upper,using:&a) {
            // This capability publishes a whole selected interval. A proved
            // excluded cell requires a different complete clipping receipt.
            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
        }
        if try inside(plus,cone.v.lower,cone.v.upper,using:&a),try outside(minus,cone.v.lower,cone.v.upper,using:&a),
            try sphereGuards(slant:plus,coefficients:k,phaseSine:sn,phaseCosine:cs,using:&a) { return 0 }
        if try inside(minus,cone.v.lower,cone.v.upper,using:&a),try outside(plus,cone.v.lower,cone.v.upper,using:&a),
            try sphereGuards(slant:minus,coefficients:k,phaseSine:sn,phaseCosine:cs,using:&a) { return 1 }
        return nil
    }

    private func sphereGuards<A:ExactScalarAdmission & ~Copyable>(slant:I,coefficients k:Coefficients,
        phaseSine:I,phaseCosine:I,using a:inout A) throws -> Bool {
        let radial=try slant.multiplying(k.sine,q,&a)
        let x=try dx.subtracting(radial.multiplying(phaseSine,q,&a),q,&a)
        let y=try radial.multiplying(phaseCosine,q,&a)
        let z=try slant.multiplying(k.cosine,q,&a).subtracting(dz,q,&a)
        guard try q.sign(of:x.lower,using:&a) == .positive else { return false }
        let lo=k.azimuthLower,hi=k.azimuthUpper
        // det(d(lower),p)>=0 and det(p,d(upper))>=0 exactly select
        // the principal negative-angle wedge because relative X is positive.
        let lowCross=try lo.sine.negated(q,&a).multiplying(y,q,&a).subtracting(lo.cosine.multiplying(x,q,&a),q,&a)
        let highCross=try x.multiplying(hi.cosine,q,&a).adding(y.multiplying(hi.sine,q,&a),q,&a)
        guard try q.sign(of:lowCross.lower,using:&a) != .negative,
            try q.sign(of:highCross.lower,using:&a) != .negative else { return false }
        return try q.compare(z.lower,k.latitudeLower.upper,using:&a) != .less
            && q.compare(z.upper,k.latitudeUpper.lower,using:&a) != .greater
    }
    private func boundary<A:ExactScalarAdmission & ~Copyable>(_ value:Double,depth:Int,
        using a:inout A) throws -> (sine:I,cosine:I) {
        let u=try q.binary64(exactly:value,using:&a)
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
