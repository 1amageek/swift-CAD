/// Original plane equation is stored N dot (X - origin) = 0. Providers retain
/// finite original coordinates and a nonzero N. A rounded basis is not authority.
public protocol OriginalPlaneSourceReading: Sendable {
    func originCoordinate(in axis: Int) -> Double
    func normalCoordinate(in axis: Int) -> Double
}
