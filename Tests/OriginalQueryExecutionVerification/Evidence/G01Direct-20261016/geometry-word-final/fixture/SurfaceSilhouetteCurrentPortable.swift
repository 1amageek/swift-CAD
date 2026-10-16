import CADCore
import Synchronization
@testable import CADGeometry

/// Actual Geometry-only controls for the current silhouette source and retained trim path.
@main
struct SurfaceSilhouetteCurrentPortable {
    enum Failure: Error { case mismatch, missingRefusal }

    static func require(_ condition: Bool, line: UInt32 = #line) throws {
        guard condition else {
            print("FAIL current silhouette portable oracle line=\(line)")
            throw Failure.mismatch
        }
    }

    static func unwrap<Value>(_ value: Value?, line: UInt32 = #line) throws -> Value {
        guard let value else {
            print("FAIL current silhouette portable missing value line=\(line)")
            throw Failure.mismatch
        }
        return value
    }

    static func originalFailure(_ error: any Error) -> any Error {
        if let retained = error as? OriginalQueryFailure { return originalFailure(retained.originalError) }
        if case .admissionRejected(let retained)? = error as? ExactScalarFailure {
            return originalFailure(retained)
        }
        return error
    }

    static func expectFailure<Result>(_ predicate: (any Error) -> Bool,
        _ operation: () throws -> Result) throws {
        do { _ = try operation() }
        catch {
            guard predicate(error) else { throw error }
            return
        }
        throw Failure.missingRefusal
    }

