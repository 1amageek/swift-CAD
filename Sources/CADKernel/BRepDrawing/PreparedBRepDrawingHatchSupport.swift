import CADCore
import CADGeometry
import CADTopology

/// Retains the original cutting UV-to-world word for all hatch rows and witnesses.
struct PreparedBRepDrawingHatchSupport {
    let chartWord: OriginalAffineOperationWord
    let preparedChart: PreparedOriginalAffineOperationWord
    let maximumSourceDepth: Int
    let maximumSubdivisionDepth: Int
    let maximumAlgebraicDepth: Int

    init(_ support: BRepDrawingCuttingSupport, tolerance: ModelingTolerance,
         maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int,
         using execution: inout OriginalQueryExecution) throws {
        guard maximumSourceDepth > 0, maximumSourceDepth <= 16,
              maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32,
              maximumAlgebraicDepth >= 0, maximumAlgebraicDepth <= 32 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original hatch source, subdivision or algebra capabilities are invalid.")
        }
        self.maximumSourceDepth = maximumSourceDepth; self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        try execution.consumeWork(1)
        try support.originalPlane.validate(tolerance: tolerance)
        let basis = try support.originalPlane.parameterBasis(tolerance: tolerance)
        let origin = support.originalPlane.origin
        let chart = try AffineTransform3D(basisX: basis.u, basisY: basis.v, basisZ: support.originalPlane.normal,
            translation: .init(x: origin.x, y: origin.y, z: origin.z))
        let count = support.operationWord.factors.count.addingReportingOverflow(1)
        guard !count.overflow else { throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
            tolerance: tolerance, message: "Original hatch factor count overflowed.") }
        var factors: [OriginalAffineOperation] = []; try OriginalParameterQueryStorage.reserve(count.partialValue, in: &factors, using: &execution)
        factors.append(.forward(chart))
        for factor in support.operationWord.factors { try execution.consumeWork(1); factors.append(factor) }
        chartWord = try OriginalAffineOperationWord(factors: factors, tolerance: tolerance,
            maximumDepth: maximumAlgebraicDepth, usage: &execution)
        preparedChart = try chartWord.prepared(usage: &execution)
    }

    func row(at y: Double, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Surface3D {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalAffineWordSurface3D.self))
        let original = Plane3D(origin: .init(x: 0, y: y, z: 0), normal: .unitY, uDirection: .unitX)
        return .procedural(.originalAffineWord(try OriginalAffineWordSurface3D(source: .plane(original),
            operationWord: chartWord, tolerance: tolerance, remainingSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &execution)))
    }

    func point(u: Double, v: Double, using execution: inout OriginalQueryExecution) throws -> Point3D {
        try preparedChart.applying(to: .init(x: u, y: v, z: 0), usage: &execution)
    }
}
