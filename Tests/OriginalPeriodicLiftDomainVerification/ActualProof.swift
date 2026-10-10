import CADCore
import struct CADGeometry.BSplineCurve2D
import struct CADGeometry.SurfaceLiftCurve3D
import L0
import L1
import DI0
import SourceIssuer
import DI

@main struct ActualPeriodicLiftDomainProof {
    static func main() throws { try run() }
    nonisolated static func shape(two: Bool=false,multi: Bool=false,huge: Bool=false) -> SurfaceLiftCurve3D {
        let base=ActualPeriodicLiftProof.shape(two:two)
        if !multi && !huge { return base }
        let giant=3*Double(sign:.plus,exponent:96,significand:1),values=huge ? [giant,giant]:[-3.0,0,6]
        let p=BSplineCurve2D(degree:1,knots:huge ? [0,0,1,1]:[0,0,1,3,3],
            controlPoints:values.map { Point2D(x:$0,y:two ? (huge ? -$0:$0):0.5) })
        return .init(surface:base.surface,parameterCurve:.bSpline(p))
    }
    nonisolated static func actualPositions(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<OriginalNativeSurfaceLiftSnapshot>,two: Bool,multi: Bool) throws {
        var a=try LiftAdmission();let c=try DomainChecks.cover(family,using:&a),f=family.field,l=try DomainChecks.limits()
        let third=try f.dividing(f.integer(1,using:&a),f.integer(3,using:&a),using:&a)
        for t in [0.0,0.25,1.0/3,0.5,0.75,1.0] {
            let parameter=t==1.0/3 ? third:try f.binary64(exactly:t,using:&a)
            let u=try f.subtracting(f.multiplying(f.integer(9,using:&a),parameter,using:&a),f.integer(3,using:&a),using:&a)
            let tuple=[parameter,u,two ? u:try f.binary64(exactly:0.5,using:&a)]
            let found=try c.liftedPositionIncidents(at:tuple,limits:l,using:&a)
            try LiftChecks.require(!found.isEmpty)
            if multi && t==1.0/3 { try LiftChecks.require(found.count==(two ? 8:4)) }
            // Exact 1/3 is not the same parameter as its binary64 approximation.
            // Compare its graph position independently; public evaluation uses binary T below.
            let point: Point3D
            if t==1.0/3 { point=Point3D(x:0,y:0,z:two ? 0:0.5) }
            else { point=try family.source.original.original.point(atNormalizedFraction:t,tolerance:.standard) }
            for occurrence in found {
                let xyz=try LiftChecks.position(occurrence.relation.graph,values:tuple,using:&a)
                for (axis,expected) in [point.x,point.y,point.z].enumerated() {
                    try LiftChecks.require(f.compare(xyz[axis],f.binary64(exactly:expected,using:&a),using:&a) == .equal)
                }
            }
        }
        print("PASS actual original periodic lift evaluator and all DI-bound chart positions")
    }
    nonisolated static func detachedSource() throws -> OriginalPeriodicNativeSurfaceLiftChartOccurrence<OriginalNativeSurfaceLiftSnapshot> {
        let original=shape(two:true)
        let family=try ActualPeriodicLiftProof.family(original)
        var a=try LiftAdmission();let f=family.field
        let tuple=[try f.binary64(exactly:0.5,using:&a),try f.binary64(exactly:1.5,using:&a),try f.binary64(exactly:1.5,using:&a)]
        return try DomainChecks.detached(family,tuple:tuple)
    }
    nonisolated static func run() throws {
        for two in [false,true] {
            for multi in [false,true] {
                let family=try ActualPeriodicLiftProof.family(shape(two:two,multi:multi))
                try DomainChecks.run(family,twoAxes:two,multi:multi)
                try actualPositions(family,two:two,multi:multi)
            }
            try DomainChecks.huge(ActualPeriodicLiftProof.family(shape(two:two,huge:true)),twoAxes:two)
        }
        try DomainChecks.resources(ActualPeriodicLiftProof.family(shape()),foreign:ActualPeriodicLiftProof.family(shape()))
        let retained=try detachedSource()
        var a=try LiftAdmission();let f=retained.family.field
        let tuple=[try f.binary64(exactly:0.5,using:&a),try f.binary64(exactly:1.5,using:&a),try f.binary64(exactly:1.5,using:&a)]
        try retained.relation.admitProof(limits:DomainChecks.limits(),using:&a)
        let xyz=try LiftChecks.position(retained.relation.graph,values:tuple,using:&a)
        let point=try retained.family.source.original.original.point(atNormalizedFraction:0.5,tolerance:.standard)
        for (axis,value) in [point.x,point.y,point.z].enumerated() {
            try LiftChecks.require(f.compare(xyz[axis],f.binary64(exactly:value,using:&a),using:&a) == .equal)
        }
        print("PASS actual original source and evaluator retained by detached DI occurrence")
        print("PASS actual periodic lift source/domain/evaluator composition")
    }
}
