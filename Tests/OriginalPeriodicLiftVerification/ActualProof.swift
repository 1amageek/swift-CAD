import CADCore
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.BSplineCurve2D
import struct CADGeometry.SurfaceLiftCurve3D
import enum CADGeometry.Surface3D
import L0
import L1
import SourceIssuer

@main struct ActualPeriodicLiftProof {
    typealias Source=OriginalNativeSurfaceLiftSnapshot
    typealias Family=OriginalPeriodicNativeSurfaceLiftGraphs<Source>
    static func main() throws { try run() }
    nonisolated static func shape(two: Bool=false,nonmonotone: Bool=false,constant: Double?=nil,
        finite: Bool=false) -> SurfaceLiftCurve3D {
        let xy:[[Double]]=finite ? [[0,0],[1,0]]:[[0,0],[1,0],[0,1],[0,0]],yz=two ? xy:[[0,0],[0,1]]
        let rows=yz.map { v in xy.map { u in Point3D(x:u[0],y:u[1]+v[0],z:v[1]) } }
        let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:finite ? [0,0,1,1]:[-1,0,1,2,3,4],
            vKnots:two ? [-1,0,1,2,3,4]:[0,0,1,1],controlPoints:rows,weights:finite ? [[1,2],[1,2]]:nil,isUPeriodic:!finite,isVPeriodic:two)
        let uv=constant.map { [$0,$0] } ?? (nonmonotone ? [-3.0,6.0,-3.0]:finite ? [0.0,1.0]:[-3.0,6.0])
        let p=BSplineCurve2D(degree:nonmonotone ? 2:1,knots:nonmonotone ? [2,2,2,4,4,4]:[2,2,4,4],
            controlPoints:uv.map { Point2D(x:$0,y:two ? $0:0.5) },weights:finite ? [1,2]:nil)
        return SurfaceLiftCurve3D(surface:.bSpline(native),parameterCurve:.bSpline(p))
    }
    nonisolated static func family(_ original: SurfaceLiftCurve3D) throws -> Family {
        var a=try LiftAdmission();let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceLiftSnapshotProvider(tolerance:.standard)).bind(original,limits:l,using:&a)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let s=try DefaultOriginalBSplineFundamentalChartPreparer<BSplineSurface3D>().prepare(
            source:source.original.originalSurface,field:f,maximumCharts:32,limits:l,using:&a)
        let p=try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>().prepare(
            source:source.original.originalPcurve,field:f,maximumCharts:32,limits:l,using:&a)
        return try DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<Source>().prepare(
            source:source,surface:s,pcurve:p,maximumCharts:32,limits:l,using:&a)
    }
    nonisolated static func actualPositions(_ family: Family,two: Bool,nonmonotone: Bool=false,constant: Bool=false) throws {
        var a=try LiftAdmission();let f=family.field,q=ExactRationalScalarDomain(),l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        for t in [0.0,0.25,0.5,0.75,1.0] {
            let uv=constant ? 3.0:nonmonotone ? -3+18*t*(1-t):-3+9*t
            let values=[try f.binary64(exactly:t,using:&a),try f.binary64(exactly:uv,using:&a),try f.binary64(exactly:two ? uv:0.5,using:&a)]
            let cycle=Int((uv/3).rounded(.down))
            let point=try family.source.original.original.point(atNormalizedFraction:t,tolerance:.standard)
            var count=0
            for template in 0..<family.templateCount {
                let g=try family.graph(template:template,cycles:[q.integer(cycle,using:&a),q.integer(two ? cycle:0,using:&a)],maximumCharts:32,limits:l,using:&a)
                if try g.admits(values,limits:l,using:&a) {
                    count += 1
                    let xyz=try LiftChecks.position(g,values:values,using:&a)
                    for (axis,expected) in [point.x,point.y,point.z].enumerated() {
                        try LiftChecks.require(f.compare(xyz[axis],f.binary64(exactly:expected,using:&a),using:&a) == .equal)
                    }
                }
            }
            try LiftChecks.require(count>=1)
        }
        print("PASS actual original periodic lift construction/provider/evaluator correspondence")
    }
    nonisolated static func finiteRegression() throws {
        var a=try LiftAdmission();let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8),original=shape(finite:true)
        let binder=DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceLiftSnapshotProvider(tolerance:.standard))
        let source=try binder.bind(original,limits:l,using:&a)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let s=try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:source.original.originalSurface,field:f,maximumCharts:8,limits:l,using:&a)
        let p=try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>().prepare(source:source.original.originalPcurve,field:f,maximumCharts:8,limits:l,using:&a)
        let family=try DefaultOriginalFiniteNativeSurfaceLiftGraphPreparer<Source>().prepare(source:source,surface:s,pcurve:p,maximumCharts:8,limits:l,using:&a)
        for t in [0.0,0.5,1.0] {
            let parameter=try f.binary64(exactly:t,using:&a)
            let uv=try f.dividing(f.multiplying(f.integer(2,using:&a),parameter,using:&a),f.adding(f.integer(1,using:&a),parameter,using:&a),using:&a)
            let values=[parameter,uv,try f.binary64(exactly:0.5,using:&a)]
            try LiftChecks.require(family.graphs.count==1 && family.graphs[0].admits(values,limits:l,using:&a))
            let xyz=try LiftChecks.position(family.graphs[0],values:values,using:&a)
            let expected=try original.point(atNormalizedFraction:t,tolerance:.standard)
            let exactX=try f.dividing(f.multiplying(f.integer(2,using:&a),uv,using:&a),f.adding(f.integer(1,using:&a),uv,using:&a),using:&a)
            for axis in 0..<3 {
                let target=axis==0 ? exactX : try f.binary64(exactly:axis==1 ? 0:0.5,using:&a)
                try LiftChecks.require(f.compare(xyz[axis],target,using:&a) == .equal)
            }
            let numeric=4*t/(1+3*t)
            try LiftChecks.require(abs(expected.x-numeric)<1e-12 && expected.y==0 && expected.z==0.5)
        }
        let periodic=try binder.bind(shape(),limits:l,using:&a)
        do { _=try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:periodic.original.originalSurface,field:f,maximumCharts:32,limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        // A nonperiodic-axis clamp must remain refused by the exact source provider.
        let outside=SurfaceLiftCurve3D(surface:original.surface,parameterCurve:.bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:0,y:-1e-10),.init(x:1,y:0.5)])))
        do { _=try binder.bind(outside,limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        print("PASS finite original lift regression, periodic finite refusal and nonperiodic UV clamp refusal")
    }
    nonisolated static func run() throws {
        for two in [false,true] {
            var original=shape(two:two)
            let saved=try family(original)
            // Mutating caller-owned COW children must not affect the retained source.
            if case .bSpline(var surface)=original.surface {
                surface.controlPoints[0][0]=Point3D(x:99,y:99,z:99)
                original=SurfaceLiftCurve3D(surface:.bSpline(surface),parameterCurve:original.parameterCurve)
            }
            try LiftChecks.run(saved,twoAxes:two);try actualPositions(saved,two:two)
            let reverse=try family(shape(two:two,nonmonotone:true))
            try LiftChecks.run(reverse,twoAxes:two,nonmonotone:true);try actualPositions(reverse,two:two,nonmonotone:true)
            let constant=try family(shape(two:two,constant:3))
            try LiftChecks.run(constant,twoAxes:two,constant:true);try actualPositions(constant,two:two,constant:true)
        }
        try LiftChecks.preparation(family(shape()),foreign:family(shape()))
        try LiftChecks.huge(family(shape(constant:3*Double(sign:.plus,exponent:96,significand:1))))
        try finiteRegression()
        print("PASS actual periodic lift source and finite regression")
    }
}
