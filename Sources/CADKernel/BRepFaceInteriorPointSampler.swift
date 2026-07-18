import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

struct BRepFaceInteriorPointSampler {
    private let containmentTester: any FacePointContainmentTesting

    init(
        containmentTester: any FacePointContainmentTesting = DefaultFacePointContainmentTester()
    ) {
        self.containmentTester = containmentTester
    }

    func point(
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try tolerance.validate()
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(
                phase: .classification,
                code: .missingReference,
                tolerance: tolerance,
                message: "Face interior sampling references missing face geometry."
            )
        }
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Face interior sampling references a missing loop."
                )
            }
            guard loop.role == .outer else { continue }
            for coedge in loop.coedges {
                guard let pcurve = coedge.surfaceParameterCurve else {
                    throw KernelError(
                        phase: .classification,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Exact face interior sampling requires face-local pcurves."
                    )
                }
                for fraction in [0.5, 0.25, 0.75] {
                    if let point = try interiorPoint(
                        near: fraction,
                        pcurve: pcurve,
                        faceID: faceID,
                        surface: surface,
                        model: model,
                        tolerance: tolerance
                    ) {
                        return point
                    }
                }
            }
        }
        throw KernelError(
            phase: .classification,
            code: .classificationFailure,
            tolerance: tolerance,
            message: "No deterministic non-boundary point could be found on the exact trimmed face."
        )
    }

    private func interiorPoint(
        near fraction: Double,
        pcurve: SurfaceParameterCurve,
        faceID: FaceID,
        surface: Surface3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Point3D? {
        let derivativeFraction = 1.0e-4
        let lowerFraction = max(fraction - derivativeFraction, 0.0)
        let upperFraction = min(fraction + derivativeFraction, 1.0)
        let center = try pcurve.parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let lower = try pcurve.parameter(
            atNormalizedFraction: lowerFraction,
            tolerance: tolerance
        )
        let upper = try pcurve.parameter(
            atNormalizedFraction: upperFraction,
            tolerance: tolerance
        )
        let tangentU = upper.u - lower.u
        let tangentV = upper.v - lower.v
        let tangentLength = hypot(tangentU, tangentV)
        guard tangentLength > Double.ulpOfOne else { return nil }
        let start = try pcurve.startParameter(tolerance: tolerance)
        let end = try pcurve.endParameter(tolerance: tolerance)
        let span = max(
            hypot(end.u - start.u, end.v - start.v),
            tangentLength / max(upperFraction - lowerFraction, Double.ulpOfOne)
        )
        let minimumOffset = tolerance.distance * 8.0
        let baseOffset = max(span * 0.0025, minimumOffset)
        for multiplier in [1.0, 2.0, 4.0, 8.0, 16.0, 32.0] {
            let offset = min(baseOffset * multiplier, max(span * 0.25, minimumOffset))
            let normalU = -tangentV / tangentLength
            let normalV = tangentU / tangentLength
            for sign in [1.0, -1.0] {
                let parameter = SurfaceParameter(
                    u: center.u + normalU * offset * sign,
                    v: center.v + normalV * offset * sign
                )
                do {
                    let candidate = try surface.point(
                        u: parameter.u,
                        v: parameter.v,
                        tolerance: tolerance
                    )
                    if try containmentTester.contains(
                        candidate,
                        on: faceID,
                        in: model,
                        tolerance: tolerance
                    ) {
                        return candidate
                    }
                } catch GeometryError.invalidDistance {
                    continue
                } catch let error as KernelError where error.code == .intersectionFailure {
                    continue
                }
            }
        }
        return nil
    }
}
