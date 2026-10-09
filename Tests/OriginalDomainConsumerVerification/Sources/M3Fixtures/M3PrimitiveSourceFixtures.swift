import CADCore
import CADGeometry

/// Exercises the actual authored geometry providers and their evaluation handoff.
public enum M3PrimitiveSourceFixtures {
    private static func require(_ condition: Bool,line: Int = #line) throws {
        if !condition { print("FAILED M3 original source line \(line)"); throw ExactScalarFailure.invalidEvidence }
    }
    private static func near(_ first: Point3D,_ second: Point3D) throws {
        try require((first-second).length < 1e-9)
    }
    private static func ledger() throws -> ExactScalarLedger {
        .init(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
    }
    private static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:2),maximumTransportDepth:16,maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:0)
    }
    public static func verify() throws {
        try lines()
        try planes()
        try analyticProviders()
        try physicalWrappers()
        print("PASS M3 actual primitive sources, stored-N UV, original physical wrappers")
    }
    private static func lines() throws {
        var a = try ledger(); let f = ExactRationalScalarDomain(),l = try limits()
        let o = Point3D(x:1,y:2,z:3)
        for curve in [Curve3D.line(.init(origin:o,direction:.unitX)),.analytic(.line(origin:o,direction:.unitX))] {
            let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalLinearCurveSnapshotProvider(tolerance:.standard)).bind(curve,limits:l.source,using:&a)
            let issuer = DefaultOriginalLinearDomainIssuer<OriginalLinearCurveSnapshot,ExactRationalScalarDomain>()
            let frame = try issuer.frame(source:source,field:f,limits:l,using:&a)
            let cover = try issuer.issue(request:frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
            let t = try f.integer(-100000000,using:&a)
            let xyz = try cover.law.position(at:t,limits:l.source,using:&a)
            try require(f.compare(xyz[0],f.integer(-99999999,using:&a),using:&a) == .equal)
            try near(curve.point(at:-100000000,tolerance:.standard),o + Vector3D(x:-100000000,y:0,z:0))
            try require(cover.incident(at:[t],limits:l,using:&a).count == 1)
        }
    }
    private static func planes() throws {
        var a = try ledger(); let f = ExactRationalScalarDomain(),l = try limits()
        let origin = Point3D(x:1,y:2,z:3),normal = Vector3D(x:3,y:4,z:0)
        let values: [Surface3D] = [.plane(.init(origin:origin,normal:normal)),.analytic(.plane(origin:origin,normal:normal))]
        for surface in values {
            let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalPlaneSnapshotProvider(tolerance:.standard)).bind(surface,limits:l.source,using:&a)
            let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,ExactRationalScalarDomain>().issue(source:source,field:f,
                firstLength:f.integer(4,using:&a),normalLength:f.integer(5,using:&a),limits:l.source,using:&a)
            let xyz = try basis.position(u:f.integer(7,using:&a),v:f.integer(-9,using:&a),limits:l,using:&a)
            let p = try surface.point(u:7,v:-9,tolerance:.standard)
            let expected = origin + Vector3D(x:7.2,y:-5.4,z:-7)
            try near(p,expected)
            let exactExpected = [try f.dividing(f.integer(41,using:&a),f.integer(5,using:&a),using:&a),
                try f.dividing(f.integer(-17,using:&a),f.integer(5,using:&a),using:&a),try f.integer(-4,using:&a)]
            for i in 0..<3 { try require(f.compare(xyz[i],exactExpected[i],using:&a) == .equal) }
            let uv = try surface.parameterProjection(of:p,tolerance:.standard)
            try require(abs(uv.u-7)<1e-9 && abs(uv.v+9)<1e-9)
            let differential = try surface.differentialGeometry(u:7,v:-9,tolerance:.standard)
            try near(differential.position,p)
            try require(abs(differential.normal.length-1)<1e-12)
            let issuer = DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot,ExactRationalScalarDomain>()
            let frame = try issuer.frame(basis:basis,limits:l,using:&a)
            let cover = try issuer.issue(request:frame.fullSelection(limits:l,using:&a),basis:basis,limits:l,using:&a)
            try require(cover.incident(at:[f.integer(100000000,using:&a),f.integer(-100000000,using:&a)],limits:l,using:&a).count == 1)
        }
        let authored = Surface3D.plane(.init(origin:origin,normal:.unitZ,uDirection:.unitX))
        try near(authored.point(u:7,v:-9,tolerance:.standard),origin + Vector3D(x:7,y:-9,z:0))
        let projected = try authored.parameterProjection(of:origin + Vector3D(x:7,y:-9,z:0),tolerance:.standard)
        try require(projected.u == 7 && projected.v == -9)
        do {
            _ = try OriginalPlaneSnapshotProvider(tolerance:.standard).snapshot(authored,limits:l.source,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalSourceIssuanceFailure.unsupportedRepresentation { }
        // A newly admitted scaled N must never enter legacy unit-normal distance formulas.
        let scaled = Surface3D.analytic(.plane(origin:.init(x:0,y:0,z:0.5),normal:.init(x:0,y:0,z:2)))
        do {
            _ = try DefaultSurfaceSurfaceIntersector().intersections(first:scaled,second:.analytic(.sphere(center:.origin,radius:1)),tolerance:.standard)
            throw ExactScalarFailure.invalidEvidence
        } catch let error as KernelError { try require(error.code == .unsupportedCapability) }
    }
    private static func analyticProviders() throws {
        var a = try ledger(); let f = ExactRationalScalarDomain(),l = try limits()
        let o = Point3D(x:1,y:2,z:3)
        let curves: [Curve3D] = [
            .circle(.init(center:o,normal:.unitZ,radius:3)),
            .analytic(.circle(center:o,normal:.unitZ,radius:3)),
            .analytic(.arc(center:o,normal:.unitZ,radius:3,startAngle:0,endAngle:1)),
            .analytic(.ellipse(center:o,normal:.unitZ,majorAxis:.unitX,majorRadius:3,minorRadius:2)),
            .analytic(.hyperbola(.init(center:o,normal:.unitZ,transverseAxis:.unitX,transverseRadius:3,conjugateRadius:2))),
            .analytic(.parabola(.init(vertex:o,normal:.unitZ,axis:.unitX,focalLength:3))) ]
        for curve in curves {
            let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticCoordinateCurveSnapshotProvider(tolerance:.standard)).bind(curve,limits:l.source,using:&a)
            let law = try DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot,ExactRationalScalarDomain>().issue(source:source,field:f,limits:l.source,using:&a)
            let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
            let functions = source.original.coordinateKind == .parabola ? [zero] : [one,zero]
            let expected = source.original.coordinateKind == .parabola ? o : o + source.original.first * source.original.firstMagnitude
            try near(curve.point(at:0,tolerance:.standard),expected)
            try near(curve.differentialGeometry(at:0,tolerance:.standard).position,expected)
            let coords = [expected.x,expected.y,expected.z]
            for i in 0..<3 {
                let actual = try law.polynomials.evaluated(law.position[i],at:functions,using:&a).value
                try require(f.compare(actual,f.binary64(exactly:coords[i],using:&a),using:&a) == .equal)
            }
            let issuer = DefaultOriginalAnalyticDomainIssuer<OriginalAnalyticCoordinateSnapshot,ExactRationalScalarDomain>()
            let frame = try issuer.frame(law:law,limits:l,using:&a)
            let cover = try issuer.issue(request:frame.fullSelection(limits:l,using:&a),law:law,limits:l,using:&a)
            try require(!cover.incident(at:[zero],limits:l,using:&a).isEmpty)
        }
        let surfaces: [Surface3D] = [.cylinder(.init(origin:o,axis:.unitZ,radius:3)),
            .analytic(.cylinder(origin:o,axis:.unitZ,radius:3)),.analytic(.cone(apex:o,axis:.unitZ,halfAngle:0.5)),
            .analytic(.sphere(center:o,radius:3)),.analytic(.torus(center:o,axis:.unitZ,majorRadius:3,minorRadius:2))]
        for surface in surfaces {
            let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance:.standard)).bind(surface,limits:l.source,using:&a)
            let law = try DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot,ExactRationalScalarDomain>().issue(source:source,field:f,limits:l.source,using:&a)
            let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
            let functions: [ExactRationalCoefficient]
            let expected: Point3D
            switch source.original.coordinateKind {
            case .cone: functions = [one,zero,zero,zero,one]; expected = o
            case .cylinder: functions = [one,zero,zero]; expected = o + source.original.first * 3
            case .sphere: functions = [one,zero,one,zero]; expected = o + source.original.first * 3
            default: functions = [one,zero,one,zero]; expected = o + source.original.first * 5
            }
            try near(surface.point(u:0,v:0,tolerance:.standard),expected)
            if source.original.coordinateKind != .cone { try near(surface.differentialGeometry(u:0,v:0,tolerance:.standard).position,expected) }
            for i in 0..<3 {
                let actual = try law.polynomials.evaluated(law.position[i],at:functions,using:&a).value
                let coords = [expected.x,expected.y,expected.z]
                try require(f.compare(actual,f.binary64(exactly:coords[i],using:&a),using:&a) == .equal)
            }
            let issuer = DefaultOriginalAnalyticDomainIssuer<OriginalAnalyticCoordinateSnapshot,ExactRationalScalarDomain>()
            let frame = try issuer.frame(law:law,limits:l,using:&a)
            let cover = try issuer.issue(request:frame.fullSelection(limits:l,using:&a),law:law,limits:l,using:&a)
            try require(!cover.incident(at:[zero,zero],limits:l,using:&a).isEmpty)
        }
    }
    private static func physicalWrappers() throws {
        var usage = try NativeRationalSourceAllowance(maximumWork:80_000_000,maximumCells:1_000_000,
            maximumStorage:268_435_456,maximumDepth:32,operationCheck:{ try CurrentTaskCancellationChecker().checkCancellation() })
        var a = try ledger(); let f = try OriginalPiScalarDomain(using:&a),l = try limits()
        let gain = try ExactRationalCoefficient.originalDouble(2,usage:&usage)
        let latitudeGain = try ExactRationalCoefficient.originalDouble(0.5,usage:&usage)
        let conics: [Curve3D] = [.circle(.init(center:.origin,normal:.unitZ,radius:3)),
            .analytic(.ellipse(center:.origin,normal:.unitZ,majorAxis:.unitX,majorRadius:3,minorRadius:2))]
        for curve in conics {
            let wrapper = try OriginalAngularTransportCurve3D(source:curve,
                transport:.physicalRadians(gain:gain,offset:.zero),tolerance:.standard,usage:&usage)
            let actual = Curve3D.originalAngularTransport(wrapper)
            let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticCoordinateCurveSnapshotProvider(tolerance:.standard)).bind(actual,limits:l.source,using:&a)
            let law = try DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot,OriginalPiScalarDomain>().issuePhysical(source:source,field:f,limits:l.source,using:&a)
            try require(f.compare(law.periods[0].period,f.pi(using:&a),using:&a) == .equal)
            let p = try actual.point(at:0.25,tolerance:.standard)
            let d = try actual.differentialGeometry(at:0.25,tolerance:.standard)
            try near(p,d.position); try require(d.firstDerivative.length > 0)
        }
        let arc = try OriginalAngularTransportCurve3D(source:conics[0],
            transport:.physicalRadianArc(start:.zero,end:.one,additionalTurns:1),tolerance:.standard,usage:&usage)
        let actualArc = Curve3D.originalAngularTransport(arc)
        let arcSource = try DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticCoordinateCurveSnapshotProvider(tolerance:.standard)).bind(actualArc,limits:l.source,using:&a)
        let arcLaw = try DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot,OriginalPiScalarDomain>().issuePhysical(source:arcSource,field:f,limits:l.source,using:&a)
        try require(f.compare(arcLaw.axes[0].lower!,f.integer(0,using:&a),using:&a) == .equal)
        try require(f.compare(arcLaw.axes[0].upper!,f.integer(1,using:&a),using:&a) == .equal)
        let arcIssuer = DefaultOriginalAnalyticDomainIssuer<OriginalAnalyticCoordinateSnapshot,OriginalPiScalarDomain>()
        let arcFrame = try arcIssuer.frame(law:arcLaw,limits:l,using:&a)
        let arcCover = try arcIssuer.issue(request:arcFrame.fullSelection(limits:l,using:&a),law:arcLaw,limits:l,using:&a)
        try require(arcCover.incident(at:[f.integer(1,using:&a)],limits:l,using:&a).count == 1)
        try require(arcCover.incident(at:[f.integer(2,using:&a)],limits:l,using:&a).isEmpty)
        _ = try actualArc.point(at:1,tolerance:.standard)
        let shapes: [Surface3D] = [.analytic(.cylinder(origin:.origin,axis:.unitZ,radius:3)),
            .analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:0.5)),.analytic(.sphere(center:.origin,radius:3)),
            .analytic(.torus(center:.origin,axis:.unitZ,majorRadius:3,minorRadius:2))]
        for shape in shapes {
            let v: OriginalAngularParameterTransport
            if case .analytic(.sphere) = shape { v = .physicalRadians(gain:latitudeGain,offset:.zero) }
            else if case .analytic(.torus) = shape { v = .physicalRadians(gain:.one,offset:.zero) }
            else { v = .intrinsic }
            let wrapper = try OriginalAngularTransportSurface3D(source:shape,uTransport:.physicalRadians(gain:gain,offset:.zero),
                vTransport:v,tolerance:.standard,usage:&usage)
            let actual = Surface3D.procedural(.originalAngularTransport(wrapper))
            let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance:.standard)).bind(actual,limits:l.source,using:&a)
            let law = try DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot,OriginalPiScalarDomain>().issuePhysical(source:source,field:f,limits:l.source,using:&a)
            try require(law.axes[0].meaning == .physicalRadian && law.periods.count >= 1)
            try require(f.compare(law.periods[0].period,f.pi(using:&a),using:&a) == .equal)
            let p = try actual.point(u:0,v:1,tolerance:.standard)
            let derivative = try wrapper.parameterDerivatives(u:0,v:1,tolerance:.standard)
            try near(p,derivative.position)
            try require(derivative.tangentU.length > 0 && derivative.tangentV.length > 0)
            if source.original.coordinateKind == .cone {
                let negative = try actual.point(u:0,v:-1,tolerance:.standard)
                try require((p + (negative - .origin) - .origin).length < 1e-9)
                try near(actual.point(u:7,v:0,tolerance:.standard),.origin)
            }
            if source.original.coordinateKind == .sphere {
                try require(law.collapsedFibers.count == 2)
                do { _ = try actual.point(u:0,v:4,tolerance:.standard); throw ExactScalarFailure.invalidEvidence }
                catch GeometryConversionError.invalidInput { }
            }
        }
        do {
            _ = try OriginalAngularTransportSurface3D(source:.analytic(.sphere(center:.origin,radius:3)),uTransport:.intrinsic,
                vTransport:.physicalRadianArc(start:.zero,end:.one,additionalTurns:1),tolerance:.standard,usage:&usage)
            throw ExactScalarFailure.invalidEvidence
        } catch GeometryConversionError.invalidInput { }
        catch GeometryConversionError.resourceLimitExceeded { }
        print("PASS M3 exact physical source periods and actual point/derivative domain checks")
    }
}
