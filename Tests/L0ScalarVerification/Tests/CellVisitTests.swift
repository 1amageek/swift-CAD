@testable import L0
import Testing

@Suite(.timeLimit(.minutes(1)))
struct CellVisitTests {
    struct VisitAdmission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var events: [(ExactScalarRootAxis, Int)] = []
        let maximumVisits: Int
        var cancelOnVisit: Bool = false
        init(maximumVisits: Int) throws {
            self.maximumVisits = maximumVisits
            ledger = .init(limits: try .init(work: 100, storageBytes: 100,
                valueDepth: 32, coefficientDepth: 32))
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
            try ledger.consumeWork(units)
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try ledger.retainStorage(bytes: bytes)
        }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            try ledger.admitDepth(value: value, coefficient: coefficient)
        }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try ledger.visitCell(axis: axis, depth: depth)
            guard events.count < maximumVisits else { throw .admissionRejected(VisitLimit.exhausted) }
            events.append((axis, depth))
            if cancelOnVisit { ledger.cancel() }
        }
    }
    enum VisitLimit: Error { case exhausted }

    @Test func numericVisitsPreserveCausalAxesAndOneCumulativeCounter() throws {
        var admission = try VisitAdmission(maximumVisits: 2)
        let original = try ExactScalarDepth(value: 2, coefficient: 4)
        let inherited = try ExactScalarDepth(value: 7, coefficient: 11)
        let result = try ExactScalarNumericAccess.withAdmission(&admission,
            original: original, inherited: inherited) { numeric in
            try numeric.visitExactCell(depth: 3)
            try numeric.visitCoefficientCell(depth: 6)
        }
        #expect(admission.events.count == 2)
        #expect(admission.events[0].0 == .value && admission.events[0].1 == 8)
        #expect(admission.events[1].0 == .coefficient && admission.events[1].1 == 13)
        #expect(result.depth.value == 8 && result.depth.coefficient == 13)
        #expect(admission.ledger.valueDepth == 8 && admission.ledger.coefficientDepth == 13)
        do {
            _ = try ExactScalarNumericAccess.withAdmission(&admission) { numeric in
                try numeric.visitCoefficientCell(depth: 0)
            }
            Issue.record("A second numeric invocation reset the caller visit counter")
        } catch ExactScalarFailure.admissionRejected(let cause) {
            #expect(cause is VisitLimit)
            #expect(admission.events.count == 2)
        }
    }

    @Test func visitCancellationIsObservedBeforeNumericPublication() throws {
        var admission = try VisitAdmission(maximumVisits: 1)
        admission.cancelOnVisit = true
        do {
            _ = try ExactScalarNumericAccess.withAdmission(&admission) { numeric in
                try numeric.visitExactCell(depth: 0)
            }
            Issue.record("A visit callback cancelled but the bridge returned success")
        } catch ExactScalarFailure.cancelled {
            #expect(admission.events.count == 1)
            #expect(admission.ledger.work == 1)
        }
    }

    @Test func plainLedgerPreservesIndependentDepthAndRejectsInvalidVisit() throws {
        var admission = ExactScalarLedger(limits: try .init(work: 0, storageBytes: 0,
            valueDepth: 2, coefficientDepth: 4))
        try admission.visitCell(axis: .value, depth: 2)
        try admission.visitCell(axis: .coefficient, depth: 4)
        #expect(admission.work == 0 && admission.storageBytes == 0)
        do {
            try admission.visitCell(axis: .value, depth: 3)
            Issue.record("A visit exceeded the independent value depth")
        } catch ExactScalarFailure.resourceLimit(.valueDepth) {
            #expect(admission.valueDepth == 2 && admission.coefficientDepth == 4)
        }
        do {
            try admission.visitCell(axis: .coefficient, depth: -1)
            Issue.record("A negative visit depth was admitted")
        } catch ExactScalarFailure.countOverflow { }
    }
}
