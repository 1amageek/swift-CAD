import Foundation
import CADCore
import CADGeometry

package struct CertifiedSurfaceParameterCurveEncloser {
    private struct ImplicitWorkItem {
        let cell: CertifiedImplicitIntersectionGraphCell
        let cellLowerFraction: Double
        let cellUpperFraction: Double
        let curveLowerFraction: Double
        let curveUpperFraction: Double
        let depth: Int
    }

    private struct RigidSphereWorkItem {
        let lowerFraction: Double
        let upperFraction: Double
        let depth: Int
    }

    private struct ParameterWorkItem {
        let lowerFraction: Double
        let upperFraction: Double
        let depth: Int
    }

    private let maximumDepth = 48
    private let maximumCellCount = 131_072

    package init() {}

    package func enclosures(
        for curve: SurfaceParameterCurve,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try enclosures(
            for: curve,
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: 1.0,
            maximumWidth: maximumWidth,
            tolerance: tolerance
        )
    }

    /// Encloses a borrowed normalized range without materializing a trimmed
    /// curve. Proof subdivision may legitimately reach ranges whose image is
    /// smaller than the modeling tolerance; those ranges are not standalone
    /// topology and must not be rejected by curve-construction invariants.
    package func enclosures(
        for curve: SurfaceParameterCurve,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try tolerance.validate()
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction,
              maximumWidth.isFinite,
              maximumWidth > 0.0 else {
            throw failure(
                .invalidInput,
                residual: upperFraction - lowerFraction,
                tolerance: tolerance,
                "Surface-parameter enclosure requires an ordered normalized range and a finite positive width."
            )
        }
        let boundedLower = min(max(lowerFraction, 0.0), 1.0)
        let boundedUpper = min(max(upperFraction, 0.0), 1.0)
        guard boundedUpper > boundedLower else {
            throw failure(
                .invalidInput,
                residual: boundedUpper - boundedLower,
                tolerance: tolerance,
                "Surface-parameter enclosure range collapsed at its normalized domain boundary."
            )
        }
        switch curve {
        case let .certifiedImplicit(certified):
            return try implicitEnclosures(
                for: certified,
                lowerFraction: boundedLower,
                upperFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        case let .certifiedAnalyticImplicit(certified):
            return try analyticImplicitEnclosures(
                for: certified,
                lowerFraction: boundedLower,
                upperFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        case .sphericalGreatCircle, .projectedAnalytic:
            return try CertifiedAnalyticPcurveFluxIntegrator()
                .parameterEnclosures(
                    for: curve,
                    fromNormalizedFraction: boundedLower,
                    toNormalizedFraction: boundedUpper,
                    maximumWidth: maximumWidth,
                    tolerance: tolerance
                )
        case let .certifiedAnalyticPair(certified):
            return try CertifiedAnalyticPairPcurveAreaIntegrator()
                .parameterEnclosures(
                    for: certified,
                    fromNormalizedFraction: boundedLower,
                    toNormalizedFraction: boundedUpper,
                    maximumWidth: maximumWidth,
                    tolerance: tolerance
                )
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline:
            return try directlyEvaluableEnclosures(
                for: curve,
                lowerFraction: boundedLower,
                upperFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        case let .rigidImage(image):
            guard let mapping = try image.affineParameterTransform(
                tolerance: tolerance
            ) else {
                return try sphericalRigidImageEnclosures(
                    for: image,
                    lowerFraction: boundedLower,
                    upperFraction: boundedUpper,
                    maximumWidth: maximumWidth,
                    tolerance: tolerance
                )
            }
            let scale = max(
                abs(mapping.uu) + abs(mapping.uv),
                abs(mapping.vu) + abs(mapping.vv),
                Double.leastNormalMagnitude
            )
            let sourceCurve = image.source.parameterCurve
            let sourceSpan = image.endFraction - image.startFraction
            let firstSourceFraction = image.startFraction
                + sourceSpan * boundedLower
            let secondSourceFraction = image.startFraction
                + sourceSpan * boundedUpper
            let sourceLower = min(firstSourceFraction, secondSourceFraction)
            let sourceUpper = max(firstSourceFraction, secondSourceFraction)
            return try enclosures(
                for: sourceCurve,
                fromNormalizedFraction: sourceLower,
                toNormalizedFraction: sourceUpper,
                maximumWidth: maximumWidth / scale,
                tolerance: tolerance
            ).map { enclosure in
                let mapped = try mapping.applying(
                    u: enclosure.u,
                    v: enclosure.v
                )
                let firstImageFraction = (
                    enclosure.lowerFraction - image.startFraction
                ) / sourceSpan
                let secondImageFraction = (
                    enclosure.upperFraction - image.startFraction
                ) / sourceSpan
                return SurfaceParameterCurveEnclosure(
                    lowerFraction: min(firstImageFraction, secondImageFraction),
                    upperFraction: max(firstImageFraction, secondImageFraction),
                    u: mapped.u,
                    v: mapped.v
                )
            }.sorted { $0.lowerFraction < $1.lowerFraction }
        case let .offsetSurfaceImage(image):
            return try enclosures(
                for: image.source,
                fromNormalizedFraction: boundedLower,
                toNormalizedFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            return try enclosures(
                for: base,
                fromNormalizedFraction: boundedLower,
                toNormalizedFraction: boundedUpper,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            ).map { enclosure in
                SurfaceParameterCurveEnclosure(
                    lowerFraction: enclosure.lowerFraction,
                    upperFraction: enclosure.upperFraction,
                    u: try ScalarInterval(
                        lower: (enclosure.u.lower + uShift).nextDown,
                        upper: (enclosure.u.upper + uShift).nextUp
                    ),
                    v: try ScalarInterval(
                        lower: (enclosure.v.lower + vShift).nextDown,
                        upper: (enclosure.v.upper + vShift).nextUp
                    )
                )
            }
        }
    }

    /// Certifies V-coordinate ranges without requiring a narrow U range at a
    /// legitimate U singularity. Other representations retain the stronger
    /// two-coordinate enclosure contract.
    package func vEnclosures(
        for curve: SurfaceParameterCurve,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        switch curve {
        case let .certifiedAnalyticPair(certified):
            return try CertifiedAnalyticPairPcurveAreaIntegrator()
                .vParameterEnclosures(
                    for: certified,
                    fromNormalizedFraction: lowerFraction,
                    toNormalizedFraction: upperFraction,
                    maximumWidth: maximumWidth,
                    tolerance: tolerance
                )
        case let .offsetSurfaceImage(image):
            return try vEnclosures(
                for: image.source,
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            return try vEnclosures(
                for: base,
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            ).map { enclosure in
                SurfaceParameterCurveEnclosure(
                    lowerFraction: enclosure.lowerFraction,
                    upperFraction: enclosure.upperFraction,
                    u: try ScalarInterval(
                        lower: (enclosure.u.lower + uShift).nextDown,
                        upper: (enclosure.u.upper + uShift).nextUp
                    ),
                    v: try ScalarInterval(
                        lower: (enclosure.v.lower + vShift).nextDown,
                        upper: (enclosure.v.upper + vShift).nextUp
                    )
                )
            }
        case .affine, .constantU, .constantV, .harmonic, .sphericalGreatCircle,
             .polyline, .bSpline, .certifiedImplicit, .certifiedAnalyticImplicit,
             .projectedAnalytic, .rigidImage:
            return try enclosures(
                for: curve,
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        }
    }

    private func directlyEvaluableEnclosures(
        for curve: SurfaceParameterCurve,
        lowerFraction: Double,
        upperFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        let derivativeBounds = try normalizedParameterDerivativeBounds(
            for: curve,
            tolerance: tolerance
        )
        var remainingCells = maximumCellCount
        var stack = [ParameterWorkItem(
            lowerFraction: lowerFraction,
            upperFraction: upperFraction,
            depth: 0
        )]
        var result: [SurfaceParameterCurveEnclosure] = []
        while let item = stack.popLast() {
            guard remainingCells > 0 else {
                throw failure(
                    .resourceLimitExceeded,
                    tolerance: tolerance,
                    "Direct pcurve enclosure exceeded its cell budget."
                )
            }
            remainingCells -= 1
            let midpoint = item.lowerFraction
                + (item.upperFraction - item.lowerFraction) * 0.5
            let parameter = try curve.parameter(
                atNormalizedFraction: midpoint,
                tolerance: tolerance
            )
            let halfSpan = (item.upperFraction - item.lowerFraction) * 0.5
            let uRoundoff = (
                max(abs(parameter.u), derivativeBounds.u * halfSpan, 1.0)
                    * Double.ulpOfOne * 2_048.0
            ).nextUp
            let vRoundoff = (
                max(abs(parameter.v), derivativeBounds.v * halfSpan, 1.0)
                    * Double.ulpOfOne * 2_048.0
            ).nextUp
            let uRadius = (
                derivativeBounds.u * halfSpan + uRoundoff
            ).nextUp
            let vRadius = (
                derivativeBounds.v * halfSpan + vRoundoff
            ).nextUp
            let enclosure = SurfaceParameterCurveEnclosure(
                lowerFraction: item.lowerFraction,
                upperFraction: item.upperFraction,
                u: try ScalarInterval(
                    lower: (parameter.u - uRadius).nextDown,
                    upper: (parameter.u + uRadius).nextUp
                ),
                v: try ScalarInterval(
                    lower: (parameter.v - vRadius).nextDown,
                    upper: (parameter.v + vRadius).nextUp
                )
            )
            if enclosure.maximumWidth <= maximumWidth {
                result.append(enclosure)
                continue
            }
            guard item.depth < maximumDepth else {
                throw failure(
                    .resourceLimitExceeded,
                    residual: enclosure.maximumWidth,
                    tolerance: tolerance,
                    "Direct pcurve enclosure exceeded its subdivision depth."
                )
            }
            stack.append(ParameterWorkItem(
                lowerFraction: midpoint,
                upperFraction: item.upperFraction,
                depth: item.depth + 1
            ))
            stack.append(ParameterWorkItem(
                lowerFraction: item.lowerFraction,
                upperFraction: midpoint,
                depth: item.depth + 1
            ))
        }
        return result
    }

    private func normalizedParameterDerivativeBounds(
        for curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> (u: Double, v: Double) {
        switch curve {
        case let .affine(_, direction, startParameter, endParameter):
            let scale = abs(endParameter - startParameter)
            return (
                (abs(direction.x) * scale).nextUp,
                (abs(direction.y) * scale).nextUp
            )
        case let .constantU(_, vStart, vEnd):
            return (0.0, abs(vEnd - vStart).nextUp)
        case let .constantV(_, uStart, uEnd):
            return (abs(uEnd - uStart).nextUp, 0.0)
        case let .harmonic(_, cosine, sine, startParameter, endParameter):
            let scale = abs(endParameter - startParameter)
            return (
                ((abs(cosine.x) + abs(sine.x)) * scale).nextUp,
                ((abs(cosine.y) + abs(sine.y)) * scale).nextUp
            )
        case let .polyline(points):
            guard points.count >= 2 else {
                throw failure(
                    .invalidInput,
                    tolerance: tolerance,
                    "Polyline pcurve enclosure requires at least two points."
                )
            }
            var length = 0.0
            for index in 1..<points.count {
                length += hypot(
                    points[index].u - points[index - 1].u,
                    points[index].v - points[index - 1].v
                )
            }
            guard length.isFinite, length > 0.0 else {
                throw failure(
                    .invalidInput,
                    tolerance: tolerance,
                    "Polyline pcurve enclosure requires positive finite length."
                )
            }
            return (length.nextUp, length.nextUp)
        case let .bSpline(curve):
            guard case let .closed(lower, upper) = curve.domain else {
                throw failure(
                    .invalidInput,
                    tolerance: tolerance,
                    "B-spline pcurve enclosure requires a bounded domain."
                )
            }
            let domainWidth = upper - lower
            let patches = try curve.rationalBezierPatches(tolerance: tolerance)
            guard patches.isEmpty == false else {
                throw failure(
                    .invalidInput,
                    tolerance: tolerance,
                    "B-spline pcurve enclosure requires at least one rational Bezier span."
                )
            }
            var u = 0.0
            var v = 0.0
            for patch in patches {
                let bounds = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map(\.x),
                        patch.controlPoints.map(\.y),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                )
                u = max(u, (bounds.first[0] * domainWidth).nextUp)
                v = max(v, (bounds.first[1] * domainWidth).nextUp)
            }
            return (u, v)
        case .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage, .offsetSurfaceImage,
             .periodicTranslation:
            throw failure(
                .invalidInput,
                tolerance: tolerance,
                "Direct pcurve enclosure received a non-direct representation."
            )
        }
    }

    private func sphericalRigidImageEnclosures(
        for image: RigidImageSurfaceParameterCurve,
        lowerFraction: Double,
        upperFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        guard case let .analytic(.sphere(center, radius)) = image.targetSurface else {
            throw failure(
                .invalidInput,
                tolerance: tolerance,
                "A non-affine rigid pcurve requires a spherical target surface."
            )
        }
        var remainingCells = maximumCellCount
        var stack = [RigidSphereWorkItem(
            lowerFraction: lowerFraction,
            upperFraction: upperFraction,
            depth: 0
        )]
        var result: [SurfaceParameterCurveEnclosure] = []
        while let item = stack.popLast() {
            guard remainingCells > 0 else {
                throw failure(
                    .resourceLimitExceeded,
                    tolerance: tolerance,
                    "Spherical rigid pcurve enclosure exceeded its cell budget."
                )
            }
            remainingCells -= 1
            guard let derivativeBound = try image
                .modelSpaceFirstDerivativeMagnitude(
                    fromNormalizedFraction: item.lowerFraction,
                    toNormalizedFraction: item.upperFraction,
                    tolerance: tolerance
                ) else {
                throw failure(
                    .singularSystem,
                    tolerance: tolerance,
                    "Spherical rigid pcurve enclosure requires a certified spatial derivative bound."
                )
            }
            let midpoint = item.lowerFraction
                + (item.upperFraction - item.lowerFraction) * 0.5
            let geometry = try image.modelSpaceDifferential(
                atNormalizedFraction: midpoint,
                tolerance: tolerance
            )
            let direction = (geometry.position - center) / radius
            let halfSpan = (item.upperFraction - item.lowerFraction) * 0.5
            let directionRadius = (derivativeBound / radius * halfSpan).nextUp
            let radialLower = (
                hypot(direction.x, direction.y) - directionRadius
            ).nextDown
            if radialLower > 0.0 {
                let parameter = try image.parameter(
                    atNormalizedFraction: midpoint,
                    tolerance: tolerance
                )
                let parameterRadius = (
                    derivativeBound / radius / radialLower * halfSpan
                ).nextUp
                let u = try ScalarInterval(
                    lower: (parameter.u - parameterRadius).nextDown,
                    upper: (parameter.u + parameterRadius).nextUp
                )
                let v = try ScalarInterval(
                    lower: max(
                        -Double.pi * 0.5,
                        (parameter.v - parameterRadius).nextDown
                    ),
                    upper: min(
                        Double.pi * 0.5,
                        (parameter.v + parameterRadius).nextUp
                    )
                )
                if max(u.width, v.width) <= maximumWidth {
                    result.append(SurfaceParameterCurveEnclosure(
                        lowerFraction: item.lowerFraction,
                        upperFraction: item.upperFraction,
                        u: u,
                        v: v
                    ))
                    continue
                }
            }
            guard item.depth < maximumDepth else {
                throw failure(
                    .singularSystem,
                    tolerance: tolerance,
                    "A spherical rigid pcurve reaches a target-chart pole within tolerance."
                )
            }
            let split = midpoint
            stack.append(RigidSphereWorkItem(
                lowerFraction: split,
                upperFraction: item.upperFraction,
                depth: item.depth + 1
            ))
            stack.append(RigidSphereWorkItem(
                lowerFraction: item.lowerFraction,
                upperFraction: split,
                depth: item.depth + 1
            ))
        }
        return result
    }

    private func implicitEnclosures(
        for curve: CertifiedImplicitSurfaceParameterCurve,
        lowerFraction: Double,
        upperFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try curve.validate(
            on: curve.role == .first
                ? .bSpline(curve.intersection.firstSurface)
                : .bSpline(curve.intersection.secondSurface),
            tolerance: tolerance
        )
        let uCoordinate: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstU
            : .secondU
        let vCoordinate: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstV
            : .secondV
        return try graphEnclosures(
            cells: curve.intersection.cells,
            firstSurface: curve.intersection.firstSurface,
            secondSurface: curve.intersection.secondSurface,
            traversalSegments: try curve.canonicalTraversalSegments(
                tolerance: tolerance
            ),
            requestedLowerFraction: lowerFraction,
            requestedUpperFraction: upperFraction,
            maximumWidth: maximumWidth,
            tolerance: tolerance
        ) { subcell, lowerFraction, upperFraction in
            SurfaceParameterCurveEnclosure(
                lowerFraction: lowerFraction,
                upperFraction: upperFraction,
                u: subcell.parameterBox.interval(for: uCoordinate),
                v: subcell.parameterBox.interval(for: vCoordinate)
            )
        }
    }

    private func analyticImplicitEnclosures(
        for curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        lowerFraction: Double,
        upperFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try curve.validate(
            on: curve.intersection.analyticSurface,
            tolerance: tolerance
        )
        let intersection = curve.intersection
        let implicit = intersection.implicitCurve
        let uCoordinate: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstU
            : .secondU
        let vCoordinate: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstV
            : .secondV
        let traversal = CertifiedImplicitCurveTraversalSegment(
            curveLowerFraction: 0.0,
            curveUpperFraction: 1.0,
            canonicalLowerFraction: min(curve.startFraction, curve.endFraction),
            canonicalUpperFraction: max(curve.startFraction, curve.endFraction),
            direction: curve.startFraction < curve.endFraction ? .forward : .reversed
        )
        return try graphEnclosures(
            cells: implicit.cells,
            firstSurface: implicit.firstSurface,
            secondSurface: implicit.secondSurface,
            traversalSegments: [traversal],
            requestedLowerFraction: lowerFraction,
            requestedUpperFraction: upperFraction,
            maximumWidth: maximumWidth,
            tolerance: tolerance
        ) { subcell, lowerFraction, upperFraction in
            let u = try circleAngleBounds(
                subcell.parameterBox.interval(for: uCoordinate),
                offset: intersection.periodicSeamOffset,
                parameterUpperBound: 4.0,
                tolerance: tolerance
            )
            let vSource = subcell.parameterBox.interval(for: vCoordinate)
            let v: ScalarInterval
            switch intersection.analyticSurface {
            case .cylinder, .analytic(.cylinder), .analytic(.cone):
                v = vSource
            case .analytic(.sphere):
                v = try circleAngleBounds(
                    vSource,
                    offset: -Double.pi * 0.5,
                    parameterUpperBound: 2.0,
                    tolerance: tolerance
                )
            case .analytic(.torus):
                v = try circleAngleBounds(
                    vSource,
                    offset: intersection.periodicSeamOffset,
                    parameterUpperBound: 4.0,
                    tolerance: tolerance
                )
            case .plane, .analytic(.plane), .bSpline, .procedural:
                throw failure(
                    .invalidInput,
                    tolerance: tolerance,
                    "A certified analytic-implicit pcurve has an invalid support surface."
                )
            }
            return SurfaceParameterCurveEnclosure(
                lowerFraction: lowerFraction,
                upperFraction: upperFraction,
                u: u,
                v: v
            )
        }
    }

    private func graphEnclosures(
        cells: [CertifiedImplicitIntersectionGraphCell],
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        traversalSegments: [CertifiedImplicitCurveTraversalSegment],
        requestedLowerFraction: Double,
        requestedUpperFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance,
        transform: (
            CertifiedImplicitIntersectionGraphSubcell,
            Double,
            Double
        ) throws -> SurfaceParameterCurveEnclosure
    ) throws -> [SurfaceParameterCurveEnclosure] {
        guard cells.isEmpty == false else {
            throw failure(
                .invalidInput,
                tolerance: tolerance,
                "A certified implicit pcurve requires graph cells."
            )
        }
        let cellCount = cells.count
        var pending: [ImplicitWorkItem] = []
        for traversal in traversalSegments {
            for (index, cell) in cells.enumerated() {
                let cellStart = Double(index) / Double(cellCount)
                let cellEnd = Double(index + 1) / Double(cellCount)
                let overlapStart = max(traversal.canonicalLowerFraction, cellStart)
                let overlapEnd = min(traversal.canonicalUpperFraction, cellEnd)
                guard overlapEnd > overlapStart else { continue }
                let curveRange = traversal.curveFractionRange(
                    forCanonicalLower: overlapStart,
                    upper: overlapEnd
                )
                let selectedCurveLower = max(
                    curveRange.lower,
                    requestedLowerFraction
                )
                let selectedCurveUpper = min(
                    curveRange.upper,
                    requestedUpperFraction
                )
                guard selectedCurveUpper > selectedCurveLower else { continue }
                let curveSpan = curveRange.upper - curveRange.lower
                let cellLower = (overlapStart - cellStart) * Double(cellCount)
                let cellUpper = (overlapEnd - cellStart) * Double(cellCount)
                let cellSpan = cellUpper - cellLower
                let selectedCellLower: Double
                let selectedCellUpper: Double
                switch traversal.direction {
                case .forward:
                    selectedCellLower = cellLower
                        + (selectedCurveLower - curveRange.lower) / curveSpan * cellSpan
                    selectedCellUpper = cellLower
                        + (selectedCurveUpper - curveRange.lower) / curveSpan * cellSpan
                case .reversed:
                    selectedCellLower = cellLower
                        + (curveRange.upper - selectedCurveUpper) / curveSpan * cellSpan
                    selectedCellUpper = cellLower
                        + (curveRange.upper - selectedCurveLower) / curveSpan * cellSpan
                }
                pending.append(ImplicitWorkItem(
                    cell: cell,
                    cellLowerFraction: selectedCellLower,
                    cellUpperFraction: selectedCellUpper,
                    curveLowerFraction: selectedCurveLower,
                    curveUpperFraction: selectedCurveUpper,
                    depth: 0
                ))
            }
        }
        var result: [SurfaceParameterCurveEnclosure] = []
        var processedCount = 0
        while let item = pending.popLast() {
            processedCount += 1
            guard processedCount <= maximumCellCount else {
                throw failure(
                    .resourceLimitExceeded,
                    residual: Double(processedCount),
                    tolerance: tolerance,
                    "Certified pcurve enclosure exceeded its graph-cell budget."
                )
            }
            let subcell = try restrictedBounds(
                item,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
            let enclosure = try transform(
                subcell,
                item.curveLowerFraction,
                item.curveUpperFraction
            )
            if enclosure.maximumWidth <= maximumWidth {
                result.append(enclosure)
                continue
            }
            guard item.depth < maximumDepth else {
                throw failure(
                    .resourceLimitExceeded,
                    residual: enclosure.maximumWidth,
                    tolerance: tolerance,
                    "Certified pcurve enclosure exceeded its subdivision depth."
                )
            }
            let middle = item.curveLowerFraction
                + (item.curveUpperFraction - item.curveLowerFraction) * 0.5
            let cellMiddle = item.cellLowerFraction
                + (item.cellUpperFraction - item.cellLowerFraction) * 0.5
            guard middle > item.curveLowerFraction,
                  middle < item.curveUpperFraction,
                  cellMiddle > item.cellLowerFraction,
                  cellMiddle < item.cellUpperFraction else {
                throw failure(
                    .resourceLimitExceeded,
                    tolerance: tolerance,
                    "Certified pcurve enclosure reached floating-point subdivision resolution."
                )
            }
            pending.append(ImplicitWorkItem(
                cell: item.cell,
                cellLowerFraction: cellMiddle,
                cellUpperFraction: item.cellUpperFraction,
                curveLowerFraction: middle,
                curveUpperFraction: item.curveUpperFraction,
                depth: item.depth + 1
            ))
            pending.append(ImplicitWorkItem(
                cell: item.cell,
                cellLowerFraction: item.cellLowerFraction,
                cellUpperFraction: cellMiddle,
                curveLowerFraction: item.curveLowerFraction,
                curveUpperFraction: middle,
                depth: item.depth + 1
            ))
        }
        guard result.isEmpty == false else {
            throw failure(
                .topologyFailure,
                tolerance: tolerance,
                "Certified pcurve enclosure produced no covered cells."
            )
        }
        return result.sorted { $0.lowerFraction < $1.lowerFraction }
    }

    private func restrictedBounds(
        _ item: ImplicitWorkItem,
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionGraphSubcell {
        return try item.cell.restrictedBounds(
            fromNormalizedFraction: item.cellLowerFraction,
            toNormalizedFraction: item.cellUpperFraction,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    private func circleAngleBounds(
        _ parameter: ScalarInterval,
        offset: Double,
        parameterUpperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard parameter.lower >= -tolerance.relative,
              parameter.upper <= parameterUpperBound + tolerance.relative else {
            throw failure(
                .intersectionFailure,
                tolerance: tolerance,
                "An analytic circle parameter left its certified conversion domain."
            )
        }
        let lower = circleAngle(
            at: min(max(parameter.lower, 0.0), parameterUpperBound)
        ) + offset
        let upper = circleAngle(
            at: min(max(parameter.upper, 0.0), parameterUpperBound)
        ) + offset
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw failure(
                .topologyFailure,
                tolerance: tolerance,
                "An analytic circle parameter lost monotone angle order."
            )
        }
        return try ScalarInterval(lower: lower.nextDown, upper: upper.nextUp)
    }

    private func circleAngle(at parameter: Double) -> Double {
        if parameter >= 4.0 { return 2.0 * Double.pi }
        let segment = min(max(Int(floor(parameter)), 0), 3)
        let local = parameter - Double(segment)
        let complement = 1.0 - local
        let diagonalWeight = sqrt(0.5)
        let x = complement * complement
            + 2.0 * diagonalWeight * local * complement
        let y = 2.0 * diagonalWeight * local * complement
            + local * local
        return Double(segment) * Double.pi * 0.5 + atan2(y, x)
    }

    private func failure(
        _ code: KernelErrorCode,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: code,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
