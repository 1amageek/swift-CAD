import CADGeometry
import Foundation
struct TrackingLedger:~Copyable,ExactScalarAdmission {
    var ledger:ExactScalarLedger
    init(limits:ExactScalarLimits) { ledger=ExactScalarLedger(limits:limits) }
    mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
    mutating func consumeWork(_ units:Int) throws(ExactScalarFailure) {
        do { try ledger.consumeWork(units) }
        catch {
            FileHandle.standardError.write(Data(Thread.callStackSymbols.joined(separator:"\n").utf8))
            throw error
        }
    }
    mutating func retainStorage(bytes:Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
    mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
    mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
}

@main struct BoundedMemberTrackingProbe {
 static func main() throws {
  var a=TrackingLedger(limits:try .init(work:8_388_608,storageBytes:268_435_456,valueDepth:32,coefficientDepth:32))
  let angle=Double(bitPattern:0x3fddac670561bb50)
  let physical=try OriginalPhysicalAngleScalarDomain(originalRadians:angle,using:&a)
  let input=OriginalBoundedSphereConeSurfaceInput(first:.analytic(.sphere(center:.origin,radius:2)),second:.analytic(.cone(apex:.init(x:2,y:0,z:-4),axis:.unitZ,halfAngle:angle)))
  guard try OriginalBoundedSphereConeSurfaceSnapshotProvider.admitsSingleArc(input,physical:physical,using:&a) else { fatalError("Single arc") }
  let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalBoundedSphereConeSurfaceSnapshotProvider(physical:physical,maximumExtensionLevel:32,tolerance:.standard)).bind(input,limits:.init(remainingSourceDepth:1),using:&a)
  let limits=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),maximumTransportDepth:32,maximumCharts:262_144,maximumFamilies:2,maximumIdentityProofs:0)
  let relation=try OriginalBoundedSphereConeSurfaceRelation.resolve(source:source,firstBox:nil,secondBox:nil,maximumComponents:262_144,limits:limits,using:&a)
  print("PASS relation",a.ledger.work,relation.isEmpty)
  var query=TrackingLedger(limits:try .init(work:8_388_608,storageBytes:268_435_456,valueDepth:32,coefficientDepth:32))
  let t=try source.original.field.integer(1,using:&query)
  let section=try relation.section(halfAngle:t,limits:limits,using:&query)
  print("PASS section",query.ledger.work)
  let q=ExactRationalScalarDomain();var value=try q.integer(1,using:&a)
  for _ in 0..<5 { value=try q.multiplying(value,q.integer(UInt64(1)<<32,using:&a),using:&a) }
  let positive=try OriginalParameterCycle(exact:value,using:&a),negative=try OriginalParameterCycle(exact:q.negated(value,using:&a),using:&a)
  var member=TrackingLedger(limits:try .init(work:8_388_608,storageBytes:268_435_456,valueDepth:32,coefficientDepth:32))
  _=try section.member(branch:0,coneCycle:positive,sphereCycle:negative,limits:limits,using:&member)
  print("PASS member",member.ledger.work)
 }
}
