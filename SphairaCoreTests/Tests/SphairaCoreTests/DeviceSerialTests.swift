import Testing
@testable import SphairaCore

@Suite("DeviceSerial")
struct DeviceSerialTests {
    @Test("libnx placeholder is filtered out, in any case and with surrounding whitespace")
    func placeholderHidden() {
        #expect(DeviceSerial.display("SerialNumber") == nil)
        #expect(DeviceSerial.display("serialnumber") == nil)
        #expect(DeviceSerial.display("  SerialNumber\n") == nil)
    }

    @Test("missing or empty descriptor yields nil")
    func emptyHidden() {
        #expect(DeviceSerial.display(nil) == nil)
        #expect(DeviceSerial.display("") == nil)
        #expect(DeviceSerial.display("   ") == nil)
    }

    @Test("a real value passes through trimmed")
    func realValueKept() {
        #expect(DeviceSerial.display("XAW10012345678") == "XAW10012345678")
        #expect(DeviceSerial.display(" XAW10012345678 ") == "XAW10012345678")
    }

    @Test("isPlaceholder recognises only the libnx default")
    func placeholderDetection() {
        #expect(DeviceSerial.isPlaceholder("SerialNumber"))
        #expect(DeviceSerial.isPlaceholder(" serialnumber "))
        #expect(!DeviceSerial.isPlaceholder("XAJ40000382577"))
        #expect(!DeviceSerial.isPlaceholder(""))
        #expect(!DeviceSerial.isPlaceholder(nil))
    }
}
