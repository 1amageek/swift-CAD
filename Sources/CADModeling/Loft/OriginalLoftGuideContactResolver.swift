import CADCore
import CADGeometry

/// Resolves all original chain events against section boundaries before making connector images.
package struct OriginalLoftGuideContactResolver {
    private let classifier: any OriginalCurveCurveContactClassifying

    package init(classifier: any OriginalCurveCurveContactClassifying = DefaultOriginalCurveCurveContactClassifier()) {
        self.classifier = classifier
    }

    package func contacts(chain: OriginalLoftGuideChain, section: ExactLoftGuideSection,
                          using execution: inout OriginalQueryExecution,
                          tolerance: ModelingTolerance) throws -> [OriginalLoftGuideContact] {
        var events: [OriginalLoftGuideContact] = []
        for segmentIndex in chain.segments.indices {
            let source = try chain.source(at: segmentIndex, tolerance: tolerance)
            for loopIndex in section.loops.indices {
                let targets: [OriginalCurveContactSource]
                if let originals = section.originalContactLoops {
                    guard originals.count == section.loops.count, !originals[loopIndex].isEmpty else {
                        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                            message: "Original Loft contact laws must retain every declared section loop.")
                    }
                    targets = originals[loopIndex]
                } else {
                    // Native-only internal callers already own these spline laws.
                    // Public mixed/profile routes supply their original laws explicitly.
                    try execution.consumeWork(section.loops[loopIndex].count)
                    try RationalAlgebraStorage.retain(section.loops[loopIndex].count, of: OriginalCurveContactSource.self, usage: &execution)
                    targets = try section.loops[loopIndex].map { boundary in
                        guard case .closed(let lower, let upper) = boundary.curve.domain else {
                            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                message: "Original Loft guide contacts require a finite section boundary trim.")
                        }
                        return OriginalCurveContactSource(curve: .bSpline(boundary.curve),
                            parameters: try ScalarInterval(lower: lower, upper: upper))
                    }
                }
                for target in targets {
                    switch try classifier.contacts(first: source, second: target, tolerance: tolerance, using: &execution) {
                    case .continuousAmbiguity(let first, let second):
                        throw KernelError(phase: .geometry, code: .ambiguousSelection, tolerance: tolerance,
                            message: "A Loft guide has a proved continuous section contact on original segment \(segmentIndex), guide interval [\(first.parameters.lower), \(first.parameters.upper)] and boundary interval [\(second.parameters.lower), \(second.parameters.upper)].")
                    case .isolated(let contacts):
                        try execution.consumeWork(contacts.count)
                        for contact in contacts {
                            let parameters = contact.firstParameters
                            let point = try contact.firstPoint(using: &execution)
                            let event = try OriginalLoftGuideContact(segmentIndex: segmentIndex, parameters: parameters,
                                point: point, boundaryLoopIndex: loopIndex, parameterAuthority: contact.parameterAuthority,
                                nativeEndpoint: contact.firstNativeEndpoint(using: &execution))
                            // Exact retained guide-root equality merges a shared boundary
                            // event; interval overlap and nearby points never merge roots.
                            try execution.consumeWork(events.count)
                            var duplicate = false
                            for old in events where old.segmentIndex == segmentIndex && old.boundaryLoopIndex == loopIndex {
                                if let first = old.parameterAuthority, let second = event.parameterAuthority {
                                    if try first.hasSameFirstParameter(as: second, using: &execution) {
                                        duplicate = true; break
                                    }
                                } else if old.parameters.width == 0, parameters.width == 0,
                                    old.parameters.lower == parameters.lower {
                                    duplicate = true; break
                                }
                            }
                            if !duplicate { try append(event, to: &events, using: &execution) }
                        }
                    }
                }
            }
        }
        // Adjacent original segments have one logical chain joint. Preserve all
        // other event multiplicities, including close roots and different hole roles.
        try execution.consumeWork(events.count)
        try RationalAlgebraStorage.retain(events.count, of: OriginalLoftGuideContact.self, usage: &execution)
        var merged: [OriginalLoftGuideContact] = []
        merged.reserveCapacity(events.count)
        for event in events {
            let order = try chain.orderedBounds(event, tolerance: tolerance)
            var sharedJoint = false
            if order.width == 0, order.lower.rounded() == order.lower {
                try execution.consumeWork(merged.count)
                for old in merged where old.boundaryLoopIndex == event.boundaryLoopIndex {
                    let oldOrder = try chain.orderedBounds(old, tolerance: tolerance)
                    if oldOrder.width == 0, oldOrder.lower == order.lower {
                        sharedJoint = true
                        break
                    }
                }
            }
            if !sharedJoint { merged.append(event) }
        }
        return merged
    }

    private func append(_ event: OriginalLoftGuideContact, to events: inout [OriginalLoftGuideContact],
        using execution: inout OriginalQueryExecution) throws {
        if events.count == events.capacity {
            let doubled = events.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original Loft event capacity overflows.")
            }
            let capacity = max(1, doubled.partialValue)
            try RationalAlgebraStorage.retain(capacity, of: OriginalLoftGuideContact.self, usage: &execution)
            try execution.consumeWork(events.count)
            events.reserveCapacity(capacity)
        }
        events.append(event)
    }
}
