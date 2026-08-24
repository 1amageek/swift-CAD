import Foundation
import CADCore

public struct CertifiedImplicitIntersectionCurve: Codable, Sendable, Hashable {
    public let firstSurface: BSplineSurface3D
    public let secondSurface: BSplineSurface3D
    public let cells: [CertifiedImplicitIntersectionGraphCell]
    public let isClosed: Bool
    public let certificationTolerance: ModelingTolerance

    public init(
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        cells: [CertifiedImplicitIntersectionGraphCell],
        isClosed: Bool,
        tolerance: ModelingTolerance
    ) throws {
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        self.cells = cells
        self.isClosed = isClosed
        certificationTolerance = tolerance
        try validate(tolerance: tolerance)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: max(
                    certificationTolerance.distance / tolerance.distance,
                    max(
                        certificationTolerance.angle / tolerance.angle,
                        certificationTolerance.relative / tolerance.relative
                    )
                ),
                tolerance: tolerance,
                message: "An implicit intersection certificate cannot satisfy a stricter tolerance than its stored certification tolerance."
            )
        }
        try firstSurface.validate(tolerance: tolerance)
        try secondSurface.validate(tolerance: tolerance)
        guard cells.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified implicit intersection curve requires at least one graph cell."
            )
        }
        for cell in cells {
            try cell.validate(
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
        for index in 1..<cells.count {
            try validateConnection(
                fromCell: cells[index - 1],
                toCell: cells[index],
                requiresParameterContinuity: true,
                tolerance: tolerance
            )
        }
        if isClosed {
            try validateConnection(
                fromCell: cells[cells.count - 1],
                toCell: cells[0],
                requiresParameterContinuity: false,
                tolerance: tolerance
            )
        }
    }

    public func parameterPair(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntersectionParameterPair {
        let location = try cellLocation(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        return try cells[location.index].parameterPair(
            atNormalizedFraction: location.fraction,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        let location = try cellLocation(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        return try cells[location.index].point(
            atNormalizedFraction: location.fraction,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionDifferential {
        let location = try cellLocation(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        return try cells[location.index].differential(
            atNormalizedFraction: location.fraction,
            parameterScale: Double(cells.count),
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        try differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        ).thirdDerivative
    }

    public func boundingBox(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        guard lower.isFinite,
              upper.isFinite,
              lower <= upper,
              lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        let lowerLocation = try cellLocation(
            atNormalizedFraction: min(max(lower, 0.0), 1.0),
            tolerance: tolerance
        )
        let upperLocation = try cellLocation(
            atNormalizedFraction: min(max(upper, 0.0), 1.0),
            tolerance: tolerance
        )
        var result: BoundingBox3D?
        for index in lowerLocation.index...upperLocation.index {
            let box = cells[index].parameterBox
            let patch = try firstSurface.trimmed(
                uFrom: box.firstU.lower,
                uTo: box.firstU.upper,
                vFrom: box.firstV.lower,
                vTo: box.firstV.upper,
                tolerance: tolerance
            )
            let patchBounds = try BoundingBox3D(
                points: patch.controlPoints.flatMap { $0 }
            )
            if let current = result {
                result = try current.union(patchBounds)
            } else {
                result = patchBounds
            }
        }
        guard let result else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "An implicit intersection interval did not cover a certified graph cell."
            )
        }
        return try result.expanded(by: tolerance.distance)
    }

    private func cellLocation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> (index: Int, fraction: Double) {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clamped = min(max(fraction, 0.0), 1.0)
        if clamped == 1.0 {
            return (cells.count - 1, 1.0)
        }
        let scaled = clamped * Double(cells.count)
        let index = min(Int(scaled), cells.count - 1)
        return (index, scaled - Double(index))
    }

    private func validateConnection(
        fromCell: CertifiedImplicitIntersectionGraphCell,
        toCell: CertifiedImplicitIntersectionGraphCell,
        requiresParameterContinuity: Bool,
        tolerance: ModelingTolerance
    ) throws {
        let fromParameters = fromCell.endAnchor
        let toParameters = toCell.startAnchor
        if requiresParameterContinuity {
            let parameterResidual = try maximumNormalizedParameterGap(
                from: fromParameters,
                to: toParameters
            )
            guard parameterResidual <= tolerance.relative else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: parameterResidual,
                    tolerance: tolerance,
                    message: "Certified implicit intersection graph cells are not connected in four-dimensional parameter space."
                )
            }
        }

        let fromFirstPoint = try firstSurface.point(
            u: fromParameters.first.u,
            v: fromParameters.first.v,
            tolerance: tolerance
        )
        let toFirstPoint = try firstSurface.point(
            u: toParameters.first.u,
            v: toParameters.first.v,
            tolerance: tolerance
        )
        let fromSecondPoint = try secondSurface.point(
            u: fromParameters.second.u,
            v: fromParameters.second.v,
            tolerance: tolerance
        )
        let toSecondPoint = try secondSurface.point(
            u: toParameters.second.u,
            v: toParameters.second.v,
            tolerance: tolerance
        )
        let geometricResidual = [
            (fromFirstPoint - toFirstPoint).length,
            (fromSecondPoint - toSecondPoint).length,
            (fromFirstPoint - fromSecondPoint).length,
            (toFirstPoint - toSecondPoint).length,
        ].max() ?? .infinity
        guard geometricResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: geometricResidual,
                tolerance: tolerance,
                message: "Certified implicit intersection graph cells are not connected on both source surfaces."
            )
        }

        let fromDifferential = try fromCell.differential(
            atNormalizedFraction: 1.0,
            parameterScale: 1.0,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let toDifferential = try toCell.differential(
            atNormalizedFraction: 0.0,
            parameterScale: 1.0,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let fromTangent = fromDifferential.firstDerivative
        let toTangent = toDifferential.firstDerivative
        let magnitudeProduct = fromTangent.length * toTangent.length
        let magnitudeFloor = Double.leastNonzeroMagnitude
        guard magnitudeProduct.isFinite, magnitudeProduct > magnitudeFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "A certified implicit intersection graph connection has a singular tangent."
            )
        }
        let angularResidual = fromTangent.cross(toTangent).length / magnitudeProduct
        guard fromTangent.dot(toTangent) > 0.0,
              angularResidual <= sin(tolerance.angle) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: angularResidual,
                tolerance: tolerance,
                message: "Certified implicit intersection graph cells do not preserve tangent orientation."
            )
        }
    }

    private func maximumNormalizedParameterGap(
        from: SurfaceIntersectionParameterPair,
        to: SurfaceIntersectionParameterPair
    ) throws -> Double {
        let spans = try [
            parameterSpan(firstSurface.uDomain),
            parameterSpan(firstSurface.vDomain),
            parameterSpan(secondSurface.uDomain),
            parameterSpan(secondSurface.vDomain),
        ]
        return zip(zip(from.values, to.values), spans).map { values, span in
            abs(values.0 - values.1) / span
        }.max() ?? .infinity
    }

    private func parameterSpan(_ domain: ParameterDomain) throws -> Double {
        guard case let .closed(lower, upper) = domain,
              lower.isFinite,
              upper.isFinite,
              upper > lower else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "A certified implicit intersection requires finite closed surface domains."
            )
        }
        return upper - lower
    }

    private enum CodingKeys: String, CodingKey {
        case firstSurface
        case secondSurface
        case cells
        case isClosed
        case certificationTolerance
    }

    private struct GraphCellPayload: Codable {
        let parameterBox: SurfaceIntersectionParameterBox
        let freeParameter: SurfaceIntersectionParameterCoordinate
        let direction: CertifiedImplicitIntersectionDirection
        let lowerAnchor: SurfaceIntersectionParameterPair
        let midpointAnchor: SurfaceIntersectionParameterPair
        let upperAnchor: SurfaceIntersectionParameterPair

        private enum CodingKeys: String, CodingKey {
            case parameterBox
            case freeParameter
            case direction
            case lowerAnchor
            case midpointAnchor
            case upperAnchor
        }

        init(cell: CertifiedImplicitIntersectionGraphCell) {
            parameterBox = cell.parameterBox
            freeParameter = cell.freeParameter
            direction = cell.direction
            lowerAnchor = cell.lowerAnchor
            midpointAnchor = cell.midpointAnchor
            upperAnchor = cell.upperAnchor
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try container.validateOnlyExpectedKeys(
                [
                    .parameterBox,
                    .freeParameter,
                    .direction,
                    .lowerAnchor,
                    .midpointAnchor,
                    .upperAnchor,
                ],
                in: decoder
            )
            parameterBox = try container.decode(
                SurfaceIntersectionParameterBox.self,
                forKey: .parameterBox
            )
            freeParameter = try container.decode(
                SurfaceIntersectionParameterCoordinate.self,
                forKey: .freeParameter
            )
            direction = try container.decode(
                CertifiedImplicitIntersectionDirection.self,
                forKey: .direction
            )
            lowerAnchor = try container.decode(
                SurfaceIntersectionParameterPair.self,
                forKey: .lowerAnchor
            )
            midpointAnchor = try container.decode(
                SurfaceIntersectionParameterPair.self,
                forKey: .midpointAnchor
            )
            upperAnchor = try container.decode(
                SurfaceIntersectionParameterPair.self,
                forKey: .upperAnchor
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(parameterBox, forKey: .parameterBox)
            try container.encode(freeParameter, forKey: .freeParameter)
            try container.encode(direction, forKey: .direction)
            try container.encode(lowerAnchor, forKey: .lowerAnchor)
            try container.encode(midpointAnchor, forKey: .midpointAnchor)
            try container.encode(upperAnchor, forKey: .upperAnchor)
        }

        func graphCell(
            firstSurface: BSplineSurface3D,
            secondSurface: BSplineSurface3D,
            tolerance: ModelingTolerance
        ) throws -> CertifiedImplicitIntersectionGraphCell {
            try CertifiedImplicitIntersectionGraphCell(
                parameterBox: parameterBox,
                freeParameter: freeParameter,
                direction: direction,
                lowerAnchor: lowerAnchor,
                midpointAnchor: midpointAnchor,
                upperAnchor: upperAnchor,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.firstSurface, .secondSurface, .cells, .isClosed, .certificationTolerance],
            in: decoder
        )
        let firstSurface = try container.decode(BSplineSurface3D.self, forKey: .firstSurface)
        let secondSurface = try container.decode(BSplineSurface3D.self, forKey: .secondSurface)
        let tolerance = try container.decode(ModelingTolerance.self, forKey: .certificationTolerance)
        try tolerance.validate()
        let payloads = try container.decode([GraphCellPayload].self, forKey: .cells)
        let cells = try payloads.map {
            try $0.graphCell(
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
        try self.init(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            cells: cells,
            isClosed: try container.decode(Bool.self, forKey: .isClosed),
            tolerance: tolerance
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(firstSurface, forKey: .firstSurface)
        try container.encode(secondSurface, forKey: .secondSurface)
        try container.encode(cells.map(GraphCellPayload.init), forKey: .cells)
        try container.encode(isClosed, forKey: .isClosed)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
