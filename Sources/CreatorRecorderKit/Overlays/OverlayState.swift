import Foundation

public struct OverlayState: Equatable, Sendable {
    public var teleprompterVisible = true
    public var cameraVisible = true
    public var hudVisible = true
    public var microphoneEnabled = false
    public var systemAudioEnabled = false

    public init() {}
}
