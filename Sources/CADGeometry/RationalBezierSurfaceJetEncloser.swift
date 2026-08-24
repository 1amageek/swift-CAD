import CADCore

struct RationalBezierSurfaceJetEncloser: Sendable {
    private struct HomogeneousJetControls {
        let value: [[IntervalHomogeneousSurfaceControl]]
        let derivativeU: [[IntervalHomogeneousSurfaceControl]]
        let derivativeV: [[IntervalHomogeneousSurfaceControl]]
        let secondDerivativeUU: [[IntervalHomogeneousSurfaceControl]]
        let secondDerivativeUV: [[IntervalHomogeneousSurfaceControl]]
        let secondDerivativeVV: [[IntervalHomogeneousSurfaceControl]]
        let thirdDerivativeUUU: [[IntervalHomogeneousSurfaceControl]]
        let thirdDerivativeUUV: [[IntervalHomogeneousSurfaceControl]]
        let thirdDerivativeUVV: [[IntervalHomogeneousSurfaceControl]]
        let thirdDerivativeVVV: [[IntervalHomogeneousSurfaceControl]]
    }

    func enclosure(
        of patch: RationalBezierSurfacePatch3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        try enclosure(
            of: patch,
            u: ScalarInterval(lower: patch.uLower, upper: patch.uUpper),
            v: ScalarInterval(lower: patch.vLower, upper: patch.vUpper),
            tolerance: tolerance
        )
    }

