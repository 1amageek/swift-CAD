import CADCore
import CADGeometry
import Synchronization

/// The one invocation-owned source/native allowance, identical on every target.
package final class LoftSurfacePreparationAllowance: Sendable {
    private let used: Mutex<Int>
    private let maximum: Int
    private let maximumDepth: Int
    private let featureID: FeatureID
    private let tolerance: ModelingTolerance
    private let admission: GeometryConversionAdmission?

    package init(maximum: Int, maximumDepth: Int, featureID: FeatureID, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission? = nil) throws {
        guard maximum > 0, maximumDepth >= 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, featureID: featureID,
                tolerance: tolerance, message: "Loft source preparation requires its original positive allowance.")
        }
        self.maximum = maximum; self.maximumDepth = maximumDepth
        self.featureID = featureID; self.tolerance = tolerance; self.admission = admission
        try admission?.chargeStorage(bytes: MemoryLayout<Mutex<Int>>.stride)
        // The initial owner slot is reserved against the original limit before
        // its Mutex is allocated; later operations share this same counter.
        used = Mutex(1)
    }

    package func consume(_ count: Int) throws {
        try debit(count)
        try admission?.chargeWork(count)
    }
    package func retain(_ words: Int) throws {
        let bytes = words.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard words >= 0, !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, featureID: featureID,
                tolerance: tolerance, message: "Loft body proof storage conversion overflows.")
        }
        try debit(words)
        try admission?.chargeStorage(bytes: bytes.partialValue)
    }
    private func debit(_ count: Int) throws {
        try Task.checkCancellation()
        try used.withLock { value in
            guard count >= 0, count <= maximum - value else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    featureID: featureID, tolerance: tolerance,
                    message: "Loft source/native preparation exhausted its cumulative side-pair allowance.")
            }
            value += count
        }
    }
    package func visit(depth: Int) throws {
        guard depth >= 0, depth <= maximumDepth else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                featureID: featureID, tolerance: tolerance,
                message: "Loft native proof exceeds its original subdivision allowance.")
        }
        try consume(1)
    }
}
