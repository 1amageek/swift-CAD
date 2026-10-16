import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct BRepDrawingHatchSegment: Sendable {
    public let bodyID: BodyID
    public let materialID: MaterialID?
    public let row: Int
    public let start: Point2D
    public let end: Point2D
    public let placement: BRepDrawingPlacement?
    internal let sectionIdentity: BRepDrawingSectionAuthority
    internal let sourceSnapshot: BRepDrawingSourceSnapshot

    init(bodyID: BodyID, materialID: MaterialID?, row: Int, start: Point2D, end: Point2D,
         sourceSnapshot: BRepDrawingSourceSnapshot, sectionIdentity: BRepDrawingSectionAuthority, placement: BRepDrawingPlacement? = nil) {
        self.bodyID = bodyID; self.materialID = materialID; self.row = row
        self.start = start; self.end = end; self.sourceSnapshot = sourceSnapshot; self.placement = placement; self.sectionIdentity = sectionIdentity
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateCurrent(evaluated, using: &execution)
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try sourceSnapshot.validateCurrent(evaluated, using: &execution)
    }
    public func validateCurrent(_ evaluated: EvaluatedDocument, for section: BRepDrawingSection) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateCurrent(evaluated, for: section, using: &execution)
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument, for section: BRepDrawingSection, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try section.validateCurrent(evaluated, using: &execution)
        try sourceSnapshot.validateCurrent(evaluated, using: &execution)
        guard sectionIdentity === section.publicationIdentity, try BRepDrawingPlacementComparison.equal(placement, section.placement, using: &execution) else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: evaluated.configuration.tolerance,
                message: "Section publication mixes different source planes or authored occurrences.")
        }
    }
    /// Retains the original world row curve under the same caller publication ledger.
    public func originalCurve(in evaluated: EvaluatedDocument,
        for section: BRepDrawingSection, maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> Curve3D {
        try validateCurrent(evaluated, for: section, using: &execution)
        let tolerance = evaluated.configuration.tolerance
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original hatch chart requires finite endpoints.")
        }
        guard start != end else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A hatch curve requires distinct original chart endpoints.")
        }
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Point2D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
        let chart = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [start, end], weights: [1, 1]))
        let plane: Plane3D
        let word: OriginalAffineOperationWord
        if let support = section.cuttingSupport {
            plane = support.originalPlane; word = support.operationWord
        } else {
            plane = Plane3D(origin: .origin, normal: .unitZ, uDirection: .unitX)
            let frame = section.frame
            let transform = try AffineTransform3D(basisX: frame.horizontal, basisY: frame.vertical,
                basisZ: frame.normal, translation: Vector3D(x: frame.origin.x, y: frame.origin.y, z: frame.origin.z))
            word = try OriginalAffineOperationWord(operation: .forward(transform), tolerance: tolerance,
                maximumDepth: 0, usage: &execution)
        }
        try execution.retainStorage(bytes: MemoryLayout<SurfaceLiftCurve3D>.stride)
        let lift = SurfaceLiftCurve3D(surface: .plane(plane), parameterCurve: chart)
        try execution.retainStorage(bytes: MemoryLayout<OriginalAffineWordCurve3D>.stride)
        return .originalAffineWord(try OriginalAffineWordCurve3D(source: .surfaceLift(lift),
            operationWord: word, tolerance: tolerance, remainingSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution))
    }

}
