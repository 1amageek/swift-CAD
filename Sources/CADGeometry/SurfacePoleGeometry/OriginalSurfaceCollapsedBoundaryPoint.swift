import CADCore

/// Source-bound physical pole representative with its complete original error interval.
package struct OriginalSurfaceCollapsedBoundaryPoint: Sendable {
    package let surface:Surface3D
    package let parameters:SurfaceParameterBox
    package let direction:OriginalBSplinePoleNormal.Direction
    package let point:Point3D
    package let positionBounds:IntervalVector3DBounds
    package let positionDeviationUpperBound:Double
    package let tolerance:ModelingTolerance

    package static func prepare(of surface:Surface3D,over box:SurfaceParameterBox,
        direction:OriginalBSplinePoleNormal.Direction,remainingSourceDepth:Int,
        tolerance:ModelingTolerance,using execution: inout OriginalQueryExecution) throws -> Self {
        try execution.consumeWork(1);try CurrentTaskCancellationChecker().checkCancellation();try tolerance.validate()
        let fixed = direction == .constantU ? box.u : box.v
        guard remainingSourceDepth >= 0,fixed.width == 0,fixed.lower.isFinite,
              box.u.lower.isFinite,box.u.upper.isFinite,box.v.lower.isFinite,box.v.upper.isFinite else {
            throw GeometryConversionError.invalidInput("Original collapsed XYZ needs a finite singleton boundary and source admission.")
        }
        let value:IntervalVector3DBounds
        func original(_ point:Point3D)->IntervalVector3DBounds { .init(x:.exact(point.x),y:.exact(point.y),z:.exact(point.z)) }
        switch surface {
        case .bSpline(let spline):
            let pole = try OriginalBSplinePoleNormal(surface:spline,tolerance:tolerance,using: &execution)
            value = original(try pole.collapsedPoint(at:.init(u:box.u.lower,v:box.v.lower),
                direction:direction,using: &execution))
        case .analytic(.cone(let apex,_,_)) where direction == .constantV && fixed.lower == 0:
            try surface.validate(tolerance:tolerance, using: &execution);value = original(apex)
        case .procedural(.originalRevolution(let revolution)) where direction == .constantV:
            let atEnd = fixed.lower == 1
            guard fixed.lower == 0 || atEnd,revolution.hasOriginalAxisEndpoint(atEnd:atEnd),
                  case .closed(let angularLower,let angularUpper) = revolution.uDomain,
                  box.u.lower >= angularLower,box.u.upper <= angularUpper else {
                throw GeometryConversionError.invalidInput("Original revolution XYZ does not bind an exact retained axis boundary.")
            }
            let jet = try revolution.intervalJet(over:.init(u:.init(lower:angularLower,upper:angularLower),v:box.v),
                tolerance:tolerance,using: &execution)
            value = .init(x:jet.x.value,y:jet.y.value,z:jet.z.value)
        case .procedural(.originalAngularTransport(let image)):
            guard remainingSourceDepth > 0, direction == .constantV,
                let pole = image.coefficients.collapsedSpherePosition(over: box) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Physical longitude keeps
                // canonical intrinsic sphere poles. Other transported singular
                // boundaries require their original endpoint/normal issuer.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original transported support has no retained canonical collapsed pole.")
            }
            try execution.consumeWork(1); value = pole
        case .procedural(.originalAffineWord(let image)):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original collapsed word image exhausted source depth.")
            }
            if direction == .constantV, let pole = image.harmonicCoefficients?.collapsedSpherePosition(over: box) {
                try execution.consumeWork(1); value = pole
            } else {
                let source = try prepare(of: image.source, over: box, direction: direction,
                    remainingSourceDepth: remainingSourceDepth - 1, tolerance: tolerance, using: &execution)
                value = try OriginalAffineWordJetTransport.position(image.preparedWord,
                    bounds: source.positionBounds, using: &execution)
            }
        case .procedural(.originalImage(let image)):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original collapsed image exhausted source depth.")
            }
            let native = try image.sourceParameterBounds(over:box,tolerance:tolerance,using: &execution)
            let sourceDirection:OriginalBSplinePoleNormal.Direction = image.swapAxes
                ? (direction == .constantU ? .constantV : .constantU) : direction
            let source = try prepare(of:image.source,over:native,direction:sourceDirection,
                remainingSourceDepth:remainingSourceDepth-1,tolerance:tolerance,using: &execution)
            let q = source.positionBounds,a = image.transform
            for _ in 0..<12 { try execution.consumeWork(1) }
            value = .init(x:.exact(a.translation.x)+q.x * .exact(a.basisX.x)+q.y * .exact(a.basisY.x)+q.z * .exact(a.basisZ.x),
                y:.exact(a.translation.y)+q.x * .exact(a.basisX.y)+q.y * .exact(a.basisY.y)+q.z * .exact(a.basisZ.y),
                z:.exact(a.translation.z)+q.x * .exact(a.basisX.z)+q.y * .exact(a.basisY.z)+q.z * .exact(a.basisZ.z))
        case .analytic(.sphere(let center, let radius)):
            guard direction == .constantV,
                  fixed.lower == Double.pi * 0.5 || fixed.lower == -Double.pi * 0.5,
                  box.u.lower <= box.u.upper else {
                throw GeometryConversionError.invalidInput("Original sphere collapse requires its canonical quarter-turn latitude.")
            }
            try surface.validate(tolerance: tolerance, using: &execution)
            let sign = fixed.lower > 0 ? 1.0 : -1.0
            value = .init(x: .exact(center.x), y: .exact(center.y),
                z: .exact(center.z) + .exact(radius) * .exact(sign))
        default:
            throw GeometryConversionError.invalidInput("This original support has no structural collapsed boundary witness.")
        }
        let midpoint = value.midpoint
        let point = Point3D(x:midpoint.x,y:midpoint.y,z:midpoint.z)
        let error = (value-original(point)).lengthUpperBound
        guard error.isFinite,point.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original collapsed boundary point is not finitely enclosed.")
        }
        return .init(surface:surface,parameters:box,direction:direction,point:point,
            positionBounds:value,positionDeviationUpperBound:error,tolerance:tolerance)
    }
}
