import CADCore

/// Describes actual prepared original contact output without inventing completeness receipts.
public struct BooleanPreparationDiagnostics: Sendable, Hashable {
    public let inputBodyCount: Int
    public let facePairCount: Int
    public let boundaryContactCount: Int
    public let supportCurveCount: Int
    public let supportPointCount: Int
    public let coincidentSupportCount: Int
    public let finiteCurveComponentCount: Int
    public let finitePointComponentCount: Int
    public let finiteCoincidentComponentCount: Int
    public let maximumProducerResidual: Double
    public let sourceTolerance: ModelingTolerance
    public let effectiveTolerance: ModelingTolerance
    public let policy: BooleanPreparationPolicy

    init(inputBodyCount: Int, graph: BooleanIntersectionGraph, split: BooleanUVSplitGraph,
         sourceTolerance: ModelingTolerance, effectiveTolerance: ModelingTolerance,
         policy: BooleanPreparationPolicy) {
        self.inputBodyCount = inputBodyCount
        facePairCount = graph.facePairs.count
        boundaryContactCount = graph.boundaryContacts.count
        var curves = 0, points = 0, coincident = 0
        var residual = 0.0
        for intersection in graph.faceIntersections {
            switch intersection.geometry {
            case let .curve(value): curves += 1; residual = max(residual, value.maximumResidual)
            case let .point(value): points += 1; residual = max(residual, value.residual)
            case .originalCoaxial(let value):
                if value.imageDimension == 0 { points += 1 } else { curves += 1 }
            case .originalBoundedSphereCone, .originalFullSphereCone, .originalFullConeCone, .originalApexSphereCone: curves += 1
            case let .coincident(value): coincident += 1; residual = max(residual, value.residual)
            }
        }
        for contact in graph.boundaryContacts {
            if case let .points(events) = contact.geometry {
                for event in events { residual = max(residual, event.residual) }
            }
        }
        supportCurveCount = curves
        supportPointCount = points
        coincidentSupportCount = coincident
        curves = 0; points = 0; coincident = 0
        for faceSplit in split.splits {
            for component in faceSplit.components {
                switch component.geometry {
                case let .transverseSegment(first, last):
                    curves += 1; residual = max(residual, max(first.residual, last.residual))
                case let .trimmedCurve(chain):
                    curves += 1
                    for segment in chain.segments {
                        residual = max(residual, max(segment.start.residual, segment.end.residual))
                        residual = max(residual, segment.intersection.maximumResidual)
                    }
                case let .closedCurve(value):
                    curves += 1; residual = max(residual, value.intersection.maximumResidual)
                    for sample in value.samples { residual = max(residual, sample.uvPoint.residual) }
                case let .tangent(value): points += 1; residual = max(residual, value.residual)
                case .coincident: coincident += 1
                }
            }
        }
        finiteCurveComponentCount = curves
        finitePointComponentCount = points
        finiteCoincidentComponentCount = coincident
        maximumProducerResidual = residual
        self.sourceTolerance = sourceTolerance
        self.effectiveTolerance = effectiveTolerance
        self.policy = policy
    }
}
