/// Proves complete stationary/affine contacts from the original guarded offset graphs.
struct DefaultOriginalPeriodicOffsetContactResolver {
    typealias Base = OriginalExactScalarDomain
    typealias Value = OriginalExactScalar
    typealias Surface = OriginalOffsetSnapshot<BSplineSurface3D>
    typealias Relation = OriginalPeriodicOffsetGeometricRelations
    func resolve<A:ExactScalarAdmission & ~Copyable>(curve:Relation.CurveCover,
        surface:OriginalPeriodicNativeOffsetDomainCover<Surface>,maximumContacts:Int,maximumDegree:Int,
        limits:OriginalDomainIdentityLimits,using a:inout A) throws -> Relation {
        try a.checkpoint();try surface.space.family.admitProof(limits:limits.source,using:&a)
        guard surface.templateCount<=limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        let f=surface.space.family.field,zero=try f.integer(0,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:surface.templateCount,of:Relation.Graph.self))
        var graphs:[Relation.Graph]=[];graphs.reserveCapacity(surface.templateCount)
        for ordinal in 0..<surface.templateCount {
            let law=surface.space.family.laws[surface.space.lawOrdinals[ordinal]]
            let graph=try DefaultOriginalOffsetGraphIssuer().issue(law,limits:limits.source,using:&a)
            for slot in 0..<6 {
                let p = slot<4 ? graph.homogeneous[slot]:slot==4 ? graph.evidence.normalSquared:graph.evidence.positiveRootEquation
                for axis in 0..<3 {
                    guard try (graph.polynomials.degree(of:p,in:axis,using:&a) ?? 0)<=maximumDegree else { throw ExactScalarFailure.resourceLimit(.work) }
                }
            }
            graphs.append(graph)
        }
        var contacts:[OriginalPeriodicOffsetContactTemplate]=[]
        for chart in curve.charts {
            let law=curve.laws[chart.lawIndex],r=law.polynomials
            try law.admitProof(using:&a)
            guard let denominator=try constant(law.denominator,field:f,using:&a),
                try f.sign(of:denominator,using:&a) != .zero else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Value.self))
            var point:[Value]=[];point.reserveCapacity(3)
            for p in law.homogeneous.prefix(3) {
                let divided=try r.divided(p,by:law.denominator,using:&a)
                guard try r.isZero(divided.remainder,using:&a),let value=try constant(divided.quotient,field:f,using:&a) else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                point.append(value)
            }
            for (ordinal,graph) in graphs.enumerated() {
                try a.consumeWork(1)
                if let square=try constant(graph.evidence.normalSquared,field:f,using:&a),
                    try f.sign(of:square,using:&a) != .positive { continue }
                let ring=graph.polynomials
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:9,of:Value.self))
                var coefficients:[[Value]]=[];coefficients.reserveCapacity(3)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:[Value].self))
                for axis in 0..<3 {
                    let divided=try ring.divided(graph.homogeneous[axis],by:graph.homogeneous[3],using:&a)
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary periodic offset CS
                    // consumes stationary curves and guarded affine UV position quotients.
                    // General offset graph families need complete symbolic relation intake.
                    guard try ring.isZero(divided.remainder,using:&a) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                    var row=[zero,zero,try f.negated(point[axis],using:&a)]
                    for term in divided.quotient.terms {
                        try a.consumeWork(1)
                        guard term.powers[2]==0,term.powers[0]+term.powers[1]<=1 else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                        let slot=term.powers[0]==1 ? 0:term.powers[1]==1 ? 1:2
                        row[slot]=try f.adding(row[slot],term.coefficient,using:&a)
                    }
                    coefficients.append(row)
                }
                var uv:[Value]?
                for i in 0..<2 {
                    for j in (i+1)..<3 {
                        let x=coefficients[i],y=coefficients[j]
                        let determinant=try f.subtracting(f.multiplying(x[0],y[1],using:&a),f.multiplying(x[1],y[0],using:&a),using:&a)
                        if try f.sign(of:determinant,using:&a) != .zero {
                            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Value.self))
                            uv=[try f.dividing(f.subtracting(f.multiplying(x[1],y[2],using:&a),f.multiplying(x[2],y[1],using:&a),using:&a),determinant,using:&a),
                                try f.dividing(f.subtracting(f.multiplying(x[2],y[0],using:&a),f.multiplying(x[0],y[2],using:&a),using:&a),determinant,using:&a)]
                            break
                        }
                    }
                    if uv != nil { break }
                }
                guard let uv else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                var agrees=true
                for row in coefficients {
                    let value=try f.adding(f.adding(f.multiplying(row[0],uv[0],using:&a),f.multiplying(row[1],uv[1],using:&a),using:&a),row[2],using:&a)
                    if try f.sign(of:value,using:&a) != .zero { agrees=false }
                }
                guard agrees,try graph.evidence.admitsPosition(at:uv,limits:limits.source,using:&a) else { continue }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Value.self))
                let coordinates=uv+[zero]
                let square=try ring.evaluated(graph.evidence.normalSquared,at:coordinates,using:&a).value
                guard let root=try f.exactRationalSquareRoot(of:square,using:&a),try f.sign(of:root,using:&a) == .positive else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Value.self))
                let tuple=uv+[root]
                for condition in graph.conditions {
                    let sign=try f.sign(of:ring.evaluated(condition.polynomial,at:tuple,using:&a).value,using:&a)
                    guard condition.accepts(sign) else { throw OriginalDomainIdentityFailure.invalidDomain }
                }
                let cycles=try cycleDomains(uv:uv,surface:surface,limits:limits,using:&a)
                var dimension=0
                for interval in chart.selectedLocal.axes[0].intervals {
                    if case .finite(let lo)=interval.lower,case .finite(let hi)=interval.upper,
                        try f.compare(lo,hi,using:&a) == .less { dimension=1 }
                }
                guard contacts.count<maximumContacts else { throw OriginalDomainIdentityFailure.chartLimit }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPeriodicOffsetContactTemplate.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Value.self))
                let periods=(0..<2).map { axis in surface.space.family.child.periods.first(where:{$0.axis==axis})?.period ?? zero }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:(Relation.CurveCover,OriginalPeriodicNativeOffsetDomainCover<Surface>,[Relation.Graph]).self))
                let owner:any Sendable=(curve,surface,graphs)
                let proofDepth=try ExactScalarDepth(value:max(graph.proofDepth.value,uv[0].depth.value,uv[1].depth.value,root.depth.value),
                    coefficient:max(graph.proofDepth.coefficient,uv[0].depth.coefficient,uv[1].depth.coefficient,root.depth.coefficient))
                contacts.append(.init(field:f,curveTemplate:chart.lawIndex,surfaceTemplate:ordinal,curveDomain:chart.selectedLocal.axes[0],
                    fundamentalUV:uv,normalLength:root,position:point,cycleDomains:cycles,periods:periods,parameterDimension:dimension,
                    sourceDepth:max(surface.source.sourceDepth,law.source.sourceDepth),chartCount:surface.templateCount,
                    integerRank:surface.integerFamilyRank,proofDepth:proofDepth,owner:owner))
            }
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Relation.self))
        let result=Relation(originalGraphs:graphs,curveCover:curve,surfaceCover:surface,periodicOffsetContacts:contacts)
        try a.checkpoint();return result
    }
    private func constant<A:ExactScalarAdmission & ~Copyable>(_ p:ExactPolynomial<Base>,field:Base,
        using a:inout A) throws -> Value? {
        try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
        if p.terms.isEmpty { return try field.integer(0,using:&a) }
        guard p.terms.count==1 else { return nil }
        for power in p.terms[0].powers { try a.consumeWork(1);if power != 0 { return nil } }
        return p.terms[0].coefficient
    }
    private func cycleDomains<A:ExactScalarAdmission & ~Copyable>(uv:[Value],
        surface:OriginalPeriodicNativeOffsetDomainCover<Surface>,limits:OriginalDomainIdentityLimits,using a:inout A)
        throws -> [ExactParameterSet<ExactRationalScalarDomain>] {
        let f=surface.space.family.field,q=ExactRationalScalarDomain(),one=try q.integer(1,using:&a),zero=try q.integer(0,using:&a)
        let integers=try ExactParameterDomain(field:q,depth:.init(value:0,coefficient:0),using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactParameterSet<ExactRationalScalarDomain>.self))
        var result:[ExactParameterSet<ExactRationalScalarDomain>]=[];result.reserveCapacity(2)
        for axis in 0..<2 {
            let selected=surface.effectiveEnclosure.axes[axis]
            if let period=surface.space.family.child.periods.first(where:{$0.axis==axis}) {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:selected.intervalCount,of:ExactParameterInterval<ExactRationalCoefficient>.self))
                var ranges:[ExactParameterInterval<ExactRationalCoefficient>]=[];ranges.reserveCapacity(selected.intervalCount)
                for interval in selected.intervals {
                    var lower:ExactParameterBound<ExactRationalCoefficient> = .negativeInfinity
                    var upper:ExactParameterBound<ExactRationalCoefficient> = .positiveInfinity
                    if case .finite(let value)=interval.lower {
                        let fraction=try f.dividing(f.subtracting(value,uv[axis],using:&a),period.period,using:&a)
                        let floor=try OriginalParameterCycle.floor(fraction,field:f,using:&a)
                        let equal=try f.compare(fraction,floor.scalar(in:f,using:&a),using:&a) == .equal
                        lower = .finite(try equal && interval.includesLower ? floor.original:q.adding(floor.original,one,using:&a))
                    }
                    if case .finite(let value)=interval.upper {
                        let fraction=try f.dividing(f.subtracting(value,uv[axis],using:&a),period.period,using:&a)
                        let floor=try OriginalParameterCycle.floor(fraction,field:f,using:&a)
                        let equal=try f.compare(fraction,floor.scalar(in:f,using:&a),using:&a) == .equal
                        upper = .finite(try equal && !interval.includesUpper ? q.subtracting(floor.original,one,using:&a):floor.original)
                    }
                    if case .finite(let lo)=lower,case .finite(let hi)=upper,try q.compare(lo,hi,using:&a) == .greater { continue }
                    ranges.append(try integers.interval(lower:lower,upper:upper,using:&a))
                }
                result.append(try integers.set(intervals:ranges,using:&a))
            } else {
                let domain=try ExactParameterDomain(retaining:selected,using:&a)
                if try domain.contains(uv[axis],in:selected,using:&a) {
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<ExactRationalCoefficient>.self))
                    result.append(try integers.set(intervals:[integers.interval(lower:.finite(zero),upper:.finite(zero),using:&a)],using:&a))
                } else { result.append(try integers.empty(using:&a)) }
            }
        }
        return result
    }
}
