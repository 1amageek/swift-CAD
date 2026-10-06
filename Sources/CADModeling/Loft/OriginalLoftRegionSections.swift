import CADCore
import CADGeometry
import CADIR

/// One invocation's original region laws and their compatibility facades.
package struct OriginalLoftRegionSections {
    package let sections: [ResolvedModelingSection]
    package let profiles: [Profile]
    package let spans: [[[ExactBSplineCurveSpan]]]
    package let contacts: [[[OriginalCurveContactSource]]]

    package init(loft: LoftFeature, featureID: FeatureID, context: EvaluationContext,
        allowance: inout LoftCorrespondenceAllowance) throws {
        let builder = ExactBSplineCurveSpanBuilder(tolerance: context.tolerance, admission: try allowance.conversionAdmission())
        let contactBuilder = OriginalLoftProfileContactSources()
        try allowance.retainElements(loft.sections.count, of: ResolvedModelingSection.self)
        try allowance.retainElements(loft.sections.count, of: Profile.self)
        try allowance.retainElements(loft.sections.count, of: [[ExactBSplineCurveSpan]].self)
        try allowance.retainElements(loft.sections.count, of: [[OriginalCurveContactSource]].self)
        var sections: [ResolvedModelingSection] = [], profiles: [Profile] = []
        var spans: [[[ExactBSplineCurveSpan]]] = [], contacts: [[[OriginalCurveContactSource]]] = []
        for reference in loft.sections {
            let section = try ResolvedModelingSection.resolve(reference.section, context: context, featureID: featureID,
                admission: try allowance.conversionAdmission())
            let profile = try section.profileFacade()
            let sourceContacts: [[OriginalCurveContactSource]]
            switch section {
            case .profile(let profile, _):
                sourceContacts = try contactBuilder.loops(profile: profile,
                    consumeStorage: { try allowance.charge($0) }, tolerance: context.tolerance)
            case .face(let face, _):
                sourceContacts = try contactBuilder.loops(face: face,
                    consumeStorage: { try allowance.charge($0) }, tolerance: context.tolerance)
            case .constructedRegion(let region):
                let admission = try allowance.conversionAdmission()
                try allowance.retainElements(region.loops.count, of: [OriginalCurveContactSource].self)
                var originalLoops: [[OriginalCurveContactSource]] = []
                originalLoops.reserveCapacity(region.loops.count)
                for charts in region.loops {
                    try allowance.retainElements(charts.count, of: OriginalCurveContactSource.self)
                    var originalContacts: [OriginalCurveContactSource] = []
                    originalContacts.reserveCapacity(charts.count)
                    for chart in charts {
                        let law = try chart.persistentCurve(tolerance: context.tolerance, admission: admission)
                        originalContacts.append(.init(curve: law, parameters: try .init(lower: 0, upper: 1)))
                    }
                    originalLoops.append(originalContacts)
                }
                sourceContacts = originalLoops
            case .curve: throw FeatureEvaluationError.invalidGraph("A region Loft requires closed source sections.")
            }
            sections.append(section); profiles.append(profile)
            spans.append(try builder.loopSpans(from: section)); contacts.append(sourceContacts)
        }
        self.sections = sections; self.profiles = profiles; self.spans = spans; self.contacts = contacts
    }

    /// Correspondence may reorder holes but must keep the same complete source loops.
    package func reorderedSpans(for profiles: [Profile], allowance: inout LoftCorrespondenceAllowance)
        throws -> [[[ExactBSplineCurveSpan]]] {
        guard profiles.count == self.profiles.count else {
            throw FeatureEvaluationError.invalidGraph("Loft region correspondence changed its original section count.")
        }
        try allowance.retainElements(profiles.count, of: [[ExactBSplineCurveSpan]].self)
        var result: [[[ExactBSplineCurveSpan]]] = []
        for section in profiles.indices {
            let original = self.profiles[section].boundaryLoops, ordered = profiles[section].boundaryLoops
            guard original.count == ordered.count, original.count == spans[section].count else {
                throw FeatureEvaluationError.invalidGraph("Loft region correspondence changed its original loop coverage.")
            }
            try allowance.retainElements(original.count, of: [ExactBSplineCurveSpan].self)
            try allowance.chargeProduct(original.count, 2)
            var used = Set<Int>(), loops: [[ExactBSplineCurveSpan]] = []
            for loop in ordered {
                var owner: Int?
                for index in original.indices {
                    try allowance.charge(1)
                    if !used.contains(index), try sameOriginalLoop(original[index], loop, allowance: allowance) {
                        guard owner == nil else {
                            throw KernelError(phase: .topology, code: .ambiguousSelection, tolerance: allowance.tolerance,
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
        allowance: LoftCorrespondenceAllowance) throws -> Bool {
        guard first.vertices.count == second.vertices.count,
              first.boundarySegments.count == second.boundarySegments.count else { return false }
        try allowance.chargeProduct(first.vertices.count, 3)
        guard first.vertices == second.vertices else { return false }
        for (a, b) in zip(first.boundarySegments, second.boundarySegments) {
            switch (a, b) {
            case (.line, .line): try allowance.charge(6)
            case (.circularArc, .circularArc): try allowance.charge(16)
            case (.spline(let x), .spline(let y)):
                guard x.curve.degree == y.curve.degree, x.curve.isPeriodic == y.curve.isPeriodic,
                      x.curve.knots.count == y.curve.knots.count,
                      x.curve.controlPoints.count == y.curve.controlPoints.count,
                      x.curve.weights.count == y.curve.weights.count else { return false }
                try allowance.charge(x.curve.knots.count)
                try allowance.chargeProduct(x.curve.controlPoints.count, 3)
                try allowance.charge(x.curve.weights.count)
            default: return false
            }
            if a != b { return false }
        }
        return true
    }
}
