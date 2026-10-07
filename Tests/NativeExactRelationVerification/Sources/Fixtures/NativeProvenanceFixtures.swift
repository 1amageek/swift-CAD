import CADCore
@testable import CADGeometry
import Synchronization

public enum NativeProvenanceFixtures {
    enum Failure: Error { case rejected, invalidEvidence }
    final class Sink: SurfaceSilhouetteProvenanceWriting {
        let events = Mutex<[SurfaceSilhouetteProvenanceEvent]>([])
        let rejecting: Bool
        init(rejecting: Bool = false) { self.rejecting = rejecting }
        func write(_ event: SurfaceSilhouetteProvenanceEvent, usage: inout SurfaceSilhouetteUsage) throws {
            if rejecting { throw Failure.rejected }
            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteProvenanceEvent.self, usage: &usage)
            events.withLock { $0.append(event) }
        }
    }
    public static func verify() throws {
        var usage = try SurfaceSilhouetteUsage(maximumWork:10_000_000,maximumCells:10000,
            maximumStorage:30_000_000,maximumDepth:32)
        let u=try ExactBivariatePolynomial.coordinate(alongU:true,usage:&usage)
        let v=try ExactBivariatePolynomial.coordinate(alongU:false,usage:&usage)
        let half=try ExactBivariatePolynomial.constant(.originalDouble(0.5,usage:&usage),usage:&usage)
        let equations=try [u.multiplied(by:u,usage:&usage).subtracting(half,usage:&usage),v.subtracting(u,usage:&usage)]
        let box=SurfaceParameterBox(u:try .init(lower:0,upper:1),v:try .init(lower:0,upper:1))
        let roots=try ExactBivariateSystemSolver.isolatedRoots(of:equations,over:box,maximumDepth:32,usage:&usage)
        guard roots.count == 1,let root=roots.first else { throw Failure.invalidEvidence }
        let context=try OriginalSingularFieldContext(original:root,usage:&usage)
        let sink=Sink();var emitter=SurfaceSilhouetteProvenanceEmitter(sink:sink)
        try emitter.write(context,usage:&usage)
        let state=sink.events.withLock { $0 }
        guard state.contains(where:{ if case .beginRecord("ExactAlgebraicPairAuthority")=$0 { return true };return false }),
            state.contains(where:{ if case .field("projectionRoot")=$0 { return true };return false }),
            state.contains(where:{ if case .field("fiberRoot")=$0 { return true };return false }),
            state.contains(where:{ if case .field("fiber")=$0 { return true };return false }) else { throw Failure.invalidEvidence }
        var failing=SurfaceSilhouetteProvenanceEmitter(sink:Sink(rejecting:true))
        do { try failing.write(context,usage:&usage);throw Failure.invalidEvidence }
        catch Failure.rejected { }
        print("PASS scalar authority provenance and sink failure")
    }
}
