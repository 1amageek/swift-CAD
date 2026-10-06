import Testing
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

    private struct SelectionAdmission: RationalAlgebraAdmitting {
        var work = 0
        var storage = 0
        var maximumStorage = Int.max
        var cancelled = false
        mutating func consumeExactWork(_ count: Int) throws {
            if cancelled { throw CancellationError() }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            if cancelled { throw CancellationError() }
            guard count <= maximumStorage - storage else {
                throw IndependentShapeSourceError.resourceLimitExceeded("Selection test storage ceiling.")
            }
            storage += count
        }
        mutating func visitExactCell(depth: Int) throws { try consumeExactWork(1) }
    }

    @Test(.timeLimit(.minutes(1)))
    func canonicalSelectionBorrowsStorageAndWorkOnOriginalLedger() throws {
        var construction = SelectionAdmission()
        let polyline = try OriginalPolylineCurve3D(points: [.origin, .init(x: 1, y: 0, z: 0)],
            isClosed: false, tolerance: .standard, remainingSourceDepth: 4,
            maximumSubdivisionDepth: 4, maximumAlgebraicDepth: 32, usage: &construction)
        let basis = Curve3D.originalPolyline(polyline)
        let law = IndependentShapeAngularSource.CoordinateLaw.canonicalGain(.ratio(numerator: Double.pi, denominator: 180))
        var caller = SelectionAdmission(work: 7, storage: 11)
        let selected = try IndependentShapeAngularCurveSelection.foreignCurve(basis: basis, law: law,
            tolerance: .standard, maximumSourceDepth: 4, maximumSubdivisionDepth: 4,
            maximumAlgebraicDepth: 0, usage: &caller)
        #expect(caller.work > 7 && caller.storage > 11)
        guard case .parameterImage(let image) = selected else { Issue.record("Expected original selected chart."); return }
        #expect(image.source == basis)
        #expect(image.parameterGain == .ratio(numerator: Double.pi, denominator: 180))

        var refused = SelectionAdmission(maximumStorage: 0)
        #expect(throws: IndependentShapeSourceError.self) {
            _ = try IndependentShapeAngularCurveSelection.foreignCurve(basis: basis, law: law,
                tolerance: .standard, maximumSourceDepth: 4, maximumSubdivisionDepth: 4,
                maximumAlgebraicDepth: 0, usage: &refused)
        }
        #expect(refused.work > 0 && refused.storage == 0)
        var cancelled = SelectionAdmission(cancelled: true)
        #expect(throws: CancellationError.self) {
            _ = try IndependentShapeAngularCurveSelection.foreignCurve(basis: basis, law: law,
                tolerance: .standard, maximumSourceDepth: 4, maximumSubdivisionDepth: 4,
                maximumAlgebraicDepth: 0, usage: &cancelled)
        }
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
