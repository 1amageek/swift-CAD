import L0
struct TerminalAdmission: ExactScalarAdmission {
    var checkpoints = 0
    var cancelAt: Int? = nil
    var work = 0
    var storage = 0
    mutating func checkpoint() throws(ExactScalarFailure) {
        checkpoints += 1
        if checkpoints == cancelAt { throw .cancelled }
    }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
        let sum = work.addingReportingOverflow(units)
        guard units >= 0, !sum.overflow else { throw .countOverflow }; work = sum.partialValue
    }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        let sum = storage.addingReportingOverflow(bytes)
        guard bytes >= 0, !sum.overflow else { throw .countOverflow }; storage = sum.partialValue
    }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        guard depth >= 0 else { throw .invalidEvidence }
        try checkpoint()
    }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        guard value >= 0, coefficient >= 0 else { throw .invalidEvidence }
    }
}
