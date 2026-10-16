import CADCore
import CADGeometry
import CADIR

/// One invocation's original region laws and their compatibility facades.
package struct OriginalLoftRegionSections {
    private let contextTolerance: ModelingTolerance
    package let sections: [ResolvedModelingSection]
    package let profiles: [Profile]
    package let spans: [[[ExactBSplineCurveSpan]]]
    package let contacts: [[[OriginalCurveContactSource]]]

    package init(loft: LoftFeature, featureID: FeatureID, context: EvaluationContext,
        using execution: inout OriginalQueryExecution) throws {
        let builder = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, using: &execution)
        let contactBuilder = OriginalLoftProfileContactSources()
        try RationalAlgebraStorage.retain(loft.sections.count, of: ResolvedModelingSection.self, usage: &execution)
        try RationalAlgebraStorage.retain(loft.sections.count, of: Profile.self, usage: &execution)
        try RationalAlgebraStorage.retain(loft.sections.count, of: [[ExactBSplineCurveSpan]].self, usage: &execution)
        try RationalAlgebraStorage.retain(loft.sections.count, of: [[OriginalCurveContactSource]].self, usage: &execution)
        var sections: [ResolvedModelingSection] = [], profiles: [Profile] = []
        var spans: [[[ExactBSplineCurveSpan]]] = [], contacts: [[[OriginalCurveContactSource]]] = []
        for reference in loft.sections {
            let section = try ResolvedModelingSection.resolve(reference.section, context: context, featureID: featureID,
                using: &execution)
            let profile = try section.profileFacade()
            let sourceContacts: [[OriginalCurveContactSource]]
            switch section {
            case .profile(let profile, _):
                sourceContacts = try contactBuilder.loops(profile: profile,
                    tolerance: context.tolerance, using: &execution)
            case .face(let face, _):
                sourceContacts = try contactBuilder.loops(face: face,
                    tolerance: context.tolerance, using: &execution)
            case .constructedRegion(let region):
                try RationalAlgebraStorage.retain(region.loops.count, of: [OriginalCurveContactSource].self, usage: &execution)
                var originalLoops: [[OriginalCurveContactSource]] = []
                originalLoops.reserveCapacity(region.loops.count)
                for charts in region.loops {
                    try RationalAlgebraStorage.retain(charts.count, of: OriginalCurveContactSource.self, usage: &execution)
                    var originalContacts: [OriginalCurveContactSource] = []
                    originalContacts.reserveCapacity(charts.count)
                    for chart in charts {
                        let law = try chart.persistentCurve(tolerance: context.tolerance, using: &execution)
                        originalContacts.append(.init(curve: law, parameters: try .init(lower: 0, upper: 1)))
                    }
                    originalLoops.append(originalContacts)
                }
                sourceContacts = originalLoops
            case .curve: throw FeatureEvaluationError.invalidGraph("A region Loft requires closed source sections.")
            }
            sections.append(section); profiles.append(profile)
            spans.append(try builder.loopSpans(from: section, using: &execution)); contacts.append(sourceContacts)
        }
        contextTolerance = context.tolerance
        self.sections = sections; self.profiles = profiles; self.spans = spans; self.contacts = contacts
    }

    /// Correspondence may reorder holes but must keep the same complete source loops.
    package func reorderedSpans(for profiles: [Profile], using execution: inout OriginalQueryExecution)
        throws -> [[[ExactBSplineCurveSpan]]] {
        guard profiles.count == self.profiles.count else {
            throw FeatureEvaluationError.invalidGraph("Loft region correspondence changed its original section count.")
        }
        try RationalAlgebraStorage.retain(profiles.count, of: [[ExactBSplineCurveSpan]].self, usage: &execution)
        var result: [[[ExactBSplineCurveSpan]]] = []
        for section in profiles.indices {
            let original = self.profiles[section].boundaryLoops, ordered = profiles[section].boundaryLoops
            guard original.count == ordered.count, original.count == spans[section].count else {
                throw FeatureEvaluationError.invalidGraph("Loft region correspondence changed its original loop coverage.")
            }
            try RationalAlgebraStorage.retain(original.count, of: [ExactBSplineCurveSpan].self, usage: &execution)
            try consumeProduct(original.count, 2, using: &execution)
            var used = Set<Int>(), loops: [[ExactBSplineCurveSpan]] = []
            for loop in ordered {
                var owner: Int?
                for index in original.indices {
                    try execution.consumeWork(1)
                    if !used.contains(index), try sameOriginalLoop(original[index], loop, using: &execution) {
                        guard owner == nil else {
                            throw KernelError(phase: .topology, code: .ambiguousSelection, tolerance: contextTolerance,
                                message: "Reordered Loft holes have indistinguishable original loop identities.")
                        }
                        owner = index
                    }
                }
                guard let owner else {
                    throw FeatureEvaluationError.invalidGraph("Reordered Loft loop no longer belongs to its original section.")
                }
                used.insert(owner); loops.append(spans[section][owner])
            }
            result.append(loops)
        }
        return result
    }

    private func sameOriginalLoop(_ first: ProfileLoop, _ second: ProfileLoop,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        guard first.vertices.count == second.vertices.count,
              first.boundarySegments.count == second.boundarySegments.count else { return false }
        try consumeProduct(first.vertices.count, 3, using: &execution)
        guard first.vertices == second.vertices else { return false }
        for (a, b) in zip(first.boundarySegments, second.boundarySegments) {
            switch (a, b) {
            case (.line, .line): try execution.consumeWork(6)
            case (.circularArc, .circularArc): try execution.consumeWork(16)
            case (.spline(let x), .spline(let y)):
                guard x.curve.degree == y.curve.degree, x.curve.isPeriodic == y.curve.isPeriodic,
                      x.curve.knots.count == y.curve.knots.count,
                      x.curve.controlPoints.count == y.curve.controlPoints.count,
                      x.curve.weights.count == y.curve.weights.count else { return false }
                try execution.consumeWork(x.curve.knots.count)
                try consumeProduct(x.curve.controlPoints.count, 3, using: &execution)
                try execution.consumeWork(x.curve.weights.count)
            default: return false
            }
            if a != b { return false }
        }
        return true
    }
    private func consumeProduct(_ count: Int, _ units: Int,
        using execution: inout OriginalQueryExecution) throws {
        let total = count.multipliedReportingOverflow(by: units)
        guard count >= 0, units >= 0, !total.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Loft structural work count overflowed.")
        }
        try execution.consumeWork(total.partialValue)
    }

}
