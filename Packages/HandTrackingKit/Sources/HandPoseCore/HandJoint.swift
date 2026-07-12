/// The 21 hand landmarks AirCursor tracks, decoupled from Vision so packages
/// downstream of the capture seam never import it.
public enum HandJoint: String, CaseIterable, Hashable, Sendable, Codable {
    case wrist

    case thumbCMC
    case thumbMP
    case thumbIP
    case thumbTip

    case indexMCP
    case indexPIP
    case indexDIP
    case indexTip

    case middleMCP
    case middlePIP
    case middleDIP
    case middleTip

    case ringMCP
    case ringPIP
    case ringDIP
    case ringTip

    case littleMCP
    case littlePIP
    case littleDIP
    case littleTip
}
