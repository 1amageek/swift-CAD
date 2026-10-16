import HashTreeCollections
import CADCore
import CADGeometry

package struct DefaultFaceParameterBoundsResolver: FaceParameterBoundsResolving {
    private let maximumSubdivisionDepth: Int
    private let remainingSourceDepth: Int
    private let maximumAlgebraicDepth: Int
    private let rectangularDomainResolver:
        any ExactRectangularPcurveDomainResolving

    package init(
        rectangularDomainResolver:
            any ExactRectangularPcurveDomainResolving =
                ExactRectangularPcurveDomainResolver(),
        maximumSubdivisionDepth: Int = 48,
        remainingSourceDepth: Int = 16,
        maximumAlgebraicDepth: Int = 32
    ) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.remainingSourceDepth = min(16, remainingSourceDepth)
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.rectangularDomainResolver = rectangularDomainResolver
    }

    package func bounds(for faceID: FaceID, in model: BRepModel, tolerance: ModelingTolerance) throws -> SurfaceParameterBox {
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: maximumAlgebraicDepth,
                maximumCoefficientDepth: maximumAlgebraicDepth,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth))
        return try bounds(for: faceID, in: model, tolerance: tolerance, using: &execution)
    }

    package func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> SurfaceParameterBox {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard (0...32).contains(maximumAlgebraicDepth) else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                message: "Original face parameter algebra depth must lie in 0...32.")
        }
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
            tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution) {
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
                try execution.consumeWork(1)
                guard let pcurve = coedge.surfaceParameterCurve else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A bounded face requires an exact pcurve on every coedge."
                    )
                }
                let enclosures = try CertifiedSurfaceParameterCurveEncloser(maximumSubdivisionDepth: maximumSubdivisionDepth,
                                maximumAlgebraicDepth: maximumAlgebraicDepth, remainingSourceDepth: remainingSourceDepth)
                    .enclosures(
                        for: pcurve,
                        on: surface,
                        maximumWidth: 0.25,
                        tolerance: tolerance, using: &execution)
                guard enclosures.isEmpty == false else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A face pcurve produced no certified parameter enclosure."
                    )
                }
                for enclosure in enclosures {
                    try execution.consumeWork(1)
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
