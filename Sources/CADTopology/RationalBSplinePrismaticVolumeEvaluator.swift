import CADCore
import CADGeometry
import Foundation

/// Evaluates an axis-aligned rational B-spline prism after proving that every
/// side control net is an exact translation between two planar caps.
struct RationalBSplinePrismaticVolumeEvaluator {
    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        try tolerance.validate()
        var faces: [FaceSurface] = []
        faces.reserveCapacity(shell.faceIDs.count)
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let geometry = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Rational prism volume references missing face geometry."
                )
            }
            guard case let .bSpline(surface) = geometry else {
                return nil
            }
            faces.append(FaceSurface(face: face, surface: surface))
        }
        for axis in Axis.allCases {
            let caps = faces.compactMap { candidate in
                planarCoordinate(of: candidate.surface, axis: axis).map {
                    Cap(face: candidate.face, surface: candidate.surface, coordinate: $0)
                }
            }
            guard caps.count == 2 else { continue }
            let orderedCaps = caps.sorted { $0.coordinate < $1.coordinate }
            let lower = orderedCaps[0]
            let upper = orderedCaps[1]
            let height = upper.coordinate - lower.coordinate
            guard height > tolerance.distance,
                  model.vertices.values.allSatisfy({ vertex in
                      let coordinate = axis.coordinate(of: vertex.point)
                      return coordinate == lower.coordinate
                          || coordinate == upper.coordinate
                  }) else {
                continue
            }
            let capFaceIDs = Set([lower.face.id, upper.face.id])
            let sides = faces.filter { !capFaceIDs.contains($0.face.id) }
            guard !sides.isEmpty,
                  sides.allSatisfy({
                      isExactTranslatedSide(
                          $0.surface,
                          axis: axis,
                          lower: lower.coordinate,
                          upper: upper.coordinate
                      )
                  }) else {
                continue
            }
            guard let contribution = try upperCapContribution(
                upper,
                lowerCoordinate: lower.coordinate,
                axis: axis,
                model: model,
                tolerance: tolerance
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
        tolerance: ModelingTolerance
    ) throws -> TrimmedParametricSurfaceVolumeEvaluator.VolumeBounds? {
        let loopCount = cap.face.loops.count
        guard loopCount > 0 else { return nil }
        var lower = 0.0
        var upper = 0.0
        let requestedWidth = tolerance.distance / (3.0 * Double(loopCount))
        let reference = axis.point(at: lowerCoordinate)
        for loopID in cap.face.loops {
            guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
                throw TopologyError.missingReference(
                    "Rational prism cap references a missing or empty loop."
                )
            }
            let curves = try loop.coedges.map { coedge -> SurfaceParameterCurve in
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
                    tolerance: tolerance
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
        axis: Axis
    ) -> Double? {
        guard let coordinate = surface.controlPoints.first?.first.map({
            axis.coordinate(of: $0)
        }), surface.controlPoints.allSatisfy({ row in
            !row.isEmpty && row.allSatisfy {
                axis.coordinate(of: $0) == coordinate
            }
        }) else {
            return nil
        }
        return coordinate
    }

    private func isExactTranslatedSide(
        _ surface: BSplineSurface3D,
        axis: Axis,
        lower: Double,
        upper: Double
    ) -> Bool {
        if surface.vDegree == 1,
           surface.vControlPointCount == 2,
           let first = surface.controlPoints.first,
           let second = surface.controlPoints.last,
           first.count == second.count,
           surface.weights.count == 2,
           surface.weights[0].count == surface.weights[1].count,
           surface.weights[0].count == first.count {
            return zip(first.indices, surface.weights[0].indices).allSatisfy {
                translatedPairIsExact(
                    first[$0.0],
                    second[$0.0],
                    firstWeight: surface.weights[0][$0.1],
                    secondWeight: surface.weights[1][$0.1],
                    axis: axis,
                    lower: lower,
                    upper: upper
                )
            }
        }
        if surface.uDegree == 1,
           surface.uControlPointCount == 2,
           surface.controlPoints.allSatisfy({ $0.count == 2 }),
           surface.weights.count == surface.controlPoints.count,
           surface.weights.allSatisfy({ $0.count == 2 }) {
            return surface.controlPoints.indices.allSatisfy { index in
                translatedPairIsExact(
                    surface.controlPoints[index][0],
                    surface.controlPoints[index][1],
                    firstWeight: surface.weights[index][0],
                    secondWeight: surface.weights[index][1],
                    axis: axis,
                    lower: lower,
                    upper: upper
                )
            }
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
