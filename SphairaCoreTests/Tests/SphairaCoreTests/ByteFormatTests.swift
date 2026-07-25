import Testing
@testable import SphairaCore

@Suite("ByteFormat")
struct ByteFormatTests {
    /// Das Dezimaltrennzeichen folgt der eingestellten Sprache. Die Erwartungen
    /// dürfen es deshalb nicht fest verdrahten, sonst scheitern die Tests je
    /// nach Systemsprache.
    private let sep = ByteFormat.decimalSeparator

    @Test("size: Grenzwerte und Skalierung (dezimal, sprachabhängiges Trennzeichen)")
    func sizeValues() {
        #expect(ByteFormat.size(0) == "0 B")
        #expect(ByteFormat.size(1) == "1 B")
        #expect(ByteFormat.size(999) == "999 B")
        #expect(ByteFormat.size(1000) == "1\(sep)0 kB")
        #expect(ByteFormat.size(1023) == "1\(sep)0 kB")
        #expect(ByteFormat.size(1024) == "1\(sep)0 kB")
        #expect(ByteFormat.size(1500) == "1\(sep)5 kB")
        #expect(ByteFormat.size(1_400_000_000) == "1\(sep)4 GB")
        #expect(ByteFormat.size(2_000_000_000_000) == "2\(sep)0 TB")
    }

    @Test("size: sehr groß ohne Absturz, PB als größte Einheit")
    func sizeHuge() {
        let text = ByteFormat.size(Int64.max)
        #expect(text.hasSuffix(" PB"))
        #expect(ByteFormat.size(9_000_000_000_000_000) == "9\(sep)0 PB")
    }

    @Test("size: negativ ergibt den Gedankenstrich")
    func sizeNegative() {
        #expect(ByteFormat.size(-1) == "–")
        #expect(ByteFormat.size(Int64.min) == "–")
    }

    @Test("rate: Normalfälle")
    func rateValues() {
        #expect(ByteFormat.rate(0) == "0 B/s")
        #expect(ByteFormat.rate(999) == "999 B/s")
        #expect(ByteFormat.rate(23_100_000) == "23\(sep)1 MB/s")
        #expect(ByteFormat.rate(1_000_000) == "1\(sep)0 MB/s")
    }

    @Test("rate: nicht endlich oder negativ ergibt den Gedankenstrich")
    func rateInvalid() {
        #expect(ByteFormat.rate(.nan) == "–")
        #expect(ByteFormat.rate(.infinity) == "–")
        #expect(ByteFormat.rate(-.infinity) == "–")
        #expect(ByteFormat.rate(-0.5) == "–")
    }

    @Test("duration: Formate m:ss und h:mm:ss")
    func durationValues() {
        #expect(ByteFormat.duration(0) == "0:00")
        #expect(ByteFormat.duration(5) == "0:05")
        #expect(ByteFormat.duration(59) == "0:59")
        #expect(ByteFormat.duration(60) == "1:00")
        #expect(ByteFormat.duration(125) == "2:05")
        #expect(ByteFormat.duration(3599) == "59:59")
        #expect(ByteFormat.duration(3600) == "1:00:00")
        #expect(ByteFormat.duration(3661) == "1:01:01")
        #expect(ByteFormat.duration(86_400) == "24:00:00")
    }

    @Test("duration: Rundung auf ganze Sekunden")
    func durationRounding() {
        #expect(ByteFormat.duration(59.6) == "1:00")
        #expect(ByteFormat.duration(0.4) == "0:00")
    }

    @Test("duration: nicht endlich oder negativ ergibt den Gedankenstrich")
    func durationInvalid() {
        #expect(ByteFormat.duration(.nan) == "–")
        #expect(ByteFormat.duration(.infinity) == "–")
        #expect(ByteFormat.duration(-1) == "–")
    }
}
