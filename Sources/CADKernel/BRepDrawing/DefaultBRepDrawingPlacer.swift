import CADCore
import CADGeometry
import CADTopology

/// Maps original B-rep curves through authored affine occurrences without fitting.
public struct DefaultBRepDrawingPlacer: BRepDrawingPlacing {
    private struct Key: Hashable {
        let identity: String
        let bodyID: BodyID
    }
    private let curves: any OrthographicCurveProjecting

    public init(curves: any OrthographicCurveProjecting = DefaultOrthographicCurveProjector()) {
        self.curves = curves
    }

    public func place(_ original: BRepDrawingProjection, in evaluated: EvaluatedDocument,
                      placements: [BRepDrawingPlacement], maximumPlacements: Int,
                      maximumProjectedUses: Int) throws -> BRepDrawingPlacedProjection {
        try CurrentTaskCancellationChecker().checkCancellation()
        try original.validateCurrent(evaluated)
        let tolerance = original.configuration.tolerance
        guard maximumPlacements > 0, maximumProjectedUses > 0,
              placements.count <= maximumPlacements else {
            throw KernelError(phase: .validation, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Placed drawing exceeds the caller placement capacity.")
        }
        // Retain indices into the immutable original use owner, rather than
        // copying each curve/topology receipt or rescanning all bodies per occurrence.
        var indicesByBody: [BodyID: [Int]] = [:]
        for index in original.uses.indices {
            try CurrentTaskCancellationChecker().checkCancellation()
            indicesByBody[original.uses[index].bodyID, default: []].append(index)
        }
        var keys: Set<Key> = []
        var count = 0
        for placement in placements {
            try CurrentTaskCancellationChecker().checkCancellation()
            try placement.transform.validate()
            guard evaluated.brep.bodies[placement.bodyID] != nil,
                  keys.insert(Key(identity: placement.identity, bodyID: placement.bodyID)).inserted else {
                throw TopologyError.missingReference("Drawing placement is foreign or duplicated.")
            }
            for _ in indicesByBody[placement.bodyID] ?? [] {
                guard count < maximumProjectedUses else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                        tolerance: tolerance, message: "Placed drawing exhausts the caller projected-use capacity.")
                }
                count += 1
            }
        }
        // Count admission precedes all retained affine images and output storage.
        var uses: [BRepDrawingPlacedUse] = []
        uses.reserveCapacity(count)
        for placement in placements {
            for index in indicesByBody[placement.bodyID] ?? [] {
                try CurrentTaskCancellationChecker().checkCancellation()
                let use = original.uses[index]
                let source: Curve3D
                if let word = placement.operationWord {
                    source = .originalAffineWord(try OriginalAffineWordCurve3D(
                        source: use.edge.curve.source, operationWord: word, tolerance: tolerance))
                } else {
                    source = .affineImage(try AffineImageCurve3D(source: use.edge.curve.source,
                        transform: placement.transform, tolerance: tolerance))
                }
                let curve = try curves.project(source, onto: original.frame, tolerance: tolerance)
                uses.append(BRepDrawingPlacedUse(placement: placement, original: use, curve: curve))
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return BRepDrawingPlacedProjection(original: original, placements: placements, uses: uses)
    }
}
