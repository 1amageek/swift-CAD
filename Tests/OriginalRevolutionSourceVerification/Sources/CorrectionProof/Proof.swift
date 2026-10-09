import CADCore
@testable import CADGeometry

@main
struct OriginalBoundaryCorrectionSourceProof {
    static func require(_ value:Bool,line:Int = #line) throws {
        guard value else { print("FAILED M4 actual correction line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    static func shape<A:ExactScalarAdmission & ~Copyable>(nonzero:Bool,using a:inout A) throws -> OriginalBoundaryCorrectedSurface3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            func span(_ points:[Point3D],degree:Int=1) throws -> OriginalCurveRootSpan3D {
                let knots=Array(repeating:0.0,count:degree+1)+Array(repeating:1.0,count:degree+1)
                return try .init(source:.bSpline(.init(degree:degree,knots:knots,controlPoints:points)),start:.authored(0),end:.authored(1),
                    maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                    storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:1,remainingSourceDepth:0,maximumAlgebraicDepth:0)
            }
            let bottom=nonzero ? try span([.origin,.init(x:0.5,y:0,z:0.25),.init(x:1,y:0,z:0)],degree:2):try span([.origin,.init(x:1,y:0,z:0)])
            let boundaries=try OriginalCoonsSurface3D(vMinimumBoundary:bottom,
                vMaximumBoundary:span([.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]),
                uMinimumBoundary:span([.origin,.init(x:0,y:1,z:0)]),uMaximumBoundary:span([.init(x:1,y:0,z:0),.init(x:1,y:1,z:0)]),tolerance:.standard,usage:&usage)
            let plane=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
                controlPoints:[[.origin,.init(x:1,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
            return try OriginalBoundaryCorrectedSurface3D(construction:plane,boundaries:boundaries,maximumSpanCount:1,maximumSubdivisionDepth:0,tolerance:.standard,usage:&usage)
        }.value
    }
    static func main() throws {
        var a=ExactScalarLedger(limits:try .init(work:160_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let provider=OriginalBoundaryCorrectionSnapshotProvider(field:f,tolerance:.standard)
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        for nonzero in [false,true] {
            let original=try shape(nonzero:nonzero,using:&a)
            let source=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(original,limits:limits,using:&a)
            let family=try DefaultOriginalFiniteRetainedSurfaceChartPreparer<OriginalBoundaryCorrectionSnapshot>().prepare(source:source,maximumCharts:1,limits:limits,using:&a)
            try family.admitProof(limits:limits,using:&a);try require(family.laws.count==1)
            let domainLimits=try OriginalDomainIdentityLimits(source:limits,maximumTransportDepth:16,
                maximumCharts:4,maximumFamilies:1,maximumIdentityProofs:8)
            let domainIssuer=DefaultOriginalRetainedSurfaceDomainIssuer<OriginalBoundaryCorrectionSnapshot>()
            let frame=try domainIssuer.frame(family:family,limits:domainLimits,using:&a)
            let cover=try domainIssuer.issue(request:frame.fullSelection(limits:domainLimits,using:&a),
                family:family,limits:domainLimits,using:&a)
            let half=try f.binary64(exactly:0.5,using:&a),quarter=try f.binary64(exactly:0.25,using:&a)
            let occurrences=try cover.incident(at:[half,quarter],limits:domainLimits,using:&a)
            try require(occurrences.count==1)
            let transport=DefaultOriginalParameterTransporter<OriginalBoundaryCorrectionSnapshot,OriginalExactScalarDomain>()
            let local=try transport.forward([half,quarter],through:transport.inverse(occurrences[0].transport,limits:domainLimits,using:&a),
                limits:domainLimits,using:&a)
            try require(f.compare(local[0],half,using:&a) == .equal && f.compare(local[1],quarter,using:&a) == .equal)
            let selected=try frame.selection(intervals:[[
                .checked(field:f,lower:.finite(half),upper:.finite(half),depth:.init(value:0,coefficient:0),using:&a)],
                [.checked(field:f,lower:.finite(quarter),upper:.finite(quarter),depth:.init(value:0,coefficient:0),using:&a)]],
                limits:domainLimits,using:&a)
            try require(domainIssuer.issue(request:selected,family:family,limits:domainLimits,using:&a)
                .incident(at:[half,quarter],limits:domainLimits,using:&a).count==1)
            let empty=try frame.selection(intervals:[[],[]],limits:domainLimits,using:&a)
            try require(domainIssuer.issue(request:empty,family:family,limits:domainLimits,using:&a)
                .selectedMembers(limits:domainLimits,using:&a).isEmpty)
            let law=family.laws[0],r=law.polynomials
            for (u,v,expectedZ) in [(0.5,0.0,nonzero ? 0.125:0),(0.5,0.25,nonzero ? 0.112060546875:0),(0.5,0.5,nonzero ? 0.0625:0)] {
                let params=[try f.binary64(exactly:u,using:&a),try f.binary64(exactly:v,using:&a)]
                let d=try r.evaluated(law.denominator,at:params,using:&a).value
                let z=try f.dividing(r.evaluated(law.homogeneous[2],at:params,using:&a).value,d,using:&a)
                try require(f.compare(z,f.binary64(exactly:expectedZ,using:&a),using:&a) == .equal)
                let actual=try original.point(u:u,v:v,tolerance:.standard)
                try require((actual-Point3D(x:u,y:v,z:expectedZ)).length<1e-9)
            }
            let derivatives=try original.parameterDerivatives(u:0.5,v:0.25,tolerance:.standard)
            try require(abs(derivatives.tangentV.z-(nonzero ? -0.1318359375:0))<1e-9)
            let coons=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalCoonsRationalDifferentialAtlas.prepared(original.boundaries,usage:&usage)
            }.value
            guard let coons else { throw ExactScalarFailure.invalidEvidence }
            try require(coons.cells.count==1)
            let fields=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try coons.fields(over:.init(u:.init(lower:0.5,upper:0.5),v:.init(lower:0.25,upper:0.25)),usage:&usage)
            }.value
            try require(fields.count==1 && fields[0].normal[2].lower>0)
            let native=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalCoonsRationalDifferentialAtlas.prepared(.bSpline(original.construction),maximumSpanCount:1,tolerance:.standard,usage:&usage)
            }.value
            guard let native else { throw ExactScalarFailure.invalidEvidence }
            try require(native.cells.count==1)
            let nativeFields=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try native.fields(over:.init(u:.init(lower:0.5,upper:0.5),v:.init(lower:0.25,upper:0.25)),usage:&usage)
            }.value
            try require(nativeFields.count==1 && nativeFields[0].normal[2].lower>0)
            var noStorage=ExactScalarLedger(limits:try .init(work:160_000_000,storageBytes:0,valueDepth:32,coefficientDepth:32))
            do { _ = try provider.snapshot(original,limits:limits,using:&noStorage);throw ExactScalarFailure.invalidEvidence }
            catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
            do { _ = try provider.snapshot(original,limits:.init(remainingSourceDepth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
            catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
            let bad=ModelingTolerance(distance:2*ModelingTolerance.standard.distance,angle:ModelingTolerance.standard.angle,relative:ModelingTolerance.standard.relative)
            do { _ = try OriginalBoundaryCorrectionSnapshotProvider(field:f,tolerance:bad).snapshot(original,limits:limits,using:&a);throw ExactScalarFailure.invalidEvidence }
            catch OriginalSourceIssuanceFailure.sourceRejected {}
        }
        print("PASS M4 actual retained correction XYZ/D, nonzero and zero corrections, original point/derivative, Native/Coons differential interaction and explicit source/storage failures")
    }
}
