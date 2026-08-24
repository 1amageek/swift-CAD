import CADCore
import Foundation

package struct SurfaceTessellationDifferentialBounds: Sendable {
    package let tangentUMagnitudeUpperBound: Double
    package let tangentVMagnitudeUpperBound: Double
    package let secondDerivativeUUMagnitudeUpperBound: Double
    package let secondDerivativeUVMagnitudeUpperBound: Double
    package let secondDerivativeVVMagnitudeUpperBound: Double
    package let unitNormalDerivativeUMagnitudeUpperBound: Double
    package let unitNormalDerivativeVMagnitudeUpperBound: Double
}

extension DefaultSurfaceDifferentialEncloser {
    package func tessellationBounds(
        of surface: Surface3D,
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> SurfaceTessellationDifferentialBounds {
        try tolerance.validate()
        try parameters.validate(for: surface, tolerance: tolerance)

        struct Cell {
            let parameters: SurfaceParameterBox
            let depth: Int
        }

        let maximumDepth = 32
        let maximumCellCount = 262_144
        var remainingCells = maximumCellCount
        var pending = [Cell(parameters: parameters, depth: 0)]
        var aggregate: SurfaceTessellationDifferentialBounds?

        while let cell = pending.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Surface tessellation bounds exhausted their certified cell budget."
                )
            }
            remainingCells -= 1

            if let local = try certifiedTessellationBounds(
                of: surface,
                over: cell.parameters,
                tolerance: tolerance
            ) {
                aggregate = aggregate.map { union($0, local) } ?? local
                continue
            }

