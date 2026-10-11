import CADCore
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import SourceGeometryAdapters
import NativeDomainAdapters
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer

@main enum NativePeriodicBindingFailure {
    typealias F = FamilyFixtures.Field
    typealias Member = NativeExactSymbolicRelationMember<BSplineCurve3D,BSplineSurface3D>

    static func detachedMember() throws -> Member {
        var a = try FamilyFixtures.ledger()
        let f = try FamilyFixtures.field(&a)
        let first = try FamilyFixtures.curveCover(FamilyFixtures.stationary(),f,nil,&a)
        let second = try FamilyFixtures.surfaceCover(FamilyFixtures.periodicSurface(),f,nil,&a)
        let family = try DefaultCurveSurfaceIntersector().exactParameterRelationFamily(curve:first,surface:second,
            domainLimits:FamilyFixtures.limits(),maximumMaps:64,maximumPairs:4096,
            cellLimits:FamilyFixtures.cells(),topologyLimits:FamilyFixtures.topology(),using:&a)
        let zero = try OriginalParameterCycle(exact:ExactRationalScalarDomain().integer(0,using:&a),using:&a)
        return try family.member(template:0,firstCycles:[zero],secondCycles:[zero,zero],limits:FamilyFixtures.limits(),using:&a)
    }

    static func main() throws {
        var a = try FamilyFixtures.ledger()
        let f = try FamilyFixtures.field(&a),foreign = try FamilyFixtures.field(&a)
        let surface = try FamilyFixtures.surfaceCover(FamilyFixtures.periodicSurface(),f,nil,&a)
        for empty in [false,true] {
            let curve = try FamilyFixtures.curveCover(FamilyFixtures.stationary(),foreign,empty ? [[]]:nil,&a)
            do {
                _ = try DefaultCurveSurfaceIntersector().exactParameterRelationFamily(curve:curve,surface:surface,
                    domainLimits:FamilyFixtures.limits(),maximumMaps:64,maximumPairs:4096,
                    cellLimits:FamilyFixtures.cells(),topologyLimits:FamilyFixtures.topology(),using:&a)
                throw ExactScalarFailure.invalidEvidence
            } catch NativeExactRelationFailure.scalar(.incompatibleDomain) {}
        }
        let empty = try FamilyFixtures.curveCover(FamilyFixtures.stationary(),f,[[]],&a)
        let noFamilies = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:0),maximumTransportDepth:16,
            maximumCharts:64,maximumFamilies:0,maximumIdentityProofs:0)
        do {
            _ = try DefaultCurveSurfaceIntersector().exactParameterRelationFamily(curve:empty,surface:surface,
                domainLimits:noFamilies,maximumMaps:64,maximumPairs:4096,
                cellLimits:FamilyFixtures.cells(),topologyLimits:FamilyFixtures.topology(),using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch NativeExactRelationFailure.domain(.familyLimit) {}
        let member = try detachedMember()
        let retained = member.first.selectedImage.frame.scalarField
        try FamilyFixtures.require(try member.contains(firstTuple:[retained.binary64(exactly:0.5,using:&a)],
            secondTuple:[retained.binary64(exactly:0.25,using:&a),retained.binary64(exactly:0.5,using:&a)],
            domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a))
        print("PASS foreign construction fields and empty family limits fail explicitly")
        print("PASS member retains source, period-derived correspondence and L5 after family release")
    }
}
