import L0
import L1
import SourceIssuer

extension SourceFixtures {
    public static func parametricGraphs() throws {
        var a = try TraceAdmission()
        let graph: OriginalParametricGraphReceipt<OffsetInput<NativeSnapshot>, OriginalExactScalarDomain,
            OriginalOffsetLawReceipt<OffsetInput<NativeSnapshot>, OriginalBSplineChartSelection, OriginalExactScalarDomain>>
        do {
            let family = try offset(using: &a)
            graph = try DefaultOriginalOffsetGraphIssuer().issue(family.laws[0], limits: .init(remainingSourceDepth: 1), using: &a)
            let rational = try DefaultOriginalRationalGraphIssuer().issue(family.child.laws[0], limits: .init(remainingSourceDepth: 0), using: &a)
            try require(rational.layout.parameters == [0,1] && rational.layout.auxiliaries.isEmpty)
            let f = rational.field, zero = try f.integer(0, using: &a)
            try require(rational.admits([zero,zero], limits: .init(remainingSourceDepth: 0), using: &a))
            let outside = try f.integer(2, using: &a)
            try require(!rational.admits([outside,zero], limits: .init(remainingSourceDepth: 0), using: &a))
        }
        let f = graph.field, zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
        let half = try f.dividing(one, f.integer(2, using: &a), using: &a)
        try require(graph.layout.parameters == [0,1] && graph.layout.auxiliaries == [2])
        try require(graph.admits([half,half,one], limits: .init(remainingSourceDepth: 1), using: &a))
        try require(!graph.admits([half,half,f.negated(one, using: &a)], limits: .init(remainingSourceDepth: 1), using: &a))
        try require(!graph.admits([half,zero,zero], limits: .init(remainingSourceDepth: 1), using: &a))
        try require(graph.evidence.source.original.originalDistance == 0.25)
        do { _ = try graph.admits([half,half], limits: .init(remainingSourceDepth: 1), using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        do { _ = try graph.admits([half,half,one], limits: .init(remainingSourceDepth: 0), using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        for roles in [([0,0],[2]), ([0],[2]), ([0,1],[3])] {
            do { _ = try OriginalParametricVariableLayout.checked(variableCount: 3, parameters: roles.0, auxiliaries: roles.1, using: &a); throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.invalidChart {}
        }
        try offsetKnotOwnership(using: &a)
        for axis in [ExactScalarRootAxis.value, .coefficient] {
            var limited = try TraceAdmission(rejectDepth: axis)
            var rejected = false
            do { _ = try DefaultOriginalOffsetGraphIssuer().issue(graph.evidence, limits: .init(remainingSourceDepth: 1), using: &limited) }
            catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(let resource)) { rejected = resource == (axis == .value ? .valueDepth : .coefficientDepth) }
            try require(rejected)
        }
        var measured = try TraceAdmission()
        _ = try DefaultOriginalOffsetGraphIssuer().issue(graph.evidence, limits: .init(remainingSourceDepth: 1), using: &measured)
        var exact = try TraceAdmission(work: measured.work, storage: measured.storageBytes)
        _ = try DefaultOriginalOffsetGraphIssuer().issue(graph.evidence, limits: .init(remainingSourceDepth: 1), using: &exact)
        var work = try TraceAdmission(work: measured.work-1)
        do { _ = try DefaultOriginalOffsetGraphIssuer().issue(graph.evidence, limits: .init(remainingSourceDepth: 1), using: &work); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var storage = try TraceAdmission(storage: measured.storageBytes-1)
        do { _ = try DefaultOriginalOffsetGraphIssuer().issue(graph.evidence, limits: .init(remainingSourceDepth: 1), using: &storage); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var final = try TraceAdmission(cancelAtStorage: measured.storageCalls)
        do { _ = try DefaultOriginalOffsetGraphIssuer().issue(graph.evidence, limits: .init(remainingSourceDepth: 1), using: &final); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) {}
        var cancelled = try TraceAdmission(); cancelled.base.cancel()
        do { _ = try graph.admits([half,half,one], limits: .init(remainingSourceDepth: 1), using: &cancelled); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS B1 sealed rational/offset graphs, roles, positive branch, singular fiber, lifetime and cumulative failures")
    }
}