            let differential = try surface.parameterDerivatives(
                atU: cell.parameters.u.midpoint,
                v: cell.parameters.v.midpoint,
                tolerance: tolerance
            )
            guard isRegular(differential, tolerance: tolerance) else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "Surface tessellation encountered a singular tangent frame."
                )
            }
            guard cell.depth < maximumDepth else {
                let diagnostic = tessellationCertificationDiagnostic(
                    of: surface,
                    over: cell.parameters,
                    tolerance: tolerance
                )
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: max(
                        cell.parameters.u.width,
                        cell.parameters.v.width
                    ),
                    tolerance: tolerance,
                    message: "Surface tessellation of \(tessellationSurfaceKind(surface)) could not certify differential bounds at U [\(cell.parameters.u.lower), \(cell.parameters.u.upper)] and V [\(cell.parameters.v.lower), \(cell.parameters.v.upper)] within the subdivision limit. \(diagnostic)"
                )
            }
            let children = try subdivided(
                cell.parameters,
                surface: surface,
                depth: cell.depth + 1
            )
            pending.append(contentsOf: children.reversed().map {
                Cell(parameters: $0, depth: cell.depth + 1)
            })
        }

        guard let aggregate else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface tessellation requires a nonempty parameter region."
            )
        }
        return aggregate
    }

    private func certifiedTessellationBounds(
        of surface: Surface3D,
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> SurfaceTessellationDifferentialBounds? {
        let jet: SurfaceIntervalVectorJet
        do {
            jet = try intervalJet(
                of: surface,
                over: parameters,
                tolerance: tolerance
            )
        } catch let error as KernelError where error.code == .singularSystem {
            return nil
        }
        let tangentU = jet.differentiatedUThroughSecondOrder()
        let tangentV = jet.differentiatedVThroughSecondOrder()
        let normal = tangentU.cross(tangentV)
        let tangentUSquared = tangentU.dot(tangentU).value
        let tangentVSquared = tangentV.dot(tangentV).value
        let normalSquared = normal.dot(normal).value
        let tangentUUpper = squareRootUpper(tangentUSquared)
        let tangentVUpper = squareRootUpper(tangentVSquared)
        let normalLower = squareRootLower(normalSquared)
        let sineTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        let minimumTangentSquared = (tolerance.distance * tolerance.distance).nextUp
        let minimumNormalSquared = (
            sineTolerance * sineTolerance
                * tangentUSquared.upper * tangentVSquared.upper
        ).nextUp
        guard tangentUSquared.lower > minimumTangentSquared,
              tangentVSquared.lower > minimumTangentSquared,
              normalSquared.lower > minimumNormalSquared,
              normalLower > 0.0 else {
            return nil
        }

        let secondUU = tangentU.differentiatedUThroughSecondOrder()
        let secondUV = tangentU.differentiatedVThroughSecondOrder()
        let secondVV = tangentV.differentiatedVThroughSecondOrder()
        let normalDerivativeU = normal.differentiatedUThroughSecondOrder()
        let normalDerivativeV = normal.differentiatedVThroughSecondOrder()
        let bounds = SurfaceTessellationDifferentialBounds(
            tangentUMagnitudeUpperBound: tangentUUpper,
            tangentVMagnitudeUpperBound: tangentVUpper,
            secondDerivativeUUMagnitudeUpperBound: magnitudeUpper(secondUU),
            secondDerivativeUVMagnitudeUpperBound: magnitudeUpper(secondUV),
            secondDerivativeVVMagnitudeUpperBound: magnitudeUpper(secondVV),
            unitNormalDerivativeUMagnitudeUpperBound: (
                magnitudeUpper(normalDerivativeU) / normalLower
            ).nextUp,
            unitNormalDerivativeVMagnitudeUpperBound: (
                magnitudeUpper(normalDerivativeV) / normalLower
            ).nextUp
        )
        guard [
            bounds.tangentUMagnitudeUpperBound,
            bounds.tangentVMagnitudeUpperBound,
            bounds.secondDerivativeUUMagnitudeUpperBound,
            bounds.secondDerivativeUVMagnitudeUpperBound,
            bounds.secondDerivativeVVMagnitudeUpperBound,
            bounds.unitNormalDerivativeUMagnitudeUpperBound,
            bounds.unitNormalDerivativeVMagnitudeUpperBound,
        ].allSatisfy({ $0.isFinite && $0 >= 0.0 }) else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Surface tessellation differential bounds overflowed."
            )
        }
        return bounds
    }

    private func tessellationCertificationDiagnostic(
        of surface: Surface3D,
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) -> String {
        do {
            let jet = try intervalJet(
                of: surface,
                over: parameters,
                tolerance: tolerance
            )
            let tangentU = jet.differentiatedUThroughSecondOrder()
            let tangentV = jet.differentiatedVThroughSecondOrder()
            let tangentUSquared = tangentU.dot(tangentU).value
            let tangentVSquared = tangentV.dot(tangentV).value
            let normalSquared = tangentU.cross(tangentV)
                .dot(tangentU.cross(tangentV)).value
            let sineTolerance = max(
                sin(min(tolerance.angle, Double.pi * 0.5)),
                tolerance.relative,
                Double.ulpOfOne * 256.0
            )
            let minimumNormalSquared = (
                sineTolerance * sineTolerance
                    * tangentUSquared.upper * tangentVSquared.upper
            ).nextUp
            var sourceDetail = ""
            if case let .procedural(.offset(offset)) = surface {
                let source = try intervalJet(
                    of: offset.source,
                    over: parameters,
                    tolerance: tolerance
                )
                let sourceU = source.differentiatedUThroughSecondOrder()
                let sourceV = source.differentiatedVThroughSecondOrder()
                let rawNormal = sourceU.cross(sourceV)
                if let unitNormal = rawNormal.normalized() {
                    sourceDetail = " Source U tangent X is \(source.x.derivativeU); raw-normal squared and raw-normal U derivative X are \(rawNormal.dot(rawNormal).value) and \(rawNormal.x.derivativeU); unit-normal U derivative X is \(unitNormal.x.derivativeU); offset distance is \(offset.distance)."
                }
            }
            return "Squared tangent/normal lower bounds are \(tangentUSquared.lower), \(tangentVSquared.lower), and \(normalSquared.lower); the normal threshold is \(minimumNormalSquared).\(sourceDetail)"
        } catch {
            return "Interval-jet certification failed with \(error)."
        }
    }

    private func tessellationSurfaceKind(_ surface: Surface3D) -> String {
        switch surface {
        case .plane: return "plane"
        case .cylinder: return "cylinder"
        case .analytic: return "analytic surface"
        case .bSpline: return "B-spline surface"
        case .procedural(.offset): return "offset surface"
        case .procedural(.ruled): return "ruled surface"
        }
    }

    private func magnitudeUpper(_ jet: SurfaceIntervalVectorJet) -> Double {
        squareRootUpper(jet.dot(jet).value)
    }

    private func squareRootUpper(_ interval: OutwardScalarInterval) -> Double {
        sqrt(max(0.0, interval.upper)).nextUp
    }

    private func squareRootLower(_ interval: OutwardScalarInterval) -> Double {
        guard interval.lower > 0.0 else { return 0.0 }
        return sqrt(interval.lower).nextDown
    }

    private func union(
        _ lhs: SurfaceTessellationDifferentialBounds,
        _ rhs: SurfaceTessellationDifferentialBounds
    ) -> SurfaceTessellationDifferentialBounds {
        SurfaceTessellationDifferentialBounds(
            tangentUMagnitudeUpperBound: max(
                lhs.tangentUMagnitudeUpperBound,
                rhs.tangentUMagnitudeUpperBound
            ),
            tangentVMagnitudeUpperBound: max(
                lhs.tangentVMagnitudeUpperBound,
                rhs.tangentVMagnitudeUpperBound
            ),
            secondDerivativeUUMagnitudeUpperBound: max(
                lhs.secondDerivativeUUMagnitudeUpperBound,
                rhs.secondDerivativeUUMagnitudeUpperBound
            ),
            secondDerivativeUVMagnitudeUpperBound: max(
                lhs.secondDerivativeUVMagnitudeUpperBound,
                rhs.secondDerivativeUVMagnitudeUpperBound
            ),
            secondDerivativeVVMagnitudeUpperBound: max(
                lhs.secondDerivativeVVMagnitudeUpperBound,
                rhs.secondDerivativeVVMagnitudeUpperBound
            ),
            unitNormalDerivativeUMagnitudeUpperBound: max(
                lhs.unitNormalDerivativeUMagnitudeUpperBound,
                rhs.unitNormalDerivativeUMagnitudeUpperBound
            ),
            unitNormalDerivativeVMagnitudeUpperBound: max(
                lhs.unitNormalDerivativeVMagnitudeUpperBound,
                rhs.unitNormalDerivativeVMagnitudeUpperBound
            )
        )
    }

    private func isRegular(
        _ differential: SurfaceParameterDerivatives,
        tolerance: ModelingTolerance
    ) -> Bool {
        let tangentULength = differential.tangentU.length
        let tangentVLength = differential.tangentV.length
        guard tangentULength > tolerance.distance,
              tangentVLength > tolerance.distance else {
            return false
        }
        let sine = differential.tangentU.cross(differential.tangentV).length
            / (tangentULength * tangentVLength)
        let sineTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        return sine.isFinite && sine > sineTolerance
    }

    private func subdivided(
        _ parameters: SurfaceParameterBox,
        surface: Surface3D,
        depth: Int
    ) throws -> [SurfaceParameterBox] {
        let u = parameters.u
        let v = parameters.v
        let middleU = u.midpoint
        let middleV = v.midpoint
        let canSplitU = middleU > u.lower && middleU < u.upper
        let canSplitV = middleV > v.lower && middleV < v.upper
        guard canSplitU || canSplitV else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "Surface tessellation bounds reached the representable parameter resolution at depth \(depth)."
            )
        }
        let splitU = canSplitU && (
            canSplitV == false
                || relativeWidth(u, domain: surface.uDomain)
                    >= relativeWidth(v, domain: surface.vDomain)
        )
        if splitU {
            return [
                SurfaceParameterBox(
                    u: try ScalarInterval(lower: u.lower, upper: middleU),
                    v: v
                ),
                SurfaceParameterBox(
                    u: try ScalarInterval(lower: middleU, upper: u.upper),
                    v: v
                ),
            ]
        }
        return [
            SurfaceParameterBox(
                u: u,
                v: try ScalarInterval(lower: v.lower, upper: middleV)
            ),
            SurfaceParameterBox(
                u: u,
                v: try ScalarInterval(lower: middleV, upper: v.upper)
            ),
        ]
    }

    private func relativeWidth(
        _ interval: ScalarInterval,
        domain: ParameterDomain
    ) -> Double {
        switch domain {
        case let .closed(lower, upper):
            return interval.width / max(upper - lower, Double.leastNormalMagnitude)
        case let .periodic(period):
            return interval.width / max(period, Double.leastNormalMagnitude)
        case .unbounded:
            return interval.width
        }
    }
}
