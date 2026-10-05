import CADCore
import CADGeometry
import CADIR

/// Selects the original directed guide interval joining all section events.
package struct OriginalLoftGuideResolver {
    package func resolve(chain: OriginalLoftGuideChain, sections: [ExactLoftGuideSection],
                         featureID: FeatureID, allowance: inout OriginalCurveContactAllowance,
                         tolerance: ModelingTolerance) throws -> ExactLoftGuideCurve {
        var events: [OriginalLoftGuideContact] = []
        let resolver = OriginalLoftGuideContactResolver()
        try allowance.reserveEntries(sections.count)
        try allowance.reserveStorage(sections.count, of: OriginalLoftGuideContact.self)
        events.reserveCapacity(sections.count)
        for (index, section) in sections.enumerated() {
            let contacts = try resolver.contacts(chain: chain, section: section, allowance: &allowance, tolerance: tolerance)
            guard contacts.count == 1, let contact = contacts.first else {
                throw KernelError(phase: .geometry,
                    code: contacts.isEmpty ? .intersectionFailure : .ambiguousSelection,
                    featureID: featureID, tolerance: tolerance,
                    message: "Original Loft guide section \(index) has \(contacts.count) distinct original contact events; exactly one is required.")
            }
            events.append(contact)
        }
        guard let first = events.first, let last = events.last,
              events.allSatisfy({ ($0.boundaryLoopIndex == 0) == (first.boundaryLoopIndex == 0) }) else {
            throw KernelError(phase: .geometry, code: .ambiguousSelection, featureID: featureID,
                tolerance: tolerance, message: "A Loft guide changes original outer/hole boundary role.")
        }
        let firstOrder = try chain.orderedBounds(first, tolerance: tolerance)
        let lastOrder = try chain.orderedBounds(last, tolerance: tolerance)
        let oriented: OriginalLoftGuideChain
        let contacts: [OriginalLoftGuideContact]
        if firstOrder.upper < lastOrder.lower {
            oriented = chain
            contacts = events
        } else if lastOrder.upper < firstOrder.lower {
            try allowance.reserveStorage(chain.segments.count, of: EvaluatedCurvePathSegment.self)
            try allowance.reserveEntries(chain.segments.count)
            oriented = try chain.reversed(tolerance: tolerance)
            try allowance.reserveEntries(events.count)
            try allowance.reserveStorage(events.count, of: OriginalLoftGuideContact.self)
            contacts = events.map { chain.reversed($0) }
        } else {
            throw KernelError(phase: .geometry, code: .ambiguousSelection, featureID: featureID,
                tolerance: tolerance, message: "Original Loft guide end-event intervals do not determine a traversal direction.")
        }
        for pair in zip(contacts, contacts.dropFirst()) {
            guard try oriented.orderedBounds(pair.0, tolerance: tolerance).upper
                < oriented.orderedBounds(pair.1, tolerance: tolerance).lower else {
                throw KernelError(phase: .geometry, code: .ambiguousSelection, featureID: featureID,
                    tolerance: tolerance, message: "Original Loft guide event intervals do not establish the section order.")
            }
        }
        try allowance.reserveEntries(contacts.count)
        try allowance.reserveEntries(contacts.count)
        try allowance.reserveStorage(contacts.count, of: Point3D.self)
        try allowance.reserveStorage(contacts.count, of: Int.self)
        return ExactLoftGuideCurve(originalChain: oriented, sectionContacts: contacts,
            boundaryLoopIndex: contacts[0].boundaryLoopIndex,
            sectionPoints: contacts.map(\.point), sectionBoundaryLoopIndexes: contacts.map(\.boundaryLoopIndex))
    }
}
