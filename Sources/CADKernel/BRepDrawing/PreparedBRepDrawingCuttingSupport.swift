import CADCore
import CADGeometry
import CADTopology

/// Exact original chart recovery and finite boundary construction for one cut.
struct PreparedBRepDrawingCuttingSupport {
    let source: BRepDrawingCuttingSupport
    let image: OriginalAffineWordSurface3D
    let worldInverse: PreparedOriginalAffineOperationWord
    let chartInverse: PreparedOriginalAffineOperationWord
    let maximumSourceDepth: Int
    let maximumSubdivisionDepth: Int
    var usage: BRepDrawingCuttingAdmission

    init(_ source: BRepDrawingCuttingSupport, tolerance: ModelingTolerance,
         maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int,
         usage: BRepDrawingCuttingAdmission) throws {
        guard !source.sourceIdentity.isEmpty, maximumSourceDepth > 0, maximumSourceDepth <= 16,
              maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32,
              maximumAlgebraicDepth >= 0, maximumAlgebraicDepth <= 32 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original cutting support identity or depth capabilities are invalid.")
        }
        self.source = source; self.maximumSourceDepth = maximumSourceDepth
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        var admission = usage
        try admission.consume(work: 1, bytes: source.sourceIdentity.utf8.count)
        try source.originalPlane.validate(tolerance: tolerance)
        try admission.retain(1, of: OriginalAffineWordSurface3D.self)
        image = try OriginalAffineWordSurface3D(source: .plane(source.originalPlane),
            operationWord: source.operationWord, tolerance: tolerance, remainingSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
            usage: &admission)
        let inverse = try source.operationWord.inverted(tolerance: tolerance,
            maximumDepth: maximumAlgebraicDepth, usage: &admission)
        worldInverse = try inverse.prepared(usage: &admission)
        let basis = try source.originalPlane.parameterBasis(tolerance: tolerance)
        let origin = source.originalPlane.origin
        let chart = try AffineTransform3D(basisX: basis.u, basisY: basis.v, basisZ: source.originalPlane.normal,
            translation: Vector3D(x: origin.x, y: origin.y, z: origin.z))
        let chartWord = try OriginalAffineOperationWord(operation: .inverse(chart), tolerance: tolerance,
            maximumDepth: maximumAlgebraicDepth, usage: &admission)
        chartInverse = try chartWord.prepared(usage: &admission)
        self.usage = admission
    }

    mutating func parameters(over world: CoordinateEnclosure3D) throws -> CoordinateEnclosure3D {
        let local = try worldInverse.enclosure(of: world, isPosition: true, usage: &usage)
        return try chartInverse.enclosure(of: local, isPosition: true, usage: &usage)
    }

    mutating func edges(u: ScalarInterval, v: ScalarInterval, tolerance: ModelingTolerance) throws -> [BRepSewingEdge] {
        try usage.consume(work: 4)
        try usage.retain(4, of: BRepSewingEdge.self)
        var output: [BRepSewingEdge] = []; output.reserveCapacity(4)
        for index in 0..<4 {
            let chart: SurfaceParameterCurve
            switch index {
            case 0: chart = .constantV(v: v.lower, uStart: u.lower, uEnd: u.upper)
            case 1: chart = .constantU(u: u.upper, vStart: v.lower, vEnd: v.upper)
            case 2: chart = .constantV(v: v.upper, uStart: u.upper, uEnd: u.lower)
            default: chart = .constantU(u: u.lower, vStart: v.upper, vEnd: v.lower)
            }
            let lift = SurfaceLiftCurve3D(surface: image.source, parameterCurve: chart)
            try usage.retain(1, of: OriginalAffineWordCurve3D.self)
            let curve = try OriginalAffineWordCurve3D(source: .surfaceLift(lift),
                operationWord: source.operationWord, tolerance: tolerance,
                remainingSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
            try usage.retain(1, of: OriginalAffineWordSurfaceParameterCurve.self)
            let pcurve = try OriginalAffineWordSurfaceParameterCurve(source: lift, target: image, tolerance: tolerance,
                remainingSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage)
            try usage.consume(work: 2)
            let start = try image.point(u: index == 0 || index == 3 ? u.lower : u.upper,
                v: index < 2 ? v.lower : v.upper, tolerance: tolerance, usage: &usage)
            let end = try image.point(u: index == 0 || index == 1 ? u.upper : u.lower,
                v: index == 0 || index == 3 ? v.lower : v.upper, tolerance: tolerance, usage: &usage)
            output.append(BRepSewingEdge(stableID: "drawing:original-cut:edge:\(index)",
                curve: .originalAffineWord(curve), startParameter: 0, endParameter: 1,
                startPoint: start, endPoint: end, surfaceParameterCurve: .originalAffineWord(pcurve)))
        }
        return output
    }
}