    func enclosure(
        of patch: RationalBezierSurfacePatch3D,
        u: ScalarInterval,
        v: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        guard patch.controlPoints.isEmpty == false,
              patch.controlPoints.count == patch.weights.count,
              let uCount = patch.controlPoints.first?.count,
              uCount > 0,
              patch.controlPoints.indices.allSatisfy({
                  patch.controlPoints[$0].count == uCount
                      && patch.weights[$0].count == uCount
              }),
              u.lower >= patch.uLower,
              u.upper <= patch.uUpper,
              v.lower >= patch.vLower,
              v.upper <= patch.vUpper else {
            throw invalidPatchError(tolerance: tolerance)
        }
        var controls: [[IntervalHomogeneousSurfaceControl]] = []
        controls.reserveCapacity(patch.controlPoints.count)
        for vIndex in patch.controlPoints.indices {
            var row: [IntervalHomogeneousSurfaceControl] = []
            row.reserveCapacity(uCount)
            for uIndex in patch.controlPoints[vIndex].indices {
                let point = patch.controlPoints[vIndex][uIndex]
                let weight = patch.weights[vIndex][uIndex]
                guard weight.isFinite, weight > 0.0 else {
                    throw invalidPatchError(tolerance: tolerance)
                }
                let intervalWeight = OutwardScalarInterval(weight)
                row.append(IntervalHomogeneousSurfaceControl(
                    x: OutwardScalarInterval(point.x) * intervalWeight,
                    y: OutwardScalarInterval(point.y) * intervalWeight,
                    z: OutwardScalarInterval(point.z) * intervalWeight,
                    weight: intervalWeight
                ))
            }
            controls.append(row)
        }
        let localized = try localizedJetControls(
            try derivativeJetControls(
                controls,
                uSpan: patch.uUpper - patch.uLower,
                vSpan: patch.vUpper - patch.vLower,
                tolerance: tolerance
            ),
            sourceULower: patch.uLower,
            sourceUUpper: patch.uUpper,
            sourceVLower: patch.vLower,
            sourceVUpper: patch.vUpper,
            targetU: u,
            targetV: v,
            tolerance: tolerance
        )
        let x = scalarJet(localized, component: \IntervalHomogeneousSurfaceControl.x)
        let y = scalarJet(localized, component: \IntervalHomogeneousSurfaceControl.y)
        let z = scalarJet(localized, component: \IntervalHomogeneousSurfaceControl.z)
        let weight = scalarJet(
            localized,
            component: \IntervalHomogeneousSurfaceControl.weight
        )
        guard let reciprocalWeight = weight.reciprocal() else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: weight.value.lower,
                tolerance: tolerance,
                message: "A rational surface enclosure requires a certified positive weight range."
            )
        }
        return SurfaceIntervalVectorJet(
            x: x * reciprocalWeight,
            y: y * reciprocalWeight,
            z: z * reciprocalWeight
        )
    }

    private func derivativeJetControls(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        uSpan: Double,
        vSpan: Double,
        tolerance: ModelingTolerance
    ) throws -> HomogeneousJetControls {
        guard uSpan.isFinite, uSpan > 0.0,
              vSpan.isFinite, vSpan > 0.0 else {
            throw invalidPatchError(tolerance: tolerance)
        }
        let derivativeU = try differentiatedU(
            controls,
            span: uSpan,
            tolerance: tolerance
        )
        let derivativeV = try differentiatedV(
            controls,
            span: vSpan,
            tolerance: tolerance
        )
        let secondDerivativeUU = try differentiatedU(
            derivativeU,
            span: uSpan,
            tolerance: tolerance
        )
        let secondDerivativeUV = try differentiatedV(
            derivativeU,
            span: vSpan,
            tolerance: tolerance
        )
        let secondDerivativeVV = try differentiatedV(
            derivativeV,
            span: vSpan,
            tolerance: tolerance
        )
        let thirdDerivativeUUU = try differentiatedU(
            secondDerivativeUU,
            span: uSpan,
            tolerance: tolerance
        )
        let thirdDerivativeUUV = try differentiatedV(
            secondDerivativeUU,
            span: vSpan,
            tolerance: tolerance
        )
        let thirdDerivativeUVV = try differentiatedV(
            secondDerivativeUV,
            span: vSpan,
            tolerance: tolerance
        )
        let thirdDerivativeVVV = try differentiatedV(
            secondDerivativeVV,
            span: vSpan,
            tolerance: tolerance
        )
        return HomogeneousJetControls(
            value: controls,
            derivativeU: derivativeU,
            derivativeV: derivativeV,
            secondDerivativeUU: secondDerivativeUU,
            secondDerivativeUV: secondDerivativeUV,
            secondDerivativeVV: secondDerivativeVV,
            thirdDerivativeUUU: thirdDerivativeUUU,
            thirdDerivativeUUV: thirdDerivativeUUV,
            thirdDerivativeUVV: thirdDerivativeUVV,
            thirdDerivativeVVV: thirdDerivativeVVV
        )
    }

    private func differentiatedU(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        span: Double,
        tolerance: ModelingTolerance
    ) throws -> [[IntervalHomogeneousSurfaceControl]] {
        guard let count = controls.first?.count, count > 1 else {
            return controls.map { _ in [.zero] }
        }
        guard let scale = OutwardScalarInterval(Double(count - 1)).divided(
            by: OutwardScalarInterval(span)
        ) else {
            throw invalidPatchError(tolerance: tolerance)
        }
        return controls.map { row in
            (0..<(count - 1)).map { index in
                row[index + 1].subtracting(row[index]).scaled(by: scale)
            }
        }
    }

    private func differentiatedV(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        span: Double,
        tolerance: ModelingTolerance
    ) throws -> [[IntervalHomogeneousSurfaceControl]] {
        guard controls.count > 1,
              let count = controls.first?.count else {
            return [Array(
                repeating: .zero,
                count: controls.first?.count ?? 1
            )]
        }
        guard let scale = OutwardScalarInterval(
            Double(controls.count - 1)
        ).divided(by: OutwardScalarInterval(span)) else {
            throw invalidPatchError(tolerance: tolerance)
        }
        return (0..<(controls.count - 1)).map { rowIndex in
            (0..<count).map { columnIndex in
                controls[rowIndex + 1][columnIndex]
                    .subtracting(controls[rowIndex][columnIndex])
                    .scaled(by: scale)
            }
        }
    }

    private func localizedJetControls(
        _ controls: HomogeneousJetControls,
        sourceULower: Double,
        sourceUUpper: Double,
        sourceVLower: Double,
        sourceVUpper: Double,
        targetU: ScalarInterval,
        targetV: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> HomogeneousJetControls {
        func localized(
            _ values: [[IntervalHomogeneousSurfaceControl]]
        ) throws -> [[IntervalHomogeneousSurfaceControl]] {
            try trimmedControls(
                values,
                sourceULower: sourceULower,
                sourceUUpper: sourceUUpper,
                sourceVLower: sourceVLower,
                sourceVUpper: sourceVUpper,
                targetU: targetU,
                targetV: targetV,
                tolerance: tolerance
            )
        }
        return try HomogeneousJetControls(
            value: localized(controls.value),
            derivativeU: localized(controls.derivativeU),
            derivativeV: localized(controls.derivativeV),
            secondDerivativeUU: localized(controls.secondDerivativeUU),
            secondDerivativeUV: localized(controls.secondDerivativeUV),
            secondDerivativeVV: localized(controls.secondDerivativeVV),
            thirdDerivativeUUU: localized(controls.thirdDerivativeUUU),
            thirdDerivativeUUV: localized(controls.thirdDerivativeUUV),
            thirdDerivativeUVV: localized(controls.thirdDerivativeUVV),
            thirdDerivativeVVV: localized(controls.thirdDerivativeVVV)
        )
    }

    private func scalarJet(
        _ controls: HomogeneousJetControls,
        component: KeyPath<IntervalHomogeneousSurfaceControl, OutwardScalarInterval>
    ) -> SurfaceIntervalJet {
        func enclosure(
            _ values: [[IntervalHomogeneousSurfaceControl]]
        ) -> OutwardScalarInterval {
            .enclosing(values.flatMap { row in
                row.map { $0[keyPath: component] }
            })
        }
        return SurfaceIntervalJet(
            value: enclosure(controls.value),
            derivativeU: enclosure(controls.derivativeU),
            derivativeV: enclosure(controls.derivativeV),
            secondDerivativeUU: enclosure(controls.secondDerivativeUU),
            secondDerivativeUV: enclosure(controls.secondDerivativeUV),
            secondDerivativeVV: enclosure(controls.secondDerivativeVV),
            thirdDerivativeUUU: enclosure(controls.thirdDerivativeUUU),
            thirdDerivativeUUV: enclosure(controls.thirdDerivativeUUV),
            thirdDerivativeUVV: enclosure(controls.thirdDerivativeUVV),
            thirdDerivativeVVV: enclosure(controls.thirdDerivativeVVV)
        )
    }

    private func trimmedControls(
        _ source: [[IntervalHomogeneousSurfaceControl]],
        sourceULower: Double,
        sourceUUpper: Double,
        sourceVLower: Double,
        sourceVUpper: Double,
        targetU: ScalarInterval,
        targetV: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> [[IntervalHomogeneousSurfaceControl]] {
        var controls = source
        var currentULower = sourceULower
        if targetU.lower > currentULower {
            let parameter = try normalizedParameter(
                targetU.lower,
                lower: currentULower,
                upper: sourceUUpper,
                tolerance: tolerance
            )
            controls = splitU(controls, parameter: parameter).upper
            currentULower = targetU.lower
        }
        if targetU.upper < sourceUUpper {
            let parameter = try normalizedParameter(
                targetU.upper,
                lower: currentULower,
                upper: sourceUUpper,
                tolerance: tolerance
            )
            controls = splitU(controls, parameter: parameter).lower
        }
        var currentVLower = sourceVLower
        if targetV.lower > currentVLower {
            let parameter = try normalizedParameter(
                targetV.lower,
                lower: currentVLower,
                upper: sourceVUpper,
                tolerance: tolerance
            )
            controls = splitV(controls, parameter: parameter).upper
            currentVLower = targetV.lower
        }
        if targetV.upper < sourceVUpper {
            let parameter = try normalizedParameter(
                targetV.upper,
                lower: currentVLower,
                upper: sourceVUpper,
                tolerance: tolerance
            )
            controls = splitV(controls, parameter: parameter).lower
        }
        return controls
    }

    private func normalizedParameter(
        _ value: Double,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> OutwardScalarInterval {
        let numerator = OutwardScalarInterval(value)
            - OutwardScalarInterval(lower)
        let denominator = OutwardScalarInterval(upper)
            - OutwardScalarInterval(lower)
        guard let parameter = numerator.divided(by: denominator),
              parameter.isFinite else {
            throw invalidPatchError(tolerance: tolerance)
        }
        return parameter
    }

    private func splitU(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        parameter: OutwardScalarInterval
    ) -> (
        lower: [[IntervalHomogeneousSurfaceControl]],
        upper: [[IntervalHomogeneousSurfaceControl]]
    ) {
        let splits = controls.map { split($0, parameter: parameter) }
        return (splits.map(\.lower), splits.map(\.upper))
    }

    private func splitV(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        parameter: OutwardScalarInterval
    ) -> (
        lower: [[IntervalHomogeneousSurfaceControl]],
        upper: [[IntervalHomogeneousSurfaceControl]]
    ) {
        guard controls.count > 1 else { return (controls, controls) }
        var levels = [controls]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { rowIndex in
                previous[rowIndex].indices.map { columnIndex in
                    previous[rowIndex][columnIndex].interpolated(
                        to: previous[rowIndex + 1][columnIndex],
                        parameter: parameter
                    )
                }
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func split(
        _ controls: [IntervalHomogeneousSurfaceControl],
        parameter: OutwardScalarInterval
    ) -> (
        lower: [IntervalHomogeneousSurfaceControl],
        upper: [IntervalHomogeneousSurfaceControl]
    ) {
        guard controls.count > 1 else { return (controls, controls) }
        var levels = [controls]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].interpolated(
                    to: previous[index + 1],
                    parameter: parameter
                )
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func invalidPatchError(tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .invalidInput,
            tolerance: tolerance,
            message: "A rational Bezier surface enclosure requires a finite rectangular control net."
        )
    }
}

private struct IntervalHomogeneousSurfaceControl: Sendable {
    let x: OutwardScalarInterval
    let y: OutwardScalarInterval
    let z: OutwardScalarInterval
    let weight: OutwardScalarInterval

    static let zero = IntervalHomogeneousSurfaceControl(
        x: OutwardScalarInterval(0.0),
        y: OutwardScalarInterval(0.0),
        z: OutwardScalarInterval(0.0),
        weight: OutwardScalarInterval(0.0)
    )

    func subtracting(
        _ other: IntervalHomogeneousSurfaceControl
    ) -> IntervalHomogeneousSurfaceControl {
        IntervalHomogeneousSurfaceControl(
            x: x - other.x,
            y: y - other.y,
            z: z - other.z,
            weight: weight - other.weight
        )
    }

    func scaled(
        by scale: OutwardScalarInterval
    ) -> IntervalHomogeneousSurfaceControl {
        IntervalHomogeneousSurfaceControl(
            x: x * scale,
            y: y * scale,
            z: z * scale,
            weight: weight * scale
        )
    }

    func interpolated(
        to other: IntervalHomogeneousSurfaceControl,
        parameter: OutwardScalarInterval
    ) -> IntervalHomogeneousSurfaceControl {
        let complement = OutwardScalarInterval(1.0) - parameter
        return IntervalHomogeneousSurfaceControl(
            x: x * complement + other.x * parameter,
            y: y * complement + other.y * parameter,
            z: z * complement + other.z * parameter,
            weight: weight * complement + other.weight * parameter
        )
    }
}
