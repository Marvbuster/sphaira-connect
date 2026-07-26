/// Interprets the result of the oversized control transfer that triggers
/// Fusée Gelée. The vulnerable boot ROM normally disappears before it can
/// complete the request, and libusb reports that disappearance differently
/// across platforms and host controllers.
nonisolated enum RCMTriggerOutcome: Equatable {
    case payloadStarted
    case deviceResponded(Int32)
    case usbFailure(Int32)

    static func classify(_ result: Int32) -> Self {
        // LIBUSB_ERROR_IO, NO_DEVICE, TIMEOUT and PIPE all describe expected
        // ways in which the RCM device can vanish during the exploit request.
        if [-1, -4, -7, -9].contains(result) {
            return .payloadStarted
        }
        if result >= 0 {
            return .deviceResponded(result)
        }
        return .usbFailure(result)
    }
}
