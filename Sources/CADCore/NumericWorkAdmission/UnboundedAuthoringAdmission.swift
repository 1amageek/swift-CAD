/// The explicit existing ordinary authoring policy; direct calls never construct this adapter.
package struct UnboundedAuthoringAdmission: NumericWorkAdmission {
    package init() {}

    package mutating func checkpoint() {}

    package mutating func consumeWork(_ units: Int) throws {
        guard units >= 0 else { throw invalidCount() }
    }

    package mutating func retainStorage(count: Int, stride: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, stride >= 0, !bytes.overflow else { throw invalidCount() }
    }

    private func invalidCount() -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: .standard,
            message: "Numeric authoring storage or work count is invalid or overflows.")
    }
}