    static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: 16, maximumTransportDepth: 16,
            maximumSubdivisionDepth: 32, maximumSpans: 64))
    }

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

    static func actualNativeSourceRetainsOnlyItsAdmittedRationalLaw(_ selection: SelectionCase) throws {
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
        let source = try unwrap(sourceAuthority.nativeSource)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
            tolerance: sourceAuthority.nativeTolerance, using: &usage)
        let spans = try prepared.originalNativeSpans(over: box, tolerance: sourceAuthority.nativeTolerance,
            maximumSpanCount: 4, using: &usage)
        try require(spans.count == 1)
        let span = try unwrap(spans.first)
        let original = try OriginalSurfaceSilhouetteField(surface: surface, domain: box,
            view: view, tolerance: .standard, sourceAuthority: sourceAuthority,
            native: span, usage: &usage)
        let authority = try unwrap(original.zeroSetAuthority)
        let selectionWork = authority.original.originalCoefficients.count
            + authority.squareFree.originalCoefficients.count
        let before = usage.budget.snapshot.work
        let selected = try original.retainingCommonOriginalFieldAuthority(usage: &usage)
        let consumed = usage.budget.snapshot.work - before
        try require(selected.surface == surface)
        try require(selected.domain == box)
        try require(selected.view == view)
        try require(selected.tolerance == .standard)

        if let axis = selection.expectedAxis {
            try require(consumed == selectionWork)
            let retained = try unwrap(selected.zeroSetAuthority)
            try require(retained.original == authority.original)
            try require(retained.squareFree == authority.squareFree)
            try require(selected.fieldZeroSetAuthority == nil)
            let jet = try selected.evaluate(over: box, usage: &usage)
            let regular = try selected.normalIsRegular(over: box, original: jet.spatial, usage: &usage)
            try require(regular)
            try require((axis == .u ? jet.scalar.u : jet.scalar.v).excludesZero)
            let station = try ExactRationalCoefficient.originalDouble(
                selection == .linearUThroughOrigin ? 0 : 0.5, usage: &usage)
            let zero = try retained.squareFree.evaluated(atU: axis == .u ? station : .zero,
                v: axis == .v ? station : .zero, usage: &usage)
            try require(zero.isZero)
        } else {
            try require(consumed >= selectionWork)
            try require(selected.zeroSetAuthority == nil)
            let common = try unwrap(selected.fieldZeroSetAuthority)
            try require(common.original.isZero == authority.original.isZero)
            if selection == .zero {
                // Canonical zero is the empty coefficient set; neither is an affine capability.
                try require(authority.original.originalCoefficients.isEmpty)
                try require(authority.squareFree.originalCoefficients.isEmpty)
            }
            if selection == .repeatedOriginal {
                // The actual cubic native source has F proportional to U squared.
                try require(authority.original.uDegree == 2)
                try require(authority.squareFree.uDegree == 1)
            }
        }
    }

    private static func nativeSource(_ selection: SelectionCase) -> BSplineSurface3D {
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

    private struct Retained {
        let curve: OriginalSurfaceSilhouetteCurve
        let trimmed: OriginalSurfaceSilhouetteTrimmedCurve
        let lower: SurfaceSilhouetteTrimPartition
        let upper: SurfaceSilhouetteTrimPartition
    }

    @inline(never)
    private static func archAndTrim(using execution: inout OriginalQueryExecution) throws -> Retained {
        let surface = Surface3D.bSpline(nativeSource(.affineU))
        let domain = SurfaceParameterBox(u: try .init(lower: 0, upper: 1),
            v: try .init(lower: 0, upper: 1))
        let producer: any SurfaceSilhouetteProducing = DefaultSurfaceSilhouetteProducer()
        let envelope = try producer.silhouette(of: surface, over: domain,
            view: .unitX, tolerance: .standard, using: &execution)
        try require(envelope.surface == surface && envelope.domain == domain && envelope.view == .unitX)
        try require(envelope.curves.count == 1 && envelope.components.count == 1)
        try require(envelope.contacts.isEmpty && envelope.algebraicContacts.isEmpty)
        try require(envelope.excludedDomains.isEmpty && envelope.coincidentDomains.isEmpty)
        let curve = try unwrap(envelope.curves.first)
        let whole = try curve.enclosure(over: curve.nativeDomain, using: &execution)
        try checkWholeArch(whole)
        // Compare both original UV coordinates, including the distinct free endpoints.
        let first = try unwrap(curve.boundaryPoint(atUpperEnd: false, usage: &execution))
        let last = try unwrap(curve.boundaryPoint(atUpperEnd: true, usage: &execution))
        let equal = try curve.boundaryRootIsSame(as: curve, atUpperEnd: false, otherAtUpperEnd: true,
            periodic: false, firstPoint: first, secondPoint: last, usage: &execution)
        try require(!equal)
        let partitions: any SurfaceSilhouetteTrimPartitionProviding = OriginalSurfaceSilhouetteTrimPartitionProducer()
        let lowerBoundary = try OriginalSurfaceSilhouetteBoundary(
            curve: .constantV(v: 0, uStart: 0, uEnd: 1), on: surface,
            maximumControlPointCount: 6, maximumBoundaryCurveCount: 4,
            tolerance: .standard, using: &execution)
        let upperBoundary = try OriginalSurfaceSilhouetteBoundary(
            curve: .constantV(v: 1, uStart: 0, uEnd: 1), on: surface,
            maximumControlPointCount: 6, maximumBoundaryCurveCount: 4,
            tolerance: .standard, using: &execution)
        let lower = try partitions.partition(curve: curve, boundary: lowerBoundary, using: &execution)
        let upper = try partitions.partition(curve: curve, boundary: upperBoundary, using: &execution)
        try require(lower.originalCurve == curve && upper.originalCurve == curve)
        try require(lower.events.count == 1 && upper.events.count == 1)
        try require(lower.overlaps.isEmpty && upper.overlaps.isEmpty)
        try require(lower.sectors.count == 1 && upper.sectors.count == 1)
        let a = try unwrap(lower.events.first), b = try unwrap(upper.events.first)
        try require(a.originalBoundarySpan == 0 && b.originalBoundarySpan == 0)
        let precision = try ExactRationalCoefficient.originalDouble(1.0 / 1024, usage: &execution)
        let firstFraction = try a.boundaryFraction.enclosure(maximumWidth: precision, using: &execution)
        let lastFraction = try b.boundaryFraction.enclosure(maximumWidth: precision, using: &execution)
        try require(firstFraction.lower <= 0.5 && firstFraction.upper >= 0.5)
        try require(lastFraction.lower <= 0.5 && lastFraction.upper >= 0.5)
        let firstUV = try a.parameter.enclosure(maximumWidth: precision, using: &execution)
        let lastUV = try b.parameter.enclosure(maximumWidth: precision, using: &execution)
        try require(firstUV.lower <= 0 && firstUV.upper < 0.25)
        try require(lastUV.lower > 0.75 && lastUV.upper >= 1)
        try require(try a.parameter.compare(to: b.parameter, using: &execution) < 0)
        let trimmed = try OriginalSurfaceSilhouetteTrimmedCurve(original: curve,
            lower: a.parameter, upper: b.parameter, using: &execution)
        let retainedWhole = try trimmed.enclosure(overNormalized: .init(lower: 0, upper: 1),
            maximumParameterWidth: .one, using: &execution)
        try checkWholeArch(retainedWhole)
        return Retained(curve: curve, trimmed: trimmed, lower: lower, upper: upper)
    }

    private static func checkWholeArch(_ whole: SurfaceSilhouetteCurveEnclosure) throws {
        // These are the unchanged Native Drawing whole-UV/XYZ enclosure oracles.
        try require(whole.parameters.u.lower <= 0.5 && whole.parameters.u.upper >= 0.5)
        try require(whole.parameters.v.lower <= 0 && whole.parameters.v.upper >= 1)
        let position = try unwrap(whole.spatialDerivatives.first)
        try require(position.x.lower <= 0.5 && position.x.upper >= 0.5)
        try require(position.y.lower <= 0 && position.y.upper >= 1)
        try require(position.z.lower <= 0 && position.z.upper >= 0)
    }

    static func resourcesLifetimeAndSourceRefusal() throws {
        let measured = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456)
        var measuring = try execution(measured)
        let retained = try archAndTrim(using: &measuring)
        let complete = measured.snapshot
        try require(complete.work > 0 && complete.storageBytes > 0)
        let exactBudget = try OriginalQueryBudget(workLimit: complete.work, storageByteLimit: complete.storageBytes)
        var exact = try execution(exactBudget)
        _ = try archAndTrim(using: &exact)
        try require(exactBudget.snapshot.work == complete.work)
        try require(exactBudget.snapshot.storageBytes == complete.storageBytes)
        for resource in [ExactResource.work, .storage] {
            let budget = try OriginalQueryBudget(workLimit: resource == .work ? complete.work - 1 : 8_388_608,
                storageByteLimit: resource == .storage ? complete.storageBytes - 1 : 268_435_456)
            var query = try execution(budget)
            try expectFailure({ error in
                guard case .resourceLimit(let actual)? = originalFailure(error) as? ExactScalarFailure else { return false }
                return actual == resource
            }) { try archAndTrim(using: &query) }
        }
        // Original source values remain retained after the producer-local input has ended.
        var caller = nativeSource(.affineU)
        caller.controlPoints[0][1].z = 99
        try require(retained.curve.surface == .bSpline(nativeSource(.affineU)))
        try require(retained.curve.surface != .bSpline(caller))
        let again = try retained.trimmed.enclosure(overNormalized: .init(lower: 0, upper: 1),
            maximumParameterWidth: .one, using: &measuring)
        try checkWholeArch(again)
        let foreign = try OriginalSurfaceSilhouetteBoundary(curve: .constantV(v: 0, uStart: 0, uEnd: 1),
            on: .bSpline(caller), maximumControlPointCount: 6, maximumBoundaryCurveCount: 4,
            tolerance: .standard, using: &measuring)
        try expectFailure({ error in
            guard let failure = originalFailure(error) as? KernelError else { return false }
            return failure.code == .intersectionFailure
        }) {
            try OriginalSurfaceSilhouetteTrimPartitionProducer().partition(
                curve: retained.curve, boundary: foreign, using: &measuring)
        }
    }

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws(ExactScalarFailure) {
            let ordinal = state.withLock { count in count += 1; return count }
            if ordinal == stop { throw .cancelled }
        }
    }

    static func cancellation() throws {
        let observer = Checkpoints()
        let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456,
            checkpoint: { try observer.checkpoint() })
        var measuring = try execution(budget)
        _ = try archAndTrim(using: &measuring)
        try require(observer.count > 1)
        for ordinal in [1, observer.count] {
            let cancellation = Checkpoints(stop: ordinal)
            let stopped = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456,
                checkpoint: { try cancellation.checkpoint() })
            var query = try execution(stopped)
            try expectFailure({ error in
                guard case .cancelled? = originalFailure(error) as? ExactScalarFailure else { return false }
                return true
            }) { try archAndTrim(using: &query) }
        }
    }

    private struct WordPacket {
        let source: Surface3D
        let word: OriginalAffineOperationWord
        let trimmed: OriginalSurfaceSilhouetteTrimmedCurve
    }

    @inline(never)
    private static func wordArch(variant: Int,
        using execution: inout OriginalQueryExecution) throws -> WordPacket {
        let transform: AffineTransform3D
        switch variant {
        case 0:
            transform = try .init(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)
        case 1:
            transform = try .init(basisX: .init(x: 2, y: 0, z: 0),
                basisY: .init(x: 0, y: 3, z: 0), basisZ: .init(x: 0, y: 0, z: 4),
                translation: .init(x: 5, y: 7, z: 11))
        default:
            // This shear changes the world-normal silhouette root from U=1/2 to U=3/8.
            transform = try .init(basisX: .init(x: 2, y: 0, z: 1),
                basisY: .init(x: 0, y: 3, z: 1), basisZ: .init(x: 1, y: 0, z: 4),
                translation: .init(x: 3, y: -2, z: 5))
        }
        let word = try OriginalAffineOperationWord(factors: [.forward(transform)],
            tolerance: .standard, maximumDepth: 32, usage: &execution)
        let image = try OriginalAffineWordSurface3D(source: .bSpline(nativeSource(.affineU)),
            operationWord: word, tolerance: .standard, remainingSourceDepth: 16,
            maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32, usage: &execution)
        let source = Surface3D.procedural(.originalAffineWord(image))
        let domain = SurfaceParameterBox(u: try .init(lower: 0, upper: 1),
            v: try .init(lower: 0, upper: 1))
        let producer: any SurfaceSilhouetteProducing = DefaultSurfaceSilhouetteProducer()
        let envelope = try producer.silhouette(of: source, over: domain,
            view: .unitX, tolerance: .standard, using: &execution)
        try require(envelope.surface == source && envelope.domain == domain)
        try require(envelope.curves.count == 1 && envelope.components.count == 1)
        try require(envelope.contacts.isEmpty && envelope.algebraicContacts.isEmpty)
        let curve = try unwrap(envelope.curves.first)
        try require(curve.surface == source)
        guard case .procedural(.originalAffineWord(let retainedImage)) = curve.surface else {
            throw Failure.mismatch
        }
        try require(retainedImage.source == .bSpline(nativeSource(.affineU)))
        try require(retainedImage.operationWord == word)
        let partitions: any SurfaceSilhouetteTrimPartitionProviding = OriginalSurfaceSilhouetteTrimPartitionProducer()
        let lowerBoundary = try OriginalSurfaceSilhouetteBoundary(
            curve: .constantV(v: 0, uStart: 0, uEnd: 1), on: source,
            maximumControlPointCount: 6, maximumBoundaryCurveCount: 4,
            tolerance: .standard, using: &execution)
        let upperBoundary = try OriginalSurfaceSilhouetteBoundary(
            curve: .constantV(v: 1, uStart: 0, uEnd: 1), on: source,
            maximumControlPointCount: 6, maximumBoundaryCurveCount: 4,
            tolerance: .standard, using: &execution)
        let lower = try partitions.partition(curve: curve, boundary: lowerBoundary, using: &execution)
        let upper = try partitions.partition(curve: curve, boundary: upperBoundary, using: &execution)
        try require(lower.events.count == 1 && upper.events.count == 1)
        let a = try unwrap(lower.events.first), b = try unwrap(upper.events.first)
        try require(try a.parameter.compare(to: b.parameter, using: &execution) < 0)
        let trimmed = try OriginalSurfaceSilhouetteTrimmedCurve(original: curve,
            lower: a.parameter, upper: b.parameter, using: &execution)
        let whole = try trimmed.enclosure(overNormalized: .init(lower: 0, upper: 1),
            maximumParameterWidth: .one, using: &execution)
        let originalU = variant == 2 ? 3.0 / 8 : 0.5
        try require(whole.parameters.u.lower <= originalU && whole.parameters.u.upper >= originalU)
        try require(whole.parameters.v.lower <= 0 && whole.parameters.v.upper >= 1)
        let position = try unwrap(whole.spatialDerivatives.first)
        let x = variant == 0 ? 0.5 : variant == 1 ? 6.0 : 241.0 / 64
        let y0 = variant == 0 ? 0.0 : variant == 1 ? 7.0 : -2.0
        let y1 = variant == 0 ? 1.0 : variant == 1 ? 10.0 : 1.0
        let z0 = variant == 0 ? 0.0 : variant == 1 ? 11.0 : 87.0 / 16
        let z1 = variant == 2 ? 103.0 / 16 : z0
        try require(position.x.lower <= x && position.x.upper >= x)
        try require(position.y.lower <= y0 && position.y.upper >= y1)
        try require(position.z.lower <= z0 && position.z.upper >= z1)
        if variant == 1 {
            // A child-chart XYZ result would be near X=1/2,Z=0 and must fail.
            try require(position.x.lower > 5 && position.x.upper < 7)
            try require(position.z.lower > 10 && position.z.upper < 12)
        } else if variant == 2 {
            try require(whole.parameters.u.upper < 0.5)
            try require(position.x.lower > 3 && position.x.upper < 4)
            try require(position.z.lower > 5)
        }
        return WordPacket(source: source, word: word, trimmed: trimmed)
    }

    static func wordSourceAndWorldReaders() throws {
        for variant in 0..<3 {
            var admission = try execution(OriginalQueryBudget(workLimit: 8_388_608,
                storageByteLimit: 268_435_456))
            let packet = try wordArch(variant: variant, using: &admission)
            for side in 0..<2 {
                let point = try packet.trimmed.enclosure(overNormalized: .init(lower: Double(side), upper: Double(side)),
                    maximumParameterWidth: .one, using: &admission)
                let world = try unwrap(point.spatialDerivatives.first)
                let x = variant == 0 ? 0.5 : variant == 1 ? 6.0 : 241.0 / 64
                let y = variant == 0 ? Double(side) : variant == 1 ? Double(side) * 3 + 7 : Double(side) * 3 - 2
                let z = variant == 0 ? 0.0 : variant == 1 ? 11.0 : Double(side) + 87.0 / 16
                try require(world.x.lower <= x && world.x.upper >= x)
                try require(world.y.lower <= y && world.y.upper >= y)
                try require(world.z.lower <= z && world.z.upper >= z)
            }
        }
    }

    static func wordProjectedEndpointContacts() throws {
        for variant in 0..<3 {
            var admission = try execution(OriginalQueryBudget(workLimit: 8_388_608,
                storageByteLimit: 268_435_456))
            let packet = try wordArch(variant: variant, using: &admission)
            let frame = try OrthographicProjectionFrame(origin: .origin, normal: .unitX,
                horizontalHint: .unitY, tolerance: .standard)
            let producer: any SurfaceSilhouetteProjectedContactProducing = OriginalNativeSilhouetteProjectedContactProducer()
            let precision = try ExactRationalCoefficient.originalDouble(1.0 / 1024, usage: &admission)
            var lowerCount = 0, upperCount = 0
            for side in 0..<2 {
                let rail = try nativeSource(.affineU).uIsoparametricCurve(atV: Double(side),
                    tolerance: .standard, using: &admission)
                let image = try OriginalAffineWordCurve3D(source: .bSpline(rail), operationWord: packet.word,
                    tolerance: .standard, remainingSourceDepth: 16, maximumSubdivisionDepth: 32,
                    maximumAlgebraicDepth: 32, usage: &admission)
                let edge = Curve3D.originalAffineWord(image)
                let partition = try producer.partition(edge: edge, spanIndex: rail.degree,
                    over: .init(lower: 0, upper: 1), silhouette: packet.trimmed,
                    frame: frame, using: &admission)
                try require(partition.originalEdge == edge)
                try require(partition.contacts.count == 1 && !partition.hasWholeRangeProjectedOverlap)
                for contact in partition.contacts {
                    try require(contact.edgeMultiplicity == 2 && !contact.coversWholeEdgeRange)
                    let station = try unwrap(contact.edgeParameter)
                    let parameter = try station.enclosure(maximumWidth: precision, using: &admission)
                    let originalU = variant == 2 ? 3.0 / 8 : 0.5
                    try require(parameter.lower <= originalU && parameter.upper >= originalU)
                    let uv = try contact.parameterEnclosure(maximumWidth: precision, using: &admission)
                    try require(uv.u.lower <= originalU && uv.u.upper >= originalU)
                    if uv.v.lower <= 0 && uv.v.upper < 0.25 { lowerCount += 1 }
                    if uv.v.lower > 0.75 && uv.v.upper >= 1 { upperCount += 1 }
                    guard case .zero = try contact.depthDifferenceSign(using: &admission) else {
                        throw Failure.mismatch
                    }
                }
            }
            try require(lowerCount == 1 && upperCount == 1)
        }
    }

    static func main() throws {
        for selection in SelectionCase.allCases {
            try actualNativeSourceRetainsOnlyItsAdmittedRationalLaw(selection)
        }
        print("PASS current silhouette eight Native source selections")
        try resourcesLifetimeAndSourceRefusal()
        print("PASS current silhouette arch whole UV and retained trim endpoints")
        print("PASS current silhouette shared resources lifetime and source refusal")
        try cancellation()
        print("PASS current silhouette entry and terminal cancellation")
        try wordSourceAndWorldReaders()
        print("PASS current silhouette original word source and world readers")
        try wordProjectedEndpointContacts()
        print("PASS current silhouette original word projected endpoint contacts")
        print("PASS current silhouette portable all")
    }
}
