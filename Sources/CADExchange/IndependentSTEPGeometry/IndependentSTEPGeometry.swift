import CADCore

/// Owns standalone geometry in internal coordinates and its declared exchange units.
public struct IndependentSTEPGeometry: Sendable {
    public let curves: [IndependentSTEPCurve]
    public let surfaces: [IndependentSTEPSurface]
    public let units: UnitSystem

    public init(curves: [IndependentSTEPCurve] = [], surfaces: [IndependentSTEPSurface] = [], units: UnitSystem = .meters) {
        self.curves = curves
        self.surfaces = surfaces
        self.units = units
    }
}
