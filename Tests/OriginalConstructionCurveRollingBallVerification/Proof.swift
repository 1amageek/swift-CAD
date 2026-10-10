#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
@testable import CADGeometry
import RetainedHostAdapters
@testable import CallerAdapters

@main struct ConstructionCurveRollingBallProof {
    typealias Legacy=RetainedRollingBallProof
    typealias Admission=Legacy.Admission
    typealias Family=Legacy.Family
    nonisolated static func curve(x: Double=0,y: Double=0,weighted: Bool,corrected: Bool,reverse: Bool,
        basis: OriginalEndpointCorrectionBasis = .quinticHermite,startAtEnd: Bool=false,endAtEnd: Bool=true,
        using a: inout Admission) throws -> Curve3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let native=BSplineCurve3D(degree:1,knots:[0,0,0.5,1,1],controlPoints:(corrected && reverse ? [3.0,1.5,0]:[0.0,1.5,3]).map {
                .init(x:x,y:y,z:$0) },weights:weighted ? [1,1,2]:nil)
            if !corrected {
                let third=try ExactRationalCoefficient.one.divided(by:.originalDouble(3,usage:&usage),usage:&usage)
                let twoThirds=try third.multiplied(by:.originalDouble(2,usage:&usage),usage:&usage)
                let source=OriginalCurveConstructionParameterSource(source:.bSpline(native),startParameter:0,endParameter:1,
                    law:.affine,firstFraction:reverse ? twoThirds:third,lastFraction:reverse ? third:twoThirds)
                return .originalConstructionChart(try .init(parameterSource:source,tolerance:.standard,maximumSpanCount:2,
                    maximumSubdivisionDepth:0,remainingSourceDepth:3,storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumAlgebraicDepth:0))
            }
            let boundary=try OriginalCurveRootSpan3D(source:.bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[
                .init(x:x,y:y,z:reverse ? 5:2),.init(x:x,y:y,z:reverse ? 4:7)])),start:.authored(0),end:.authored(1),
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:2,remainingSourceDepth:2,maximumAlgebraicDepth:0)
            return .originalEndpointConnector(try .init(construction:native,startBoundary:boundary,startAtEnd:startAtEnd,
                endBoundary:boundary,endAtEnd:endAtEnd,correctionBasis:basis,maximumSpanCount:2,maximumSubdivisionDepth:0,tolerance:.standard,usage:&usage))
        }.value
    }
    nonisolated static func traversalCurve(weighted: Bool,reverse: Bool,using a: inout Admission) throws -> Curve3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let native=BSplineCurve3D(degree:1,knots:[0,0,0.5,1,1],controlPoints:[0.0,1.5,3].map { .init(x:0,y:0,z:$0) },weights:weighted ? [1,1,2]:nil)
            let span=try OriginalCurveRootSpan3D(source:.bSpline(native),start:.authored(reverse ? 0.75:0.25),end:.authored(reverse ? 0.25:0.75),
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:2,remainingSourceDepth:2,maximumAlgebraicDepth:0)
            return .originalConstructionChart(try .init(traversal:span,maximumSpanCount:2,usage:&usage))
        }.value
    }
    nonisolated static func expected(_ t: OriginalExactScalar,weighted: Bool,corrected: Bool,reverse: Bool,
        field f: OriginalExactScalarDomain,using a: inout Admission) throws -> [OriginalExactScalar] {
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),two=try f.integer(2,using:&a),three=try f.integer(3,using:&a)
        let parameter=corrected ? t:try f.dividing(reverse ? f.subtracting(two,t,using:&a):f.adding(one,t,using:&a),three,using:&a)
        let half=try f.dividing(one,two,using:&a)
        let upper=try f.compare(parameter,half,using:&a) == .greater
        let g=weighted && upper ?
            try f.dividing(f.subtracting(f.multiplying(three,parameter,using:&a),one,using:&a),f.multiplying(two,parameter,using:&a),using:&a):parameter
        var z=corrected && reverse ? try f.subtracting(three,f.multiplying(three,g,using:&a),using:&a):try f.multiplying(three,g,using:&a)
        if corrected {
            let t2=try f.multiplying(t,t,using:&a),t3=try f.multiplying(t2,t,using:&a),t4=try f.multiplying(t3,t,using:&a),t5=try f.multiplying(t4,t,using:&a)
            let h=try f.adding(f.subtracting(f.multiplying(f.integer(10,using:&a),t3,using:&a),f.multiplying(f.integer(15,using:&a),t4,using:&a),using:&a),f.multiplying(f.integer(6,using:&a),t5,using:&a),using:&a)
            z=try f.adding(z,f.adding(two,f.multiplying(two,h,using:&a),using:&a),using:&a)
        }
        return [zero,z]
    }
    nonisolated static func numericExpected(_ t: Double,weighted: Bool,corrected: Bool,reverse: Bool) -> [Double] {
        let parameter=corrected ? t:(reverse ? 2-t:1+t)/3
        let g=weighted && parameter>0.5 ? (3*parameter-1)/(2*parameter):parameter
        var z=corrected && reverse ? 3-3*g:3*g
        if corrected { z += 2+2*(10*t*t*t-15*t*t*t*t+6*t*t*t*t*t) }
        return [0,z]
    }
    nonisolated static func incidents(_ n: Int,_ d: Int,reverse: Bool,mixed: Bool) -> Int {
        n==1 && d==2 ? 8:1
    }
    nonisolated static func childChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        for weighted in [false,true] { for corrected in [false,true] { for reverse in [false,true] {
            let input=try curve(weighted:weighted,corrected:corrected,reverse:reverse,using:&a)
            let family=try Legacy.child(input,field:f,using:&a)
            guard case .constructionCurve(let retained)=family.coverage else { throw ExactScalarFailure.invalidEvidence }
            try Legacy.require(family.graphs.count==2 && retained.laws.count==2)
            for (n,d) in [(0,1),(1,6),(1,3),(1,2),(2,3),(5,6),(1,1)] {
                let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)
                let target=try expected(t,weighted:weighted,corrected:corrected,reverse:reverse,field:f,using:&a)
                var count=0
                for graph in family.graphs {
                    if try graph.admits([t],limits:.init(remainingSourceDepth:6),using:&a) {
                        count+=1
                        guard case .constructionCurve(let law)=graph.evidence else { throw ExactScalarFailure.invalidEvidence }
                        try Legacy.require(retained.source.owns(law.chart) && graph.layout.auxiliaries.isEmpty)
                        let r=graph.polynomials,denominator=try r.evaluated(graph.homogeneous[3],at:[t],using:&a).value
                        for (axis,value) in [try f.integer(0,using:&a),target[0],target[1]].enumerated() {
                            try Legacy.require(f.compare(f.dividing(r.evaluated(graph.homogeneous[axis],at:[t],using:&a).value,denominator,using:&a),value,using:&a) == .equal)
                        }
                    }
                }
                try Legacy.require(count==(incidents(n,d,reverse:reverse,mixed:false)==8 ? 2:1))
                // Numerical approximation accuracy is distinct from exact graph equality.
                let actual=try input.point(at:Double(n)/Double(d),tolerance:.standard)
                let numeric=numericExpected(Double(n)/Double(d),weighted:weighted,corrected:corrected,reverse:reverse)
                try Legacy.require(abs(actual.x)<1e-12 && abs(actual.y-numeric[0])<1e-12 && abs(actual.z-numeric[1])<1e-12)
            }
        } } }
        for weighted in [false,true] { for reverse in [false,true] {
            let input=try traversalCurve(weighted:weighted,reverse:reverse,using:&a)
            let child=try Legacy.child(input,field:f,using:&a)
            try Legacy.require(child.graphs.count==2)
            for (n,d) in [(0,1),(1,3),(1,2),(2,3),(1,1)] {
                let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)
                let parameter=try f.dividing(reverse ? f.subtracting(f.integer(3,using:&a),f.multiplying(f.integer(2,using:&a),t,using:&a),using:&a):f.adding(f.integer(1,using:&a),f.multiplying(f.integer(2,using:&a),t,using:&a),using:&a),f.integer(4,using:&a),using:&a)
                let half=try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
                let upper=try f.compare(parameter,half,using:&a) == .greater
        let g=weighted && upper ? try f.dividing(f.subtracting(f.multiplying(f.integer(3,using:&a),parameter,using:&a),f.integer(1,using:&a),using:&a),f.multiplying(f.integer(2,using:&a),parameter,using:&a),using:&a):parameter
                let target=try f.multiplying(f.integer(3,using:&a),g,using:&a)
                var count=0
                for graph in child.graphs { if try graph.admits([t],limits:.init(remainingSourceDepth:6),using:&a) {
                    count+=1;let ring=graph.polynomials
                    try Legacy.require(f.compare(f.dividing(ring.evaluated(graph.homogeneous[2],at:[t],using:&a).value,ring.evaluated(graph.homogeneous[3],at:[t],using:&a).value,using:&a),target,using:&a) == .equal)
                } }
                try Legacy.require(count==(n==1 && d==2 ? 2:1))
                let numeric=reverse ? 0.75-0.5*Double(n)/Double(d):0.25+0.5*Double(n)/Double(d)
                let expected=3*(weighted && numeric>0.5 ? (3*numeric-1)/(2*numeric):numeric)
                try Legacy.require(abs(input.point(at:Double(n)/Double(d),tolerance:.standard).z-expected)<1e-12)
            }
        } }
        for basis in [OriginalEndpointCorrectionBasis.linear,.cubicHermite,.quinticHermite] {
            for startAtEnd in [false,true] { for endAtEnd in [false,true] {
                let source=try curve(weighted:true,corrected:true,reverse:false,basis:basis,startAtEnd:startAtEnd,endAtEnd:endAtEnd,using:&a)
                let child=try Legacy.child(source,field:f,using:&a)
                for (n,d) in [(0,1),(1,3),(1,2),(2,3),(1,1)] {
                    let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a),one=try f.integer(1,using:&a)
                    let t2=try f.multiplying(t,t,using:&a),t3=try f.multiplying(t2,t,using:&a)
                    let h: OriginalExactScalar
                    switch basis {
                    case .linear:h=t
                    case .cubicHermite:h=try f.subtracting(f.multiplying(f.integer(3,using:&a),t2,using:&a),f.multiplying(f.integer(2,using:&a),t3,using:&a),using:&a)
                    case .quinticHermite:
                        let t4=try f.multiplying(t3,t,using:&a),t5=try f.multiplying(t4,t,using:&a)
                        h=try f.adding(f.subtracting(f.multiplying(f.integer(10,using:&a),t3,using:&a),f.multiplying(f.integer(15,using:&a),t4,using:&a),using:&a),f.multiplying(f.integer(6,using:&a),t5,using:&a),using:&a)
                    }
                    let upper=try f.compare(t,f.dividing(one,f.integer(2,using:&a),using:&a),using:&a) == .greater
                    let g=upper ? try f.dividing(f.subtracting(f.multiplying(f.integer(3,using:&a),t,using:&a),one,using:&a),f.multiplying(f.integer(2,using:&a),t,using:&a),using:&a):t
                    let first=try f.integer(startAtEnd ? 7:2,using:&a),last=try f.integer(endAtEnd ? 4:-1,using:&a)
                    let target=try f.adding(f.multiplying(f.integer(3,using:&a),g,using:&a),f.adding(first,f.multiplying(f.subtracting(last,first,using:&a),h,using:&a),using:&a),using:&a)
                    var count=0
                    for graph in child.graphs { if try graph.admits([t],limits:.init(remainingSourceDepth:6),using:&a) {
                        count+=1;let r=graph.polynomials
                        try Legacy.require(f.compare(f.dividing(r.evaluated(graph.homogeneous[2],at:[t],using:&a).value,r.evaluated(graph.homogeneous[3],at:[t],using:&a).value,using:&a),target,using:&a) == .equal)
                    } }
                    try Legacy.require(count==(n==1 && d==2 ? 2:1))
                }
            } }
        }
        print("PASS retained construction child laws: weighted/reversed exact nonbinary affine fractions, actual directed traversal and all correction bases/endpoint selectors, all original sides and exact XYZ/T/owners")
    }
    nonisolated static func sourceChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        let input=try curve(weighted:true,corrected:false,reverse:false,using:&a)
        let family=try Legacy.child(input,field:f,using:&a)
        guard case .constructionCurve(let retained)=family.coverage,
            case .originalConstructionChart(let chart)=retained.source.original.original,
            case .parameterLaw(let law)=chart.chart,case .bSpline(let native)=law.source else { throw ExactScalarFailure.invalidEvidence }
        var copied=native.controlPoints;copied[0]=copied[1]
        try Legacy.require(copied != native.controlPoints && retained.source.original.original == input)
        let provider=CallerAdapters.OriginalRetainedConstructionCurveSnapshotProvider(field:f,tolerance:.standard)
        let wrong=Curve3D.bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:0,y:0,z:1)]))
        do { _=try provider.snapshot(wrong,limits:.init(remainingSourceDepth:6),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.admissionRejected(GeometryConversionError.invalidInput(_))) {}
        do { _=try provider.snapshot(input,limits:.init(remainingSourceDepth:2),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.admissionRejected(GeometryConversionError.resourceLimitExceeded(_))) {}
        do {
            _=try CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer().prepare(source:family.source,field:f,
                maximumCharts:1,limits:.init(remainingSourceDepth:6),using:&a);throw ExactScalarFailure.invalidEvidence
        } catch RetainedHostAdapters.OriginalSourceIssuanceFailure.chartLimit {}
        var changed=ModelingTolerance.standard;changed.distance *= 2
        do {
            _=try CallerAdapters.OriginalRetainedConstructionCurveSnapshotProvider(field:f,tolerance:changed)
                .snapshot(input,limits:.init(remainingSourceDepth:6),using:&a);throw ExactScalarFailure.invalidEvidence
        } catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.admissionRejected(GeometryConversionError.invalidInput(_))) {}
        let root=try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let p=try ExactBivariatePolynomial.monomial(u:2,v:0,coefficient:.one,usage:&usage)
                .subtracting(.constant(.originalDouble(2,usage:&usage),usage:&usage),usage:&usage)
            let roots=try ExactUnivariateRootIsolator().isolate(p,lower:.one,upper:.originalDouble(2,usage:&usage),maximumDepth:32,usage:&usage)
            try Legacy.require(roots.count==1)
            return try ExactAlgebraicRealRoot(polynomial:p,isolation:roots[0],usage:&usage)
        }.value
        let alien=try OriginalExactScalarDomain(root:root,axis:.value,maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let value=try alien.generator(using:&a)
        do { _=try family.graphs[0].admits([value],limits:.init(remainingSourceDepth:6),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
        do {
        let discontinuous=try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let native=BSplineCurve3D(degree:1,knots:[0,0,0.5,0.5,1,1],controlPoints:[0.0,1,2,3].map { .init(x:0,y:0,z:$0) })
            let law=OriginalCurveConstructionParameterSource(source:.bSpline(native),startParameter:0,endParameter:1,
                law:.affine,firstFraction:.zero,lastFraction:.one)
            return Curve3D.originalConstructionChart(try .init(parameterSource:law,tolerance:.standard,maximumSpanCount:2,
                maximumSubdivisionDepth:0,remainingSourceDepth:3,storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumAlgebraicDepth:0))
        }.value
        do { _=try provider.snapshot(discontinuous,limits:.init(remainingSourceDepth:6),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.admissionRejected(let error)) {
            guard let failure=error as? KernelError,failure.code == .unsupportedCapability else { throw error }
        }
        } catch ExactScalarFailure.admissionRejected(GeometryError.invalidDistance(let multiplicity)) { try Legacy.require(multiplicity==2) }
        print("PASS retained construction source authority: foreign carrier/field, tolerance/depth/chart limits and upstream invalid-knot refusal and detached source COW")
    }
    nonisolated static func family(weighted: Bool,corrected: Bool,reverse: Bool,mixed: Bool=false,
        field f: OriginalExactScalarDomain,using a: inout Admission) throws -> Family {
        let center=try curve(weighted:weighted,corrected:corrected,reverse:reverse,using:&a)
        let first: Curve3D,second: Curve3D
        if mixed {
            let values=reverse ? [2.0,1.5,1]:[1.0,1.5,2]
            first = .bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:values.map { .init(x:3,y:4,z:$0) }))
            second=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                let native=Curve3D.bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:values.map { .init(x:3,y:-4,z:$0) }))
                let span=try OriginalCurveRootSpan3D(source:native,start:.authored(0),end:.authored(1),
                    maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                    storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:2,remainingSourceDepth:2,maximumAlgebraicDepth:0)
                return Curve3D.originalPlaneDerivative(try .init(source:span,startConstraints:[],endConstraints:[],
                    tolerance:.standard,usage:&usage,remainingSourceDepth:3))
            }.value
        } else {
            first=try curve(x:3,y:4,weighted:weighted,corrected:corrected,reverse:reverse,using:&a)
            second=try curve(x:3,y:-4,weighted:weighted,corrected:corrected,reverse:reverse,using:&a)
        }
        let original=CallerAdapters.RollingBallBlendSurface3D(centerSpine:center,firstContact:first,secondContact:second,radius:5,tolerance:.standard)
        let l=try RetainedHostAdapters.OriginalSourceIssuanceLimits(remainingSourceDepth:7)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:CallerAdapters.OriginalGraphRollingBallSnapshotProvider(field:f)).bind(original,limits:l,using:&a)
        let p=CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer(),cl=try RetainedHostAdapters.OriginalSourceIssuanceLimits(remainingSourceDepth:6)
        let c=try p.prepare(source:source.original.originalCenter,field:f,maximumCharts:8,limits:cl,using:&a)
        let x=try p.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:8,limits:cl,using:&a)
        let y=try p.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:8,limits:cl,using:&a)
        return try RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
            .prepare(source:source,center:c,first:x,second:y,maximumCharts:64,limits:l,using:&a)
    }
    nonisolated static func tuple(t: OriginalExactScalar,mixed: Bool,reverse: Bool,field f: OriginalExactScalarDomain,
        using a: inout Admission) throws -> [OriginalExactScalar] {
        let one=try f.integer(1,using:&a),five=try f.integer(5,using:&a)
        return [t,try f.dividing(one,f.integer(2,using:&a),using:&a),five,five,try f.dividing(f.integer(3,using:&a),five,using:&a)]
    }
    nonisolated static func check(_ family: Family,weighted: Bool,corrected: Bool,reverse: Bool,mixed: Bool,
        using a: inout Admission) throws {
        let f=family.field,l=try RetainedHostAdapters.OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:7),maximumTransportDepth:16,maximumCharts:64,maximumFamilies:8,maximumIdentityProofs:8)
        try Legacy.require(family.graphs.count==8)
        let issuer=RetainedHostAdapters.DefaultOriginalRollingBallGraphDomainIssuer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
        let frame=try issuer.frame(family:family,limits:l,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let z=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        for (n,d) in [(0,1),(1,6),(1,3),(1,2),(2,3),(5,6),(1,1)] {
            let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a),q=try tuple(t:t,mixed:mixed,reverse:reverse,field:f,using:&a)
            let found=try full.liftedPositionIncidents(at:q,limits:l,using:&a),target=try expected(t,weighted:weighted,corrected:corrected,reverse:reverse,field:f,using:&a)
            try Legacy.require(found.count==incidents(n,d,reverse:reverse,mixed:mixed))
            for member in found {
                let g=member.graph,r=g.polynomials,denominator=try r.evaluated(g.homogeneous[3],at:q,using:&a).value
                for (axis,value) in [try f.integer(5,using:&a),target[0],target[1]].enumerated() {
                    try Legacy.require(f.compare(f.dividing(r.evaluated(g.homogeneous[axis],at:q,using:&a).value,denominator,using:&a),value,using:&a) == .equal)
                }
            }
            let actual=try family.source.original.original.point(u:Double(n)/Double(d),v:0.5)
            let numeric=numericExpected(Double(n)/Double(d),weighted:weighted,corrected:corrected,reverse:reverse)
            try Legacy.require(abs(actual.x-5)<1e-12 && abs(actual.y-numeric[0])<1e-12 && abs(actual.z-numeric[1])<1e-12)
        }
        let q=try tuple(t:half,mixed:mixed,reverse:reverse,field:f,using:&a),third=try f.dividing(one,f.integer(3,using:&a),using:&a)
        func interval(_ lo: OriginalExactScalar,_ hi: OriginalExactScalar,closed: Bool=true) throws -> RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar> {
            try .checked(field:f,lower:.finite(lo),upper:.finite(hi),includesLower:closed,includesUpper:closed,depth:.init(value:32,coefficient:32),using:&a)
        }
        func selected(_ ranges: [[RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar>]]) throws -> RetainedHostAdapters.OriginalRollingBallGraphDomainCover<Legacy.Source,Legacy.Evidence,Legacy.Coverage> {
            try issuer.issue(request:frame.selection(intervals:ranges,limits:l,using:&a),family:family,limits:l,using:&a)
        }
        let strict=try selected([[interval(third,f.subtracting(one,third,using:&a),closed:false)],[interval(z,one)]])
        try Legacy.require(strict.liftedPositionIncidents(at:tuple(t:third,mixed:mixed,reverse:reverse,field:f,using:&a),limits:l,using:&a).isEmpty)
        let singleton=try selected([[interval(half,half)],[interval(half,half)]])
        try Legacy.require(singleton.liftedPositionIncidents(at:q,limits:l,using:&a).count==8)
        let disconnected=try selected([[interval(z,third),interval(f.subtracting(one,third,using:&a),one)],[interval(z,one)]])
        try Legacy.require(disconnected.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        let empty=try selected([[],[]]);try Legacy.require(empty.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        var wrong=q;wrong[wrong.count-3]=try f.integer(-5,using:&a)
        try Legacy.require(full.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        var cost=try Admission();_=try full.liftedPositionIncidents(at:q,limits:l,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try full.liftedPositionIncidents(at:q,limits:l,using:&exact)
        for (work,storage,cancel) in [(cost.ledger.work-1,400_000_000,nil),(100_000_000,cost.ledger.storageBytes-1,nil),(100_000_000,400_000_000,1),(100_000_000,400_000_000,cost.calls)] {
            var failed=try Admission(work:work,storage:storage,cancelAt:cancel)
            do { _=try full.liftedPositionIncidents(at:q,limits:l,using:&failed);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.cancelled) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.cancelled)) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.cancelled))) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.resourceLimit(_))) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.resourceLimit(_)))) {}
        }
    }
    static func main() {
        do { try run() }
        catch { print("FAIL retained construction curve rolling-ball uncaught failure"); exit(1) }
    }
    nonisolated static func run() throws {
        try Legacy.run()
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        try childChecks(field:f,using:&a)
        try sourceChecks(field:f,using:&a)
        try DerivativeCurveRollingBallProof.childChecks(field:f,using:&a)
        try GuideCurveRollingBallProof.childChecks(field:f,using:&a)
        var held: Family?
        for (weighted,corrected,reverse,mixed) in [(true,true,false,false),(true,true,true,false),(true,false,false,false),(true,false,true,false),(false,false,true,true)] {
            var preparation=try Admission(work:300_000_000,storage:1_073_741_824)
            let prepared=try family(weighted:weighted,corrected:corrected,reverse:reverse,mixed:mixed,field:f,using:&preparation)
            var query=try Admission(work:300_000_000,storage:1_073_741_824)
            try check(prepared,weighted:weighted,corrected:corrected,reverse:reverse,mixed:mixed,using:&query);held=prepared
            try prepared.admitProof(limits:.init(remainingSourceDepth:prepared.source.sourceDepth),using:&query)
            do { try prepared.admitProof(limits:.init(remainingSourceDepth:prepared.source.sourceDepth-1),using:&query);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalSourceIssuanceFailure.sourceDepthLimit {}
        }
        print("PASS retained construction rolling-ball and mixed product: eight complete direct or mixed chart products and all knot sides, exact XYZ/T, selections/guards and query budgets")
        var cost=try Admission();_=try family(weighted:false,corrected:false,reverse:false,field:f,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try family(weighted:false,corrected:false,reverse:false,field:f,using:&exact)
        var short=try Admission(work:cost.ledger.work-1);try Legacy.scalarFailure { _=try family(weighted:false,corrected:false,reverse:false,field:f,using:&short) }
        var bytes=try Admission(storage:cost.ledger.storageBytes-1);try Legacy.scalarFailure { _=try family(weighted:false,corrected:false,reverse:false,field:f,using:&bytes) }
        for call in [1,cost.calls] {
            var failed=try Admission(cancelAt:call);try Legacy.scalarFailure { _=try family(weighted:false,corrected:false,reverse:false,field:f,using:&failed) }
        }
        var cancelled=try Admission();cancelled.ledger.cancel();try Legacy.scalarFailure { _=try family(weighted:false,corrected:false,reverse:false,field:f,using:&cancelled) }
        guard let held else { throw ExactScalarFailure.invalidEvidence }
        let wrong=try family(weighted:false,corrected:false,reverse:false,field:f,using:&a)
        do {
            _=try RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
                .prepare(source:held.source,center:wrong.center,first:held.first,second:held.second,maximumCharts:64,limits:.init(remainingSourceDepth:7),using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch RetainedHostAdapters.OriginalSourceIssuanceFailure.foreignBinding {}
        let q=try tuple(t:f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),mixed:true,reverse:true,field:f,using:&a)
        var incidents=0
        for graph in held.graphs { if try graph.admits(q,limits:.init(remainingSourceDepth:7),using:&a) { incidents+=1 } }
        try Legacy.require(incidents==8)
        print("PASS retained construction resources/cancel/lifetime: exact preparation ceilings, one-less, depth, entry/final callback, foreign binding and detached owners")
    }
}
