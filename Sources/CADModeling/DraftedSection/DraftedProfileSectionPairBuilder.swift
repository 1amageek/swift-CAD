import CADCore
import CADGeometry
import CADIR

package struct DraftedProfileSectionPairBuilder: Sendable {
    package init() {}

    /// Keeps a face section's original source authority through both drafted heights.
    package func pair(face: ResolvedFaceSection, normal: Vector3D, axis: Vector3D,
        pull: Vector3D, lowerHeight: Double, upperHeight: Double, angle: Double,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws
        -> (lower: [[ExactPrismaticBoundarySegment]], upper: [[ExactPrismaticBoundarySegment]]) {
        let loops = try ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: admission)
            .faceLoopSpans(from: face)
        return try pair(originalLoops: loops, normal: normal, axis: axis, pull: pull,
            lowerHeight: lowerHeight, upperHeight: upperHeight, angle: angle,
            tolerance: tolerance, admission: admission)
    }

    package func pair(originalCurveSpans: [ExactBSplineCurveSpan], normal: Vector3D, axis: Vector3D,
        pull: Vector3D, lowerHeight: Double, upperHeight: Double, angle: Double,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws
        -> (lower: [[ExactPrismaticBoundarySegment]], upper: [[ExactPrismaticBoundarySegment]]) {
        guard originalCurveSpans.count >= 2 else {
            throw failure(.invalidInput, "A closed original draft region requires at least two retained directed spans.", tolerance)
        }
        try admission.chargeStorage(bytes: MemoryLayout<[ExactBSplineCurveSpan]>.stride)
        return try pair(originalLoops: [originalCurveSpans], normal: normal, axis: axis, pull: pull,
            lowerHeight: lowerHeight, upperHeight: upperHeight, angle: angle,
            tolerance: tolerance, admission: admission)
    }

    private func pair(originalLoops loops: [[ExactBSplineCurveSpan]], normal: Vector3D, axis: Vector3D,
        pull: Vector3D, lowerHeight: Double, upperHeight: Double, angle: Double,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws
        -> (lower: [[ExactPrismaticBoundarySegment]], upper: [[ExactPrismaticBoundarySegment]]) {
        try admission.chargeStorage(bytes: 2 * loops.count * MemoryLayout<[ExactPrismaticBoundarySegment]>.stride)
        var lower: [[ExactPrismaticBoundarySegment]] = [], upper: [[ExactPrismaticBoundarySegment]] = []
        lower.reserveCapacity(loops.count); upper.reserveCapacity(loops.count)
        let linearity = try OriginalSweepPathLinearity(tolerance: tolerance, admission: admission)
        for loop in loops {
            try admission.chargeWork()
            try admission.chargeStorage(bytes: 3 * loop.count * MemoryLayout<ExactPrismaticBoundarySegment>.stride)
            var bottom: [ExactPrismaticBoundarySegment] = [], top: [ExactPrismaticBoundarySegment] = []
            var constructionKinds: [ExactPrismaticBoundarySegment] = []
            bottom.reserveCapacity(loop.count); top.reserveCapacity(loop.count)
            constructionKinds.reserveCapacity(loop.count)
            for span in loop {
                try admission.chargeWork()
                let raw = try span.originalChart.persistentCurve(tolerance: tolerance, admission: admission)
                let pair = try DraftedSectionPairBuilder().pair(curve: raw,
                    parameters: ScalarInterval(lower: 0, upper: 1), normal: normal, axis: axis, pull: pull,
                    lowerHeight: lowerHeight, upperHeight: upperHeight, angle: angle,
                    tolerance: tolerance, admission: admission)
                try admission.chargeStorage(bytes: MemoryLayout<ExactBSplineCurveSpan>.stride)
                if try linearity.containsOnlyLinearArms([span]) {
                    guard let lowerStart = pair.lower.controlPoints.first, let lowerEnd = pair.lower.controlPoints.last,
                        let upperStart = pair.upper.controlPoints.first, let upperEnd = pair.upper.controlPoints.last else {
                        throw failure(.invalidInput, "Drafted original line lost its certified endpoint images.", tolerance)
                    }
                    bottom.append(try .line(from: lowerStart, to: lowerEnd, tolerance: tolerance))
                    top.append(try .line(from: upperStart, to: upperEnd, tolerance: tolerance))
                    constructionKinds.append(try .line(from: span.startPoint, to: span.endPoint, tolerance: tolerance))
                } else {
                    bottom.append(try .bSpline(pair.lower, tolerance: tolerance))
                    top.append(try .bSpline(pair.upper, tolerance: tolerance))
                    constructionKinds.append(try .bSpline(span.curve, tolerance: tolerance))
                }
            }
            // These candidate endpoint images select finite construction trims
            // only. Final wall publication still requires its raw ruling source.
            lower.append(try joined(bottom, originals: constructionKinds,
                normal: OriginalDraftDirectionInputs.normalized(normal),
                tolerance: tolerance, admission: admission))
            upper.append(try joined(top, originals: constructionKinds,
                normal: OriginalDraftDirectionInputs.normalized(normal),
                tolerance: tolerance, admission: admission))
        }
        return (lower, upper)
    }

    package func pair(profile: Profile, normal: Vector3D, axis: Vector3D,
                      pull: Vector3D, lowerHeight: Double, upperHeight: Double,
                      angle: Double, tolerance: ModelingTolerance,
                      admission: GeometryConversionAdmission? = nil) throws
        -> (lower: [[ExactPrismaticBoundarySegment]], upper: [[ExactPrismaticBoundarySegment]]) {
        let boundaries = try ExactProfileBoundaryConverter(tolerance: tolerance)
            .boundaries(from: profile, offset: .zero,
                extrusionAxis: OriginalDraftDirectionInputs.normalized(axis))
        var lower: [[ExactPrismaticBoundarySegment]] = []
        var upper: [[ExactPrismaticBoundarySegment]] = []
        for boundary in boundaries {
            try CurrentTaskCancellationChecker().checkCancellation()
            var bottom: [ExactPrismaticBoundarySegment] = []
            var top: [ExactPrismaticBoundarySegment] = []
            for segment in boundary {
                try admission?.chargeWork()
                if case .line = segment.geometry {
                    try admission?.chargeStorage(bytes: 2 * (MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride)
                        + 4 * MemoryLayout<Double>.stride)
                    let original = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                        controlPoints: [segment.startPoint, segment.endPoint], weights: [1, 1])
                    let prepared: OriginalCurveRootSpan3D?
                    if let admission {
                        var usage = OriginalDraftedConstructionAdmission(admission)
                        prepared = try OriginalCurveRootSpan3D(source: .bSpline(original),
                            start: .authored(0), end: .authored(1), nativeSpanIndex: 1,
                            maximumParameterWidth: original.domain.parameterResolution(tolerance: tolerance),
                            maximumSubdivisionDepth: min(32, admission.maximumSubdivisionDepth), tolerance: tolerance,
                            storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                            maximumSpanCount: min(4096, admission.maximumSpanCount),
                            remainingSourceDepth: admission.remainingSourceDepth,
                            maximumAlgebraicDepth: admission.maximumAlgebraicDepth ?? 32)
                    } else { prepared = nil }
                    func moved(_ height: Double) throws -> ExactPrismaticBoundarySegment {
                        let source: any GeometryCurveConversionSource
                        if let admission, let prepared {
                            var usage = OriginalDraftedConstructionAdmission(admission)
                            let original = try OriginalDraftedCurve3D(generator: prepared, normal: normal,
                                axis: axis, pull: pull, height: height, angle: angle,
                                remainingSourceDepth: admission.remainingSourceDepth,
                                tolerance: tolerance, usage: &usage)
                            source = OriginalDraftedCurveConversionSource(source: original, admission: admission)
                        } else {
                            source = try DraftedSectionCurveSource(curve: .bSpline(original), normal: normal,
                                axis: axis, pull: pull, height: height, angle: angle, tolerance: tolerance)
                        }
                        let start = try source.pointAndDerivative(at: 0, tolerance: tolerance).point
                        let end = try source.pointAndDerivative(at: 1, tolerance: tolerance).point
                        if let admission {
                            try admission.chargeStorage(bytes: 2 * (MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride)
                                + 4 * MemoryLayout<Double>.stride)
                            let candidate = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                                controlPoints: [start, end], weights: [1, 1])
                            _ = try CertifiedGeometryConverter().certifyCurve(source: source, candidate: candidate,
                                over: ScalarInterval(lower: 0, upper: 1),
                                requirements: GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
                                    maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance),
                                tolerance: tolerance, admission: admission)
                        }
                        return try .line(from: start, to: end, tolerance: tolerance)
                    }
                    bottom.append(try moved(lowerHeight))
                    top.append(try moved(upperHeight))
                } else {
                    let original = try originalBoundary(segment, tolerance: tolerance)
                    let pair = try DraftedSectionPairBuilder().pair(curve: original.curve,
                        parameters: original.parameters, normal: normal, axis: axis, pull: pull,
                        lowerHeight: lowerHeight, upperHeight: upperHeight, angle: angle, tolerance: tolerance,
                        admission: admission)
                    bottom.append(try .bSpline(pair.lower, tolerance: tolerance))
                    top.append(try .bSpline(pair.upper, tolerance: tolerance))
                }
            }
            lower.append(try joined(bottom, originals: boundary,
                normal: OriginalDraftDirectionInputs.normalized(normal), tolerance: tolerance, admission: admission))
            upper.append(try joined(top, originals: boundary,
                normal: OriginalDraftDirectionInputs.normalized(normal), tolerance: tolerance, admission: admission))
        }
        return (lower, upper)
    }

    private func originalBoundary(_ segment: ExactPrismaticBoundarySegment,
        tolerance: ModelingTolerance) throws -> (curve: Curve3D, parameters: ScalarInterval) {
        switch segment.geometry {
        case let .bSpline(curve):
            guard case let .closed(lower, upper) = curve.domain else {
                throw failure(.invalidInput, "A drafted profile curve lost its finite original trim.", tolerance)
            }
            return (.bSpline(curve), try ScalarInterval(lower: lower, upper: upper))
        case let .circularArc(circle, start, end):
            if start < end {
                return (.circle(circle), try ScalarInterval(lower: start, upper: end))
            }
            let directed = Curve3D.parameterImage(try ParameterImageCurve3D(
                source: .circle(circle), gain: -1, tolerance: tolerance))
            return (directed, try ScalarInterval(lower: -start, upper: -end))
        case .line:
            return (.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [segment.startPoint, segment.endPoint], weights: [1, 1])),
                try ScalarInterval(lower: 0, upper: 1))
        }
    }

    private func joined(_ moved: [ExactPrismaticBoundarySegment], originals: [ExactPrismaticBoundarySegment],
                        normal: Vector3D, tolerance: ModelingTolerance,
                        admission: GeometryConversionAdmission? = nil) throws -> [ExactPrismaticBoundarySegment] {
        try admission?.chargeStorage(bytes: moved.count * MemoryLayout<Point3D>.stride)
        var joints: [Point3D] = []
        joints.reserveCapacity(moved.count)
        for index in moved.indices {
            try admission?.chargeWork()
            let next = (index + 1) % moved.count
            let before = moved[index], after = moved[next]
            if case .line = originals[index].geometry, case .line = originals[next].geometry {
                let t = before.endPoint - before.startPoint
                let s = after.endPoint - after.startPoint
                let determinant = normal.dot(t.cross(s))
                if abs(determinant) <= tolerance.angle * t.length * s.length {
                    guard t.dot(s) > 0, (before.endPoint - after.startPoint).length <= tolerance.distance else {
                        throw failure(.intersectionFailure, "Parallel draft walls have no unique retained corner.", tolerance)
                    }
                    joints.append(before.endPoint)
                } else {
                    let parameter = normal.dot((after.startPoint - before.startPoint).cross(s)) / determinant
                    let point = before.startPoint + t * parameter
                    let residual = (point - after.startPoint).cross(s).length / s.length
                    guard residual <= tolerance.distance else {
                        throw failure(.intersectionFailure, "Draft wall intersection escaped its cap plane.", tolerance)
                    }
                    joints.append(point)
                }
            } else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): curved sharp joints require the retained
                // wall surfaces' intersection and its cap trims. The public closed-profile
                // extrude path reaches this branch. Complete only with a whole intersection
                // curve certificate and finite wall/cap clipping; snapping endpoints is forbidden.
                guard (before.endPoint - after.startPoint).length <= tolerance.distance else {
                    throw failure(.unsupportedCapability, "A sharp curved draft corner requires wall intersection clipping.", tolerance)
                }
                joints.append(before.endPoint)
            }
        }
        try admission?.chargeStorage(bytes: moved.count * MemoryLayout<ExactPrismaticBoundarySegment>.stride)
        return try moved.indices.map { index in
            try admission?.chargeWork()
            let segment = moved[index]
            if case .line = segment.geometry {
                let start = joints[(index + moved.count - 1) % moved.count], end = joints[index]
                guard (end - start).dot(originals[index].endPoint - originals[index].startPoint) > 0 else {
                    throw failure(.singularGeometry, "A drafted profile wall vanished or reversed at its corner intersection.", tolerance)
                }
                return try .line(from: start, to: end, tolerance: tolerance)
            }
            return segment
        }
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
