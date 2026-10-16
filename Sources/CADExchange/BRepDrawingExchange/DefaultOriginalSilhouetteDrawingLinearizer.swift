import CADCore
import CADGeometry
import CADKernel

/// Complete original D0 boxes certify chords, including singular stations and endpoint uncertainty.
public struct DefaultOriginalSilhouetteDrawingLinearizer: OriginalSilhouetteDrawingLinearizing {
    public init() {}
    public func linearize(_ span: BRepDrawingExactSilhouetteSpan, pointsPerMeter: Double, translation: Point2D,
        maximumDeviation: Double, maximumParameterWidth: ExactRationalCoefficient,
        admission: DrawingSilhouetteAdmission, usage: DrawingExchangeOwner,
        silhouetteContext: SurfaceSilhouetteContext, using execution: inout OriginalQueryExecution) throws -> OriginalSilhouetteDrawingPath {
        return try silhouetteContext.withExecution(using: &execution) { execution in
        try usage.validateExecution(execution)
        guard pointsPerMeter.isFinite, pointsPerMeter > 0, translation.x.isFinite, translation.y.isFinite,
            maximumDeviation.isFinite, maximumDeviation > 0, maximumParameterWidth.isPositive,
            admission.belongsToSameInvocation(as: usage, silhouetteContext: silhouetteContext) else {
            throw ExportError.invalidMesh("Original silhouette paper map, precision or invocation owner is invalid.")
        }
        let resources = usage.resources
        func paperBox(_ a: Double, _ b: Double, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
            try resources.checkTime()
            let box = try span.projectedEnclosure(overNormalized: .init(lower: a, upper: b),
                maximumParameterWidth: maximumParameterWidth, using: &execution)
            let x = OutwardScalarInterval(lower: box.x.lower, upper: box.x.upper) * .exact(pointsPerMeter) + .exact(translation.x)
            let y = OutwardScalarInterval(lower: box.y.lower, upper: box.y.upper) * .exact(pointsPerMeter) + .exact(translation.y)
            guard x.isFinite, y.isFinite else { throw ExportError.invalidMesh("Original silhouette paper enclosure is nonfinite.") }
            return .init(x: try .init(lower: x.lower, upper: x.upper), y: try .init(lower: y.lower, upper: y.upper),
                z: try .init(lower: 0, upper: 0))
        }
        func proposal(_ t: Double, using execution: inout OriginalQueryExecution) throws -> Point2D {
            let box = try paperBox(t,t,using: &execution)
            let point = Point2D(x: box.x.midpoint, y: box.y.midpoint)
            guard point.x.isFinite, point.y.isFinite else { throw ExportError.invalidMesh("Original silhouette chord endpoint is nonfinite.") }
            return point
        }
        let first = try proposal(0, using: &execution), last = try proposal(1, using: &execution)
        try usage.charge(entities: 1, bytes: MemoryLayout<OriginalSilhouetteDrawingPath.Sample>.stride)
        var samples = [OriginalSilhouetteDrawingPath.Sample(normalizedParameter: 0, point: first)]
        typealias Pending = (Double, Double, Point2D, Point2D, Int)
        try usage.charge(entities: 1, bytes: MemoryLayout<Pending>.stride)
        var pending: [Pending] = [(0,1,first,last,0)]
        while let (a,b,pa,pb,depth) = pending.popLast() {
            try usage.charge(work: 1)
            let box = try paperBox(a,b,using: &execution)
            let bound = try DrawingChordBoxBound.upperBound(box, from: pa, to: pb, usage: usage, using: &execution)
            if bound <= maximumDeviation {
                try usage.charge(entities: 1, bytes: MemoryLayout<OriginalSilhouetteDrawingPath.Sample>.stride)
                samples.append(.init(normalizedParameter: b, point: pb))
            } else {
                guard depth < usage.maximumCurveSubdivisionDepth, depth < silhouetteContext.maximumDepth else {
                    throw ExportError.invalidMesh("Original silhouette chord exceeds caller precision, deviation or subdivision allowance.")
                }
                let middle = a * 0.5 + b * 0.5
                guard middle > a, middle < b else { throw ExportError.invalidMesh("Original silhouette normalized station resolution is exhausted.") }
                let point = try proposal(middle, using: &execution)
                try usage.charge(entities: 2, bytes: 2 * MemoryLayout<Pending>.stride)
                pending.append((middle,b,point,pb,depth+1)); pending.append((a,middle,pa,point,depth+1))
            }
        }
        try usage.charge(entities: 1, work: 1, bytes: MemoryLayout<OriginalSilhouetteDrawingPath>.stride)
        return .init(span: span, pointsPerMeter: pointsPerMeter, translation: translation,
            maximumDeviation: maximumDeviation, maximumParameterWidth: maximumParameterWidth, samples: samples,
            accountingOwner: usage, silhouetteOwner: silhouetteContext, admission: admission)

        }
    }
}
