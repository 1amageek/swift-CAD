import CADCore
import CADGeometry

/// Retains authored laws; converted spline parameters never replace original events.
package struct OriginalLoftGuideChain: Sendable {
    package let segments: [EvaluatedCurvePathSegment]
    package let tolerance: ModelingTolerance

    package init(segments: [EvaluatedCurvePathSegment], tolerance: ModelingTolerance) throws {
        guard !segments.isEmpty else { throw FeatureEvaluationError.invalidGraph("A Loft guide requires an original directed chain.") }
        // The chain builder owns adjacency admission. Contact preparation validates
        // each original law under its retained caller ledger instead of replaying it here.
        for segment in segments {
            guard segment.curve.exactCurve != nil, case .closed = segment.curve.parameterDomain else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "A Loft guide requires an original curve and authored finite trim for every segment.")
            }
        }
        self.segments = segments
        self.tolerance = tolerance
    }

    package func source(at index: Int, tolerance: ModelingTolerance) throws -> OriginalCurveContactSource {
        guard segments.indices.contains(index), let curve = segments[index].curve.exactCurve,
              case .closed(let lower, let upper) = segments[index].curve.parameterDomain else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original Loft guide event has no retained source segment.")
        }
        return OriginalCurveContactSource(curve: curve, parameters: try ScalarInterval(lower: lower, upper: upper))
    }

    package func orderedBounds(_ contact: OriginalLoftGuideContact, tolerance: ModelingTolerance) throws -> ScalarInterval {
        let source = try source(at: contact.segmentIndex, tolerance: tolerance)
        let offset = Double(contact.segmentIndex)
        guard contact.parameters.lower >= source.parameters.lower,
              contact.parameters.upper <= source.parameters.upper else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original Loft contact order escapes its retained native trim.")
        }
        let reversed = segments[contact.segmentIndex].isReversed
        // Authored endpoints have exact chain-joint identity. Preserve those
        // identities without widening them through arithmetic on equal values.
        if contact.parameters.width == 0 {
            if contact.parameters.lower == source.parameters.lower {
                let joint = offset + (reversed ? 1 : 0)
                return try ScalarInterval(lower: joint, upper: joint)
            }
            if contact.parameters.lower == source.parameters.upper {
                let joint = offset + (reversed ? 0 : 1)
                return try ScalarInterval(lower: joint, upper: joint)
            }
        }
        let denominator = OutwardScalarInterval.exact(source.parameters.upper)
            - .exact(source.parameters.lower)
        let numerator = OutwardScalarInterval(lower: contact.parameters.lower, upper: contact.parameters.upper)
            - .exact(source.parameters.lower)
        guard let normalized = numerator.divided(by: denominator) else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                message: "Original Loft guide order cannot enclose its native interval scaling.")
        }
        let directed = reversed ? OutwardScalarInterval.exact(1) - normalized : normalized
        let order = OutwardScalarInterval.exact(offset) + directed
        guard order.isFinite else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                message: "Original Loft guide order exceeds finite parameter arithmetic.")
        }
        return try ScalarInterval(lower: max(offset, order.lower), upper: min(offset + 1, order.upper))
    }

    package func reversed(tolerance: ModelingTolerance) throws -> OriginalLoftGuideChain {
        try OriginalLoftGuideChain(segments: segments.reversed().map {
            EvaluatedCurvePathSegment(curve: $0.curve, isReversed: !$0.isReversed)
        }, tolerance: tolerance)
    }

    package func reversed(_ contact: OriginalLoftGuideContact) -> OriginalLoftGuideContact {
        OriginalLoftGuideContact(segmentIndex: segments.count - 1 - contact.segmentIndex,
            parameters: contact.parameters, point: contact.point, boundaryLoopIndex: contact.boundaryLoopIndex,
            parameterAuthority: contact.parameterAuthority, nativeEndpoint: contact.nativeEndpoint)
    }

    package func connector(from start: OriginalLoftGuideContact, to end: OriginalLoftGuideContact,
                           tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        guard start.segmentIndex <= end.segmentIndex,
              try orderedBounds(start, tolerance: tolerance).upper < orderedBounds(end, tolerance: tolerance).lower else {
            throw KernelError(phase: .geometry, code: .ambiguousSelection, tolerance: tolerance,
                message: "Original Loft guide event intervals do not establish a strict directed order.")
        }
        var pieces: [EvaluatedCurvePathSegment] = []
        for index in start.segmentIndex...end.segmentIndex {
            let original = segments[index]
            let source = try source(at: index, tolerance: tolerance)
            let begins = index == start.segmentIndex ? start.parameters.midpoint
                : (original.isReversed ? source.parameters.upper : source.parameters.lower)
            let ends = index == end.segmentIndex ? end.parameters.midpoint
                : (original.isReversed ? source.parameters.lower : source.parameters.upper)
            if begins == ends { continue }
            let lower = min(begins, ends), upper = max(begins, ends)
            guard lower >= source.parameters.lower, upper <= source.parameters.upper else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Original Loft guide connector trim escapes its authored source interval.")
            }
            var curve = original.curve
            curve.isClosed = false
            curve.exactParameterDomain = .closed(lower, upper)
            curve.points = [try source.curve.point(at: lower, tolerance: tolerance, using: &execution),
                try source.curve.point(at: upper, tolerance: tolerance, using: &execution)]
            curve.exactPointParameters = [lower, upper]
            pieces.append(EvaluatedCurvePathSegment(curve: curve, isReversed: original.isReversed))
        }
        let spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance, using: &execution).pathSpans(from: pieces, using: &execution)
        return try ExactCompositeBSplineCurveBuilder().build(spans: spans.map(\.curve), tolerance: tolerance, using: &execution)
    }
}
