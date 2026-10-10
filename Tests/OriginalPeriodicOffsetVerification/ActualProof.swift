import CADCore
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.Surface3D
import struct CADGeometry.OffsetSurface3D
import L0
import L1
import DI0
import SourceIssuer
import DI

@main struct ActualPeriodicOffsetProof {
    static func require(_ value: Bool) throws { guard value else { throw ExactScalarFailure.invalidEvidence } }
    static func main() throws {
        for twoAxes in [false,true] { for distance in [-0.25,0,0.25] {
            var a=ExactScalarLedger(limits:try .init(work:100_000_000,storageBytes:400_000_000,valueDepth:32,coefficientDepth:32))
            let l=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:8),maximumTransportDepth:16,maximumCharts:32,maximumFamilies:2,maximumIdentityProofs:32)
            let xy: [[Double]]=[[0,0],[1,0],[0,1],[0,0]]
            let yz: [[Double]]=twoAxes ? [[0,0],[1,0],[0,1],[0,0]]:[[0,0],[0,1]]
            let rows=yz.map { v in xy.map { u in Point3D(x:u[0],y:u[1]+v[0],z:v[1]) } }
            var native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3,4],vKnots:twoAxes ? [-1,0,1,2,3,4]:[0,0,1,1],
                controlPoints:rows,isUPeriodic:true,isVPeriodic:twoAxes)
            let shape=OffsetSurface3D(source:.bSpline(native),distance:distance)
            let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalOffsetSnapshotProvider(
                child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:.standard))).bind(shape,limits:l.source,using:&a)
            let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
            let child=try DefaultOriginalBSplineFundamentalChartPreparer<BSplineSurface3D>().prepare(source:source.original.originalChild,
                field:f,maximumCharts:32,limits:l.source,using:&a)
            let family=try DefaultOriginalPeriodicNativeOffsetLawPreparer<OriginalOffsetSnapshot<BSplineSurface3D>>().prepare(
                source:source,child:child,maximumCharts:32,limits:l.source,using:&a)
            let issuer=DefaultOriginalPeriodicNativeOffsetDomainIssuer<OriginalOffsetSnapshot<BSplineSurface3D>>()
            let space=try issuer.prepare(family:family,limits:l,using:&a)
            let cover=try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
            native.controlPoints[0][0]=Point3D(x:99,y:99,z:99)
            for u in [-3.0,0,0.5,3,6] {
                let v=twoAxes ? -3.0:0.5
                let uv=[try f.binary64(exactly:u,using:&a),try f.binary64(exactly:v,using:&a)]
                let one=try f.integer(1,using:&a)
                let occurrences=try cover.liftedPositionIncidents(at:uv+[one],limits:l,using:&a)
                try require(occurrences.count==1)
                let occurrence=occurrences[0],t=DefaultOriginalParameterTransporter<BSplineSurface3D,OriginalExactScalarDomain>()
                let local=try t.forward(uv,through:t.inverse(occurrence.child.correspondence,limits:l,using:&a),limits:l,using:&a)
                let values=[local[0],local[1],one],law=occurrence.law,r=law.polynomials
                let d=try r.evaluated(law.denominator,at:values,using:&a).value
                let actual=try shape.point(u:u,v:v,tolerance:.standard)
                for (axis,expected) in [actual.x,actual.y,actual.z].enumerated() {
                    let exact=try f.dividing(r.evaluated(law.homogeneous[axis],at:values,using:&a).value,d,using:&a)
                    try require(f.compare(exact,f.binary64(exactly:expected,using:&a),using:&a) == .equal)
                }
            }
        } }
        print("PASS real periodic Native offset construction/provider/DI/evaluator, independent axes, negative cycles, seam ownership, signed/zero distance and COW")
    }
}
