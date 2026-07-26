import Testing
@testable import SphairaCore

@Suite("RCM exploit trigger result")
struct RCMTriggerOutcomeTests {
    @Test(
        "Expected disconnect-style libusb results mean the payload started",
        arguments: [Int32(-1), -4, -7, -9]
    )
    func acceptsExpectedDisconnect(_ result: Int32) {
        #expect(RCMTriggerOutcome.classify(result) == .payloadStarted)
    }

    @Test("A completed control transfer means the device responded")
    func identifiesPatchedResponse() {
        #expect(RCMTriggerOutcome.classify(0) == .deviceResponded(0))
        #expect(RCMTriggerOutcome.classify(28_672) == .deviceResponded(28_672))
    }

    @Test("Unknown libusb errors remain failures")
    func preservesUnknownFailure() {
        #expect(RCMTriggerOutcome.classify(-3) == .usbFailure(-3))
        #expect(RCMTriggerOutcome.classify(-6) == .usbFailure(-6))
    }
}
