import HashTreeCollections
import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

/// Evaluates an axis-aligned rational B-spline prism after proving that every
/// side control net is an exact translation between two planar caps.
struct RationalBSplinePrismaticVolumeEvaluator {
    func volume(of shell: Shell, in model: BRepModel, tolerance: ModelingTolerance) throws -> Double? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try volume(of: shell, in: model, tolerance: tolerance, using: &execution)
    }

    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        try tolerance.validate()
        var faces: [FaceSurface] = []
        try OriginalParameterQueryStorage.reserve(shell.faceIDs.count, in: &faces, using: &execution)
        for faceID in shell.faceIDs {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID],
                  let geometry = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Rational prism volume references missing face geometry."
                )
            }
            guard case let .bSpline(surface) = geometry else {
                return nil
            }
            try OriginalParameterQueryStorage.append(FaceSurface(face: face, surface: surface), to: &faces, using: &execution)
        }
        try execution.retainStorage(bytes: 3 * MemoryLayout<Axis>.stride)
        for axis in Axis.allCases {
            try execution.consumeWork(1)
            let caps = (try OriginalParameterQueryStorage.compactMap(faces, using: &execution) { candidate, execution in
                try planarCoordinate(of: candidate.surface, axis: axis, using: &execution).map {
                    Cap(face: candidate.face, surface: candidate.surface, coordinate: $0)
                }
            })
            guard caps.count == 2 else { continue }
            let orderedCaps = try OriginalParameterQueryStorage.ordered(caps, using: &execution) { $0.coordinate < $1.coordinate }
            let lower = orderedCaps[0]
            let upper = orderedCaps[1]
            let height = upper.coordinate - lower.coordinate
            guard height > tolerance.distance,
                  (try OriginalParameterQueryStorage.allSatisfy(model.vertices.values, using: &execution) { vertex, execution in
                      let coordinate = axis.coordinate(of: vertex.point)
                      return coordinate == lower.coordinate
                          || coordinate == upper.coordinate
                  }) else {
                continue
            }
            let sides = (try OriginalParameterQueryStorage.filter(faces, using: &execution) { item, execution in item.face.id != lower.face.id && item.face.id != upper.face.id })
            guard !sides.isEmpty,
                  (try OriginalParameterQueryStorage.allSatisfy(sides, using: &execution) { item, execution in
                      try isExactTranslatedSide(
                          item.surface,
                          axis: axis,
                          lower: lower.coordinate,
                          upper: upper.coordinate, using: &execution
                      )
                  }) else {
                continue
            }
            guard let contribution = try upperCapContribution(
                upper,
                lowerCoordinate: lower.coordinate,
                axis: axis,
                model: model,
                tolerance: tolerance, using: &execution
            ) else {
                continue
            }
            let scaledLower = (contribution.lower * 3.0).nextDown
            let scaledUpper = (contribution.upper * 3.0).nextUp
            let volumeBounds: (lower: Double, upper: Double)
            if scaledLower > 0.0 {
                volumeBounds = (scaledLower, scaledUpper)
            } else if scaledUpper < 0.0 {
                volumeBounds = ((-scaledUpper).nextDown, (-scaledLower).nextUp)
            } else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: min(abs(scaledLower), abs(scaledUpper)),
                    tolerance: tolerance,
                    message: "Certified rational prism volume could not prove a positive cap area."
                )
            }
            let errorRadius = (volumeBounds.upper - volumeBounds.lower) * 0.5
            guard errorRadius <= tolerance.distance else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: errorRadius,
                    tolerance: tolerance,
                    message: "Certified rational prism volume exceeded the requested enclosure width."
                )
            }
            return volumeBounds.lower
                + (volumeBounds.upper - volumeBounds.lower) * 0.5
        }
        return nil
    }

    private func upperCapContribution(
        _ cap: Cap,
        lowerCoordinate: Double,
        axis: Axis,
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> TrimmedParametricSurfaceVolumeEvaluator.VolumeBounds? {
        try execution.consumeWork(1)
        let loopCount = cap.face.loops.count
        guard loopCount > 0 else { return nil }
        var lower = 0.0
        var upper = 0.0
        let requestedWidth = tolerance.distance / (3.0 * Double(loopCount))
        let reference = axis.point(at: lowerCoordinate)
        for loopID in cap.face.loops {
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
                throw TopologyError.missingReference(
                    "Rational prism cap references a missing or empty loop."
                )
            }
            let curves = try OriginalParameterQueryStorage.map(loop.coedges, using: &execution) { coedge, execution -> SurfaceParameterCurve in
                guard let curve = coedge.surfaceParameterCurve else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Rational prism cap requires a face-local pcurve on every coedge."
                    )
                }
                return curve
            }
            guard let bounds = try TrimmedParametricSurfaceVolumeEvaluator()
                .rationalLoopVolumeBounds(
                    surface: cap.surface,
                    parameterCurves: curves,
                    role: loop.role,
                    reference: reference,
                    requestedWidth: requestedWidth,
                    tolerance: tolerance, using: &execution
                ) else {
                return nil
            }
            lower = (lower + bounds.lower).nextDown
            upper = (upper + bounds.upper).nextUp
        }
        return TrimmedParametricSurfaceVolumeEvaluator.VolumeBounds(
            lower: lower,
            upper: upper
        )
    }

    private func planarCoordinate(
        of surface: BSplineSurface3D,
        axis: Axis, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        guard let coordinate = surface.controlPoints.first?.first.map({
            axis.coordinate(of: $0)
        }), (try OriginalParameterQueryStorage.allSatisfy(surface.controlPoints, using: &execution) { row, execution in
            try !row.isEmpty && (try OriginalParameterQueryStorage.allSatisfy(row, using: &execution) { item, execution in
                axis.coordinate(of: item) == coordinate
            })
        }) else {
            return nil
        }
        return coordinate
    }

    private func isExactTranslatedSide(
        _ surface: BSplineSurface3D,
        axis: Axis,
        lower: Double,
        upper: Double, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        if surface.vDegree == 1,
           surface.vControlPointCount == 2,
           let first = surface.controlPoints.first,
           let second = surface.controlPoints.last,
           first.count == second.count,
           surface.weights.count == 2,
           surface.weights[0].count == surface.weights[1].count,
           surface.weights[0].count == first.count {
            return try OriginalParameterQueryStorage.allSatisfy(zip(first.indices, surface.weights[0].indices), using: &execution) { item, execution in
                translatedPairIsExact(
                    first[item.0],
                    second[item.0],
                    firstWeight: surface.weights[0][item.1],
                    secondWeight: surface.weights[1][item.1],
                    axis: axis,
                    lower: lower,
                    upper: upper
                )
            }
        }
        if surface.uDegree == 1,
           surface.uControlPointCount == 2,
           (try OriginalParameterQueryStorage.allSatisfy(surface.controlPoints, using: &execution) { item, execution in item.count == 2 }),
           surface.weights.count == surface.controlPoints.count,
           (try OriginalParameterQueryStorage.allSatisfy(surface.weights, using: &execution) { item, execution in item.count == 2 }) {
            return (try OriginalParameterQueryStorage.allSatisfy(surface.controlPoints.indices, using: &execution) { index, execution in
                translatedPairIsExact(
                    surface.controlPoints[index][0],
                    surface.controlPoints[index][1],
                    firstWeight: surface.weights[index][0],
                    secondWeight: surface.weights[index][1],
                    axis: axis,
                    lower: lower,
                    upper: upper
                )
            })
        }
        return false
    }

    private func translatedPairIsExact(
        _ first: Point3D,
        _ second: Point3D,
        firstWeight: Double,
        secondWeight: Double,
        axis: Axis,
        lower: Double,
        upper: Double
    ) -> Bool {
        guard firstWeight == secondWeight else { return false }
        let firstCoordinate = axis.coordinate(of: first)
        let secondCoordinate = axis.coordinate(of: second)
        guard (firstCoordinate == lower && secondCoordinate == upper)
                || (firstCoordinate == upper && secondCoordinate == lower) else {
            return false
        }
        return axis.removingCoordinate(from: first)
            == axis.removingCoordinate(from: second)
    }

    private struct FaceSurface {
        let face: Face
        let surface: BSplineSurface3D
    }

    private struct Cap {
        let face: Face
        let surface: BSplineSurface3D
        let coordinate: Double
    }

    private enum Axis: CaseIterable {
        case x
        case y
        case z

        func coordinate(of point: Point3D) -> Double {
            switch self {
            case .x: point.x
            case .y: point.y
            case .z: point.z
            }
        }

        func removingCoordinate(from point: Point3D) -> Point2D {
            switch self {
            case .x: Point2D(x: point.y, y: point.z)
            case .y: Point2D(x: point.z, y: point.x)
            case .z: Point2D(x: point.x, y: point.y)
            }
        }

        func point(at coordinate: Double) -> Point3D {
            switch self {
            case .x: Point3D(x: coordinate, y: 0.0, z: 0.0)
            case .y: Point3D(x: 0.0, y: coordinate, z: 0.0)
            case .z: Point3D(x: 0.0, y: 0.0, z: coordinate)
            }
        }
    }
}
