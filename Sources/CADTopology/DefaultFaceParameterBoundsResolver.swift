import CADCore
import CADGeometry

package struct DefaultFaceParameterBoundsResolver: FaceParameterBoundsResolving {
    private let rectangularDomainResolver:
        any ExactRectangularPcurveDomainResolving

    package init(
        rectangularDomainResolver:
            any ExactRectangularPcurveDomainResolving =
                ExactRectangularPcurveDomainResolver()
    ) {
        self.rectangularDomainResolver = rectangularDomainResolver
    }

    package func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterBox {
        try tolerance.validate()
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Face parameter bounds reference a missing face or support surface."
            )
        }
        if face.loops.isEmpty {
            return SurfaceParameterBox(
                u: try finiteInterval(
                    surface.uDomain,
                    direction: "u",
                    tolerance: tolerance
                ),
                v: try finiteInterval(
                    surface.vDomain,
                    direction: "v",
                    tolerance: tolerance
                )
            )
        }
        if let rectangle = try rectangularDomainResolver.resolve(
            face: face,
            model: model,
            tolerance: tolerance
        ) {
            return SurfaceParameterBox(
                u: try ScalarInterval(
                    lower: rectangle.uLower,
                    upper: rectangle.uUpper
                ),
                v: try ScalarInterval(
                    lower: rectangle.vLower,
                    upper: rectangle.vUpper
                )
            )
        }

        var lowerU = Double.infinity
        var upperU = -Double.infinity
        var lowerV = Double.infinity
        var upperV = -Double.infinity
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Face parameter bounds reference a missing loop."
                )
            }
            for coedge in loop.coedges {
                guard let pcurve = coedge.surfaceParameterCurve else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A bounded face requires an exact pcurve on every coedge."
                    )
                }
                let enclosures = try CertifiedSurfaceParameterCurveEncloser()
                    .enclosures(
                        for: pcurve,
                        maximumWidth: 0.25,
                        tolerance: tolerance
                    )
                guard enclosures.isEmpty == false else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A face pcurve produced no certified parameter enclosure."
                    )
                }
                for enclosure in enclosures {
                    lowerU = min(lowerU, enclosure.u.lower)
                    upperU = max(upperU, enclosure.u.upper)
                    lowerV = min(lowerV, enclosure.v.lower)
                    upperV = max(upperV, enclosure.v.upper)
                }
            }
        }
        guard lowerU.isFinite,
              upperU.isFinite,
              lowerV.isFinite,
              upperV.isFinite,
              upperU > lowerU,
              upperV > lowerV else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A bounded face requires a nondegenerate certified pcurve domain."
            )
        }
        return SurfaceParameterBox(
            u: try ScalarInterval(lower: lowerU, upper: upperU),
            v: try ScalarInterval(lower: lowerV, upper: upperV)
        )
    }

    private func finiteInterval(
        _ domain: ParameterDomain,
        direction: String,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        switch domain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            return try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An untrimmed face with an unbounded \(direction)-domain has no finite parameter bounds."
            )
        }
    }
}
