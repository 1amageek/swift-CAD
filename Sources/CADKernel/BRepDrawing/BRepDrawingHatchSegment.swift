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
        try sourceSnapshot.validateCurrent(evaluated)
    }
    public func validateCurrent(_ evaluated: EvaluatedDocument, for section: BRepDrawingSection) throws {
        try section.validateCurrent(evaluated)
        try sourceSnapshot.validateCurrent(evaluated)
        guard sectionIdentity === section.publicationIdentity, placement == section.placement else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: evaluated.configuration.tolerance,
                message: "Section publication mixes different source planes or authored occurrences.")
        }
    }
    /// Retains the original world row curve under the same caller publication ledger.
    public func originalCurve<B: RationalAlgebraAdmitting>(in evaluated: EvaluatedDocument,
        for section: BRepDrawingSection, maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int,
        usage: inout B) throws -> Curve3D {
        try validateCurrent(evaluated, for: section)
        try start.validate(); try end.validate()
        let tolerance = evaluated.configuration.tolerance
        guard start != end else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A hatch curve requires distinct original chart endpoints.")
        }
        func storage(_ count: Int, _ stride: Int) throws -> Int {
            let bytes = count.multipliedReportingOverflow(by: stride)
            let rounded = bytes.partialValue.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
            guard count >= 0, !bytes.overflow, !rounded.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original hatch curve storage count overflowed.")
            }
            return rounded.partialValue / MemoryLayout<UInt32>.stride
        }
        try usage.consumeExactWork(1)
        try usage.retainExactStorage(storage(2, MemoryLayout<Point2D>.stride))
        try usage.retainExactStorage(storage(6, MemoryLayout<Double>.stride))
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
                maximumDepth: 0, usage: &usage)
        }
        try usage.retainExactStorage(storage(1, MemoryLayout<SurfaceLiftCurve3D>.stride))
        let lift = SurfaceLiftCurve3D(surface: .plane(plane), parameterCurve: chart)
        try usage.retainExactStorage(storage(1, MemoryLayout<OriginalAffineWordCurve3D>.stride))
        return .originalAffineWord(try OriginalAffineWordCurve3D(source: .surfaceLift(lift),
            operationWord: word, tolerance: tolerance, remainingSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage))
    }

}
