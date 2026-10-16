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

    struct Sample {
        let point: Point3D
        let parameter: SurfaceParameter
    }

    private enum Membership {
        case spatial(any FacePointContainmentTesting)
        case originalParameter(any FacePointContainmentSession)

        func contains(_ point: Point3D, parameter: SurfaceParameter, on faceID: FaceID,
            in model: BRepModel, tolerance: ModelingTolerance,
            using execution: inout OriginalQueryExecution) throws -> Bool {
            switch self {
            case .spatial(let tester):
                return try tester.contains(point, on: faceID, in: model,
                    tolerance: tolerance, using: &execution)
            case .originalParameter(let session):
                // FIXME(INCOMPLETE_IMPLEMENTATION): An injected session may lack original-parameter membership.
                // Known-chart Face Rebuild sampling refuses until this session supplies its real same-execution predicate.
                guard let membership = try session.containsParameter(parameter, on: faceID,
                    using: &execution) else {
                    throw KernelError(phase: .classification, code: .unsupportedCapability,
                        tolerance: tolerance,
                        message: "Known-chart face sampling requires original-parameter containment.")
                }
                return membership
            }
        }
    }

    func point(
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        return try sample(on: faceID, in: model, tolerance: tolerance, using: &execution).point
    }

    /// A point inside the trimmed face with its surface parameter.
    func sample(
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Sample {
        try sample(on: faceID, in: model, tolerance: tolerance,
            membership: .spatial(containmentTester), using: &execution)
    }

    /// The caller prepares this session from this same original face and model.
    /// Candidate parameters are authored in that face's chart before point evaluation.
    func sample(
        on faceID: FaceID,
        in model: BRepModel,
        parameterContainmentSession: any FacePointContainmentSession,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Sample {
        try sample(on: faceID, in: model, tolerance: tolerance,
            membership: .originalParameter(parameterContainmentSession), using: &execution)
    }

    private func sample(
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        membership: Membership,
        using execution: inout OriginalQueryExecution
    ) throws -> Sample {
        try execution.consumeWork(1)
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
                    if let sample = try interiorPoint(
                        near: fraction,
                        pcurve: pcurve,
                        faceID: faceID,
                        surface: surface,
                        model: model,
                        tolerance: tolerance,
                        membership: membership
                    , using: &execution) {
                        return sample
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
        tolerance: ModelingTolerance,
        membership: Membership
    , using execution: inout OriginalQueryExecution) throws -> Sample? {
        try execution.consumeWork(1)
        let derivativeFraction = 1.0e-4
        let lowerFraction = max(fraction - derivativeFraction, 0.0)
        let upperFraction = min(fraction + derivativeFraction, 1.0)
        let center = try pcurve.parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
        let lower = try pcurve.parameter(
            atNormalizedFraction: lowerFraction,
            tolerance: tolerance
        , using: &execution)
        let upper = try pcurve.parameter(
            atNormalizedFraction: upperFraction,
            tolerance: tolerance
        , using: &execution)
        let tangentU = upper.u - lower.u
        let tangentV = upper.v - lower.v
        let tangentLength = hypot(tangentU, tangentV)
        guard tangentLength > Double.ulpOfOne else { return nil }
        let start = try pcurve.startParameter(tolerance: tolerance, using: &execution)
        let end = try pcurve.endParameter(tolerance: tolerance, using: &execution)
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
                    , using: &execution)
                    if try membership.contains(
                        candidate,
                        parameter: parameter,
                        on: faceID,
                        in: model,
                        tolerance: tolerance
                    , using: &execution) {
                        return Sample(point: candidate, parameter: parameter)
                    }
                } catch GeometryError.invalidDistance {
                    continue
                } catch let error where OriginalQueryFailure.classification(of: error)?.code == .intersectionFailure {
            guard let errorClassification = OriginalQueryFailure.classification(of: error) else { throw error }
                    continue
                }
            }
        }
        return nil
    }
}
