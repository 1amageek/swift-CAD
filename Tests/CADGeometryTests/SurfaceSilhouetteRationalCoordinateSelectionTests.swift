import Testing
import CADCore
@testable import CADGeometry

@Suite("Silhouette rational coordinate source selection")
struct SurfaceSilhouetteRationalCoordinateSelectionTests {
    enum SelectionCase: CaseIterable, Equatable, Sendable {
        case affineU, affineV, linearUThroughOrigin
        case zero, constant, mixed, twoLinearAxes, repeatedOriginal

        var expectedAxis: OriginalSurfaceSilhouetteCurve.FreeCoordinate? {
            switch self {
            case .affineU, .linearUThroughOrigin: .u
            case .affineV: .v
            default: nil
            }
        }
    }

    @Test(arguments: SelectionCase.allCases)
    func actualNativeSourceRetainsOnlyItsAdmittedRationalLaw(_ selection: SelectionCase) throws {
        var usage = OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
        let surface = Surface3D.bSpline(nativeSource(selection))
        let box = SurfaceParameterBox(u: try .init(lower: 0, upper: 1),
            v: try .init(lower: 0, upper: 1))
        let view: Vector3D = selection == .affineV ? .unitY : .unitX
        try surface.validateOriginalSource(tolerance: .standard, remainingSourceDepth: 16,
            maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32, using: &usage)
        let sourceAuthority = try SurfaceSilhouetteSourcePreparation(original: surface,
            tolerance: .standard, usage: &usage)
        let source = try #require(sourceAuthority.nativeSource)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
            tolerance: sourceAuthority.nativeTolerance, using: &usage)
        let spans = try prepared.originalNativeSpans(over: box, tolerance: sourceAuthority.nativeTolerance,
            maximumSpanCount: 4, using: &usage)
        #expect(spans.count == 1)
        let span = try #require(spans.first)
        let original = try OriginalSurfaceSilhouetteField(surface: surface, domain: box,
            view: view, tolerance: .standard, sourceAuthority: sourceAuthority,
            native: span, usage: &usage)
        let authority = try #require(original.zeroSetAuthority)
        let selectionWork = authority.original.originalCoefficients.count
            + authority.squareFree.originalCoefficients.count
        let before = usage.budget.snapshot.work
        let selected = try original.retainingCommonOriginalFieldAuthority(usage: &usage)
        let consumed = usage.budget.snapshot.work - before
        #expect(selected.surface == surface)
        #expect(selected.domain == box)
        #expect(selected.view == view)
        #expect(selected.tolerance == .standard)

        if let axis = selection.expectedAxis {
            #expect(consumed == selectionWork)
            let retained = try #require(selected.zeroSetAuthority)
            #expect(retained.original == authority.original)
            #expect(retained.squareFree == authority.squareFree)
            #expect(selected.fieldZeroSetAuthority == nil)
            let jet = try selected.evaluate(over: box, usage: &usage)
            let regular = try selected.normalIsRegular(over: box, original: jet.spatial, usage: &usage)
            #expect(regular)
            #expect((axis == .u ? jet.scalar.u : jet.scalar.v).excludesZero)
            let station = try ExactRationalCoefficient.originalDouble(
                selection == .linearUThroughOrigin ? 0 : 0.5, usage: &usage)
            let zero = try retained.squareFree.evaluated(atU: axis == .u ? station : .zero,
                v: axis == .v ? station : .zero, usage: &usage)
            #expect(zero.isZero)
        } else {
            #expect(consumed >= selectionWork)
            #expect(selected.zeroSetAuthority == nil)
            let common = try #require(selected.fieldZeroSetAuthority)
            #expect(common.original.isZero == authority.original.isZero)
            if selection == .zero {
                // Canonical zero is the empty coefficient set; neither is an affine capability.
                #expect(authority.original.originalCoefficients.isEmpty)
                #expect(authority.squareFree.originalCoefficients.isEmpty)
            }
            if selection == .repeatedOriginal {
                // The actual cubic native source has F proportional to U squared.
                #expect(authority.original.uDegree == 2)
                #expect(authority.squareFree.uDegree == 1)
            }
        }
    }

    private func nativeSource(_ selection: SelectionCase) -> BSplineSurface3D {
        let heights: [[Double]]
        switch selection {
        case .affineU: heights = [[0.25, -0.25, 0.25], [0.25, -0.25, 0.25]]
        case .affineV: heights = [[0.25, 0.25], [-0.25, -0.25], [0.25, 0.25]]
        case .linearUThroughOrigin: heights = [[0, 0, 1], [0, 0, 1]]
        case .zero: heights = [[0, 0], [0, 0]]
        case .constant: heights = [[0, 1], [0, 1]]
        case .mixed: heights = [[0, 0, 0], [0, 0, 1]]
        case .twoLinearAxes: heights = [[0, 0, 0.5], [0, 0.5, 1.5]]
        case .repeatedOriginal: heights = [[0, 0, 0, 1], [0, 0, 0, 1]]
        }
        let uDegree = heights[0].count - 1, vDegree = heights.count - 1
        let points = heights.enumerated().map { v, row in
            row.enumerated().map { u, z in
                Point3D(x: Double(u) / Double(uDegree), y: Double(v) / Double(vDegree), z: z)
            }
        }
        return BSplineSurface3D(uDegree: uDegree, vDegree: vDegree,
            uKnots: Array(repeating: 0, count: uDegree + 1) + Array(repeating: 1, count: uDegree + 1),
            vKnots: Array(repeating: 0, count: vDegree + 1) + Array(repeating: 1, count: vDegree + 1),
            controlPoints: points)
    }
}
