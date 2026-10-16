import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Borrows one selected invocation's admission while retaining original stations.
package struct OriginalBoundedSelectionAngleResolver: Sendable {
    let tolerance: ModelingTolerance
    let maximumSubdivisionDepth: Int
    let remainingSourceDepth: Int
    let maximumAlgebraicDepth: Int

    package init(tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int) {
        self.tolerance = tolerance; self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.remainingSourceDepth = remainingSourceDepth; self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    package func resolve(_ selection: SelectionReference, in document: EvaluatedDocument, using execution: inout OriginalQueryExecution)
        throws -> (point: SelectionMeasurementPoint, bounds: CoordinateEnclosure3D) {
        try tolerance.validate(); try execution.consumeWork(1)
        guard (0...32).contains(maximumSubdivisionDepth), (0...16).contains(remainingSourceDepth),
            (0...32).contains(maximumAlgebraicDepth) else { throw failure() }
        switch selection {
        case .subshape(let stable):
            let resolved: SelectionReference
            switch try document.originalTopologyReference(for: stable, tolerance: tolerance,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution) {
            case .edge: resolved = .edge(.whole(EdgeReference(subshape: stable)))
            case .face: resolved = .surface(.whole(SurfaceReference(subshape: stable)))
            case .body, .vertex: throw failure()
            }
            var result = try resolve(resolved, in: document, using: &execution)
            result.point.selection = selection
            return result
        case .edge(let reference):
            let query = EdgeQueryEvaluator(tolerance: tolerance)
            let edge: EdgeReference
            switch reference { case .whole(let value): edge = value; case .parameter(let value): edge = value.edge }
            let source = try query.resolveOriginalGeometry(edge, in: document,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            let station: Double
            switch reference {
            case .whole: station = try middle(source.startParameter, source.endParameter, using: &execution)
            case .parameter(let value): station = value.parameter
            }
            guard try source.contains(parameter: station, tolerance: tolerance) else { throw failure() }
            return try curve(source.curve, station: station,
                sign: source.endParameter < source.startParameter ? -1 : 1, selection: selection, using: &execution)
        case .curve(let reference):
            let query = CurveQueryEvaluator(tolerance: tolerance)
            let output: CurveOutputReference
            switch reference {
            case .whole(let value): output = value
            case .parameter(let value): output = value.curve
            case .span(let value): output = value.curve
            case .knot(let value): output = value.curve
            case .center, .controlPoint: throw failure()
            }
            let source = try query.resolveOriginalGeometry(output, in: document,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            let station: Double
            switch reference {
            case .whole:
                if case .unbounded = source.parameterDomain {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): The public whole-angle
                    // selector on unbounded outputs preserves its paid display
                    // Euclidean-clock proposal followed by original support
                    // projection. The bounded projection receipt is not ready;
                    // averaging authored native endpoints changes that selector.
                    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "Original unbounded whole-angle station needs its admitted support projection.")
                }
                station = try middle(source.startParameter, source.endParameter, using: &execution)
            case .parameter(let value): station = value.parameter
            case .span(let value):
                let span = try query.spanOriginal(value, source: source,
                    remainingSourceDepth: remainingSourceDepth, using: &execution)
                station = try middle(span.lowerParameter, span.upperParameter, using: &execution)
            case .knot(let value): station = try query.knotOriginal(value, source: source,
                remainingSourceDepth: remainingSourceDepth, using: &execution)
            case .center, .controlPoint: throw failure()
            }
            guard try source.parameterDomain.contains(station, tolerance: tolerance) else { throw failure() }
            return try curve(source.curve, station: station, sign: 1, selection: selection, using: &execution)
        case .surface(.parameter(let station)):
            let source = try SurfaceQueryEvaluator(tolerance: tolerance).resolveOriginalGeometry(
                station.surface, in: document, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            return try surface(source, station: SurfaceParameter(u: station.u, v: station.v),
                selection: selection, in: document, using: &execution)
        case .surface(.trim(let trim)):
            let source = try SurfaceQueryEvaluator(tolerance: tolerance).trimOriginal(trim,
                in: document, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            return try curve(source.liftedCurve, station: 0.5, sign: 1, selection: selection, using: &execution)
        case .surface:
            // FIXME(INCOMPLETE_IMPLEMENTATION): The bounded public angle route
            // still needs the original representative-face projection and exact
            // trim station clock producers. Their legacy preparations cannot
            // publish a complete caller-admitted result or a UV-midpoint substitute.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original representative face or trim station preparation is not yet caller bounded.")
        case .sketchPoint: throw failure()
        }
    }

    private func curve(_ source: Curve3D, station: Double, sign: Double,
        selection: SelectionReference, using execution: inout OriginalQueryExecution) throws -> (point: SelectionMeasurementPoint, bounds: CoordinateEnclosure3D) {
        let prepared = try PreparedCurveDifferentialEncloser(curve: source, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let range = try ScalarInterval(lower: station, upper: station)
        let original = try prepared.closedNativeJets(over: range, tolerance: tolerance,
            maximumSpanCount: 1_048_576, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
        var x: OutwardScalarInterval?, y: OutwardScalarInterval?, z: OutwardScalarInterval?
        let precedingPolyline: Bool
        if case .originalPolyline = source { precedingPolyline = true } else { precedingPolyline = false }
        for owner in original.spans {
            try execution.consumeWork(1)
            if precedingPolyline { guard let _ = owner.originalPolylineOwner else { throw failure() } }
            x = x.map { $0.union(owner.jet.x.derivativeU) } ?? owner.jet.x.derivativeU
            y = y.map { $0.union(owner.jet.y.derivativeU) } ?? owner.jet.y.derivativeU
            z = z.map { $0.union(owner.jet.z.derivativeU) } ?? owner.jet.z.derivativeU
            if precedingPolyline { break }
        }
        guard let x, let y, let z else { throw failure() }
        let bounds = try OriginalSelectionAngleBounds.scaled(.init(x: .init(lower: x.lower, upper: x.upper),
            y: .init(lower: y.lower, upper: y.upper), z: .init(lower: z.lower, upper: z.upper)), sign: sign,
            using: &execution)
        let position = try prepared.positionBounds(over: range, tolerance: tolerance,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
        return try result(position: position, direction: bounds, normal: false, selection: selection, using: &execution)
    }

    private func surface(_ source: ResolvedOriginalSurfaceGeometry, station: SurfaceParameter,
        selection: SelectionReference, in document: EvaluatedDocument, using execution: inout OriginalQueryExecution)
        throws -> (point: SelectionMeasurementPoint, bounds: CoordinateEnclosure3D) {
        let box = SurfaceParameterBox(u: try .init(lower: station.u, upper: station.u),
            v: try .init(lower: station.v, upper: station.v))
        let prepared = try PreparedSurfaceDifferentialEncloser(surface: source.surface, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        var support = source.surface, native = box, sourceDepth = remainingSourceDepth
        while true {
            try execution.consumeWork(1)
            switch support {
            case .procedural(.originalImage(let image)):
                guard sourceDepth > 0 else { throw failure() }; sourceDepth -= 1
                try execution.admitSourceDepth(remainingSourceDepth - sourceDepth)
                native = try image.nativeBox(native, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
                support = image.source
            case .procedural(.originalAffineWord(let image)):
                guard sourceDepth > 0 else { throw failure() }; sourceDepth -= 1; try execution.admitSourceDepth(remainingSourceDepth - sourceDepth); support = image.source
            default: break
            }
            if case .procedural(.originalImage) = support { continue }
            if case .procedural(.originalAffineWord) = support { continue }
            break
        }
        var nappe: OriginalAnalyticPoleNormal.ConeNappe?
        if case .analytic(.cone) = support, native.v.lower == 0, native.v.upper == 0 {
            var extent = try FaceParameterExtentResolver(maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth).bounds(for: source.faceID, in: document.brep, tolerance: tolerance, using: &execution)
            var extentSource = source.surface, depth = remainingSourceDepth
            while true {
                try execution.consumeWork(1)
                switch extentSource {
                case .procedural(.originalImage(let image)):
                    guard depth > 0 else { throw failure() }; depth -= 1
                    try execution.admitSourceDepth(remainingSourceDepth - depth)
                    extent = try image.nativeBox(extent, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
                    extentSource = image.source
                case .procedural(.originalAffineWord(let image)):
                    guard depth > 0 else { throw failure() }; depth -= 1; try execution.admitSourceDepth(remainingSourceDepth - depth); extentSource = image.source
                default: break
                }
                if case .procedural(.originalImage) = extentSource { continue }
                if case .procedural(.originalAffineWord) = extentSource { continue }
                break
            }
            if extent.v.lower >= 0, extent.v.upper > 0 { nappe = .positive }
            else if extent.v.upper <= 0, extent.v.lower < 0 { nappe = .negative }
            else { throw failure() }
        }
        let normal = try prepared.unitNormalBounds(over: box, tolerance: tolerance,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, coneNappe: nappe,
            storageByteStride: MemoryLayout<UInt32>.stride, using: &execution)
        let bounds = CoordinateEnclosure3D(x: try .init(lower: normal.x.lower, upper: normal.x.upper),
            y: try .init(lower: normal.y.lower, upper: normal.y.upper),
            z: try .init(lower: normal.z.lower, upper: normal.z.upper))
        let position = try prepared.positionBounds(over: box, tolerance: tolerance,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
        return try result(position: position, direction: bounds, normal: true, selection: selection, using: &execution)
    }

    private func result(position: IntervalVector3DBounds, direction: CoordinateEnclosure3D,
        normal: Bool, selection: SelectionReference, using execution: inout OriginalQueryExecution)
        throws -> (point: SelectionMeasurementPoint, bounds: CoordinateEnclosure3D) {
        try execution.consumeWork(1)
        let point = Point3D(x: position.x.midpoint, y: position.y.midpoint, z: position.z.midpoint)
        try point.validate()
        let vector = try OriginalSelectionAngleBounds.representative(direction, tolerance: tolerance,
            using: &execution)
        return (SelectionMeasurementPoint(selection: selection, point: point,
            tangent: normal ? nil : vector, normal: normal ? vector : nil), direction)
    }

    private func middle(_ first: Double, _ last: Double, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let result = first * 0.5 + last * 0.5
        guard result.isFinite else { throw failure() }
        return result
    }
    private func failure() -> KernelError {
        .init(phase: .validation, code: .invalidInput, tolerance: tolerance,
            message: "Original selected angle requires valid independent ceilings and a nonzero station direction.")
    }
}
