import CADCore
import CADGeometry

/// Converts only original interval-certified transformed spans into paper-point chords.
public struct DefaultOriginalRootSpanDrawingLinearizer: OriginalRootSpanDrawingLinearizing {
    public init() {}
    public func linearize(_ span: OriginalCurveRootSpan3D, operationWord: OriginalAffineOperationWord,
        maximumDeviation: Double, usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution) throws -> OriginalRootSpanDrawingPath {
        return try execution.withProofScope(maximum: .init(value: usage.maximumAlgebraicDepth, coefficient: usage.maximumAlgebraicDepth)) { execution in
        guard maximumDeviation.isFinite, maximumDeviation > 0 else {
            throw ExportError.invalidMesh("Original root span requires an explicit positive paper-point deviation.")
        }
        try usage.validateExecution(execution)
        let admittedSpan = try span.admittingQueryAlgebra(usage.maximumAlgebraicDepth,
            tolerance: span.certificationTolerance, maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
            remainingSourceDepth: usage.maximumNesting,
            using: &execution)
        try operationWord.validateOriginal(tolerance: span.certificationTolerance,
            maximumDepth: usage.maximumAlgebraicDepth, usage: &execution)
        let prepared = try operationWord.prepared(usage: &execution)
        func transformed(_ a: Double, _ b: Double, derivative: Bool,
            usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
            try usage.check()
            let original = try admittedSpan.preparedIntervalJet(over: .init(lower: min(a,b), upper: max(a,b)),
                tolerance: span.certificationTolerance,
                maximumSpanCount: usage.resources.limits.maximumEntities,
                maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
                remainingSourceDepth: usage.maximumNesting, using: &execution)
            let x = derivative ? original.x.secondDerivativeUU : original.x.value
            let y = derivative ? original.y.secondDerivativeUU : original.y.value
            let z = derivative ? original.z.secondDerivativeUU : original.z.value
            let input = CoordinateEnclosure3D(x: try .init(lower: x.lower, upper: x.upper),
                y: try .init(lower: y.lower, upper: y.upper), z: try .init(lower: z.lower, upper: z.upper))
            return try prepared.enclosure(of: input, isPosition: !derivative, usage: &execution)
        }
        func proposal(_ parameter: Double, usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Point2D {
            let bounds = try transformed(parameter, parameter, derivative: false, usage: usage, using: &execution)
            guard bounds.x.lower.isFinite, bounds.x.upper.isFinite,
                bounds.y.lower.isFinite, bounds.y.upper.isFinite else {
                throw ExportError.invalidMesh("Original transformed root-span endpoint is not finite.")
            }
            return .init(x: bounds.x.midpoint, y: bounds.y.midpoint)
        }
        func endpointError(_ parameter: Double, point: Point2D,
            usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Double {
            let bounds = try transformed(parameter, parameter, derivative: false, usage: usage, using: &execution)
            return IntervalVector3DBounds(x: .init(lower: bounds.x.lower, upper: bounds.x.upper) - .exact(point.x),
                y: .init(lower: bounds.y.lower, upper: bounds.y.upper) - .exact(point.y), z: .exact(0)).lengthUpperBound
        }
        let first = try proposal(0, usage: usage, using: &execution), last = try proposal(1, usage: usage, using: &execution)
        try usage.charge(entities: 1, bytes: MemoryLayout<OriginalRootSpanDrawingPath.Sample>.stride)
        var samples = [OriginalRootSpanDrawingPath.Sample(normalizedParameter: 0, point: first)]
        typealias Pending = (Double, Double, Point2D, Point2D, Int)
        try usage.charge(entities: 1, bytes: MemoryLayout<Pending>.stride)
        var pending: [Pending] = [(0,1,first,last,0)]
        while let (a,b,pa,pb,depth) = pending.popLast() {
            try usage.charge(work: 1)
            let bound: Double
            if admittedSpan.nativeSpanIndex != nil {
                let whole = try transformed(a,b,derivative: true,usage: usage, using: &execution)
                let second = IntervalVector3DBounds(x: .init(lower: whole.x.lower, upper: whole.x.upper),
                    y: .init(lower: whole.y.lower, upper: whole.y.upper), z: .exact(0)).lengthUpperBound
                let ea = try endpointError(a, point: pa, usage: usage, using: &execution)
                let eb = try endpointError(b, point: pb, usage: usage, using: &execution)
                let width = OutwardScalarInterval.exact(b) - .exact(a)
                guard let chordError = (OutwardScalarInterval.exact(second) * width * width).divided(by: .exact(8)) else {
                    throw ExportError.invalidMesh("Original transformed root-span chord bound is not finite.")
                }
                let certified = chordError + .exact(max(ea,eb))
                guard second.isFinite, ea.isFinite, eb.isFinite, certified.isFinite else {
                    throw ExportError.invalidMesh("Original transformed root-span chord bound is not finite.")
                }
                bound = certified.upper
            } else {
                let box = try transformed(a,b,derivative: false,usage: usage, using: &execution)
                bound = try DrawingChordBoxBound.upperBound(box, from: pa, to: pb, usage: usage, using: &execution)
            }
            if bound <= maximumDeviation {
                try usage.charge(entities: 1, bytes: MemoryLayout<OriginalRootSpanDrawingPath.Sample>.stride)
                samples.append(.init(normalizedParameter: b, point: pb))
            } else {
                guard depth < usage.maximumCurveSubdivisionDepth else {
                    throw ExportError.invalidMesh("Original transformed root span exceeds the caller subdivision/deviation allowance.")
                }
                let middle = a * 0.5 + b * 0.5
                guard middle > a, middle < b else { throw ExportError.invalidMesh("Original root-span parameter resolution is exhausted.") }
                let point = try proposal(middle, usage: usage, using: &execution)
                try usage.charge(entities: 2, bytes: 2 * MemoryLayout<Pending>.stride)
                pending.append((middle,b,point,pb,depth+1)); pending.append((a,middle,pa,point,depth+1))
            }
        }
        try usage.charge(entities: 1, work: 1, bytes: MemoryLayout<OriginalRootSpanDrawingPath>.stride)
        return .init(span: admittedSpan, operationWord: operationWord, maximumDeviation: maximumDeviation, samples: samples, accountingOwner: usage)

        }
    }
}
