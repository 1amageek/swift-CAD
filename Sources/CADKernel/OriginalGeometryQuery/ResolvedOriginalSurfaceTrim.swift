import CADCore
import CADGeometry
import CADIR

/// The exact current face-local chart selected by an original coedge.
public struct ResolvedOriginalSurfaceTrim: Sendable, Hashable {
    public let reference: SurfaceTrimReference
    public let source: ResolvedOriginalSurfaceGeometry
    public let loopID: LoopID
    public let edgeID: EdgeID
    public let curveID: CurveID
    public let orientation: Orientation
    public let parameterCurve: SurfaceParameterCurve
    public var surface: Surface3D { source.surface }
    public var liftedCurve: Curve3D {
        .surfaceLift(SurfaceLiftCurve3D(surface: source.surface, parameterCurve: parameterCurve))
    }

    package init(reference: SurfaceTrimReference, source: ResolvedOriginalSurfaceGeometry,
        loopID: LoopID, edgeID: EdgeID, curveID: CurveID, orientation: Orientation,
        parameterCurve: SurfaceParameterCurve) {
        self.reference = reference; self.source = source; self.loopID = loopID
        self.edgeID = edgeID; self.curveID = curveID; self.orientation = orientation
        self.parameterCurve = parameterCurve
    }
}
