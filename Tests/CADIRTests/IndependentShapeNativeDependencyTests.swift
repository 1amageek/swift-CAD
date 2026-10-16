import Testing
import Synchronization
import CADCore
import CADGeometry
import CADTopology
@testable import CADIR

@Suite("Independent source Native dependency contracts")
struct IndependentShapeNativeDependencyTests {
    private func source(gain: OriginalParameterGain) throws -> IndependentShapeSource {
        let curveID = CurveID(), itemID = IndependentShapeItemID()
        let curve = Curve3D.parameterImage(try ParameterImageCurve3D(
            source: .line(Line3D(origin: .origin, direction: .unitX)),
            parameterGain: gain, tolerance: .standard))
        let degree = IndependentShapeAngularSource(law: .conversion(.init(
            name: "degree", factor: AngleUnit.degree.toInternal(1), interpretation: .canonicalDegree,
            base: .init(law: .radian(prefix: nil)))))
        return IndependentShapeSource(geometry: GeometryStore(curves: [curveID: curve]),
            items: [.init(id: itemID, name: "original angular chart", geometry: .curve(curveID, trim: nil))],
            ambientOriginalAngularSource: degree, roots: [.item(itemID)])
    }

    private func selectionExecution(work: Int = 0, storage: Int = 0,
        maximumStorage: Int = Int.max, cancelled: Bool = false,
        maximumDepth: Int = 0) throws -> OriginalQueryExecution {
        let remainingWords = Mutex(maximumStorage)
        let budget = try OriginalQueryBudget(consumeStorageBytes: { bytes in
            let words = bytes / 4 + (bytes % 4 == 0 ? 0 : 1)
            try remainingWords.withLock { remaining in
                guard words <= remaining else {
                    throw IndependentShapeSourceError.resourceLimitExceeded("Selection test storage ceiling.")
                }
                remaining -= words
            }
        }, checkpoint: { if cancelled { throw CancellationError() } })
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: maximumDepth, maximumCoefficientDepth: maximumDepth,
                remainingSourceDepth: 4, maximumSubdivisionDepth: 4))
        if work > 0 { try execution.consumeWork(work) }
        if storage > 0 { try execution.retainStorage(bytes: storage * MemoryLayout<UInt32>.stride) }
        return execution
    }
    private func originalCause(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return originalCause(failure.originalError) }
        if case ExactScalarFailure.admissionRejected(let cause) = error { return originalCause(cause) }
        return error
    }

    @Test(.timeLimit(.minutes(1)))
    func canonicalSelectionBorrowsStorageAndWorkOnOriginalLedger() throws {
        var construction = try selectionExecution(maximumDepth: 32)
        let polyline = try OriginalPolylineCurve3D(points: [.origin, .init(x: 1, y: 0, z: 0)],
            isClosed: false, tolerance: .standard, remainingSourceDepth: 4,
            maximumSubdivisionDepth: 4, maximumAlgebraicDepth: 32, usage: &construction)
        let basis = Curve3D.originalPolyline(polyline)
        let law = IndependentShapeAngularSource.CoordinateLaw.canonicalGain(.ratio(numerator: Double.pi, denominator: 180))
        var caller = try selectionExecution(work: 7, storage: 11)
        let selected = try IndependentShapeAngularCurveSelection.foreignCurve(basis: basis, law: law,
            tolerance: .standard, maximumSourceDepth: 4, maximumSubdivisionDepth: 4,
            maximumAlgebraicDepth: 0, using: &caller)
        #expect(caller.budget.snapshot.work > 7 && caller.budget.snapshot.storageBytes / 4 > 11)
        guard case .parameterImage(let image) = selected else { Issue.record("Expected original selected chart."); return }
        #expect(image.source == basis)
        #expect(image.parameterGain == .ratio(numerator: Double.pi, denominator: 180))

        var refused = try selectionExecution(maximumStorage: 0)
        #expect {
            _ = try IndependentShapeAngularCurveSelection.foreignCurve(basis: basis, law: law,
                tolerance: .standard, maximumSourceDepth: 4, maximumSubdivisionDepth: 4,
                maximumAlgebraicDepth: 0, using: &refused)
        } throws: { originalCause($0) is IndependentShapeSourceError }
        #expect(refused.budget.snapshot.work > 0 && refused.budget.snapshot.storageBytes == 0)
        var cancelled = try selectionExecution(cancelled: true)
        #expect {
            _ = try IndependentShapeAngularCurveSelection.foreignCurve(basis: basis, law: law,
                tolerance: .standard, maximumSourceDepth: 4, maximumSubdivisionDepth: 4,
                maximumAlgebraicDepth: 0, using: &cancelled)
        } throws: { originalCause($0) is CancellationError }
    }

    @Test(.timeLimit(.minutes(1)))
    func usesActualAmbientAngularSourceAndRetainsCallerAdmission() throws {
        let validator: any IndependentShapeSourceValidating = DefaultIndependentShapeSourceValidator()
        let matching = try source(gain: .ratio(numerator: Double.pi, denominator: 180))
        let receipt = try validator.validate(matching, tolerance: .standard, limits: .standard, bodySourceGraph: nil, check: {})
        #expect(receipt.consumedRecords > 0 && receipt.consumedWork > 0)
        #expect(throws: IndependentShapeSourceError.self) {
            _ = try validator.validate(source(gain: .binary(2)), tolerance: .standard, limits: .standard, bodySourceGraph: nil, check: {})
        }
        #expect(throws: IndependentShapeSourceError.self) {
            _ = try validator.validate(matching, tolerance: .standard,
                limits: IndependentShapeSourceLimits(maximumWork: 1), bodySourceGraph: nil, check: {})
        }
        #expect(throws: CancellationError.self) {
            _ = try validator.validate(matching, tolerance: .standard, limits: .standard,
                bodySourceGraph: nil, check: { throw CancellationError() })
        }
    }
}
