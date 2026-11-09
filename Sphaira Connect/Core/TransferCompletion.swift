//
//  TransferCompletion.swift
//  Sphaira Connect
//
//  Decides whether a file counts as fully transferred once the Switch closes it.
//

/// The SPH0 protocol carries no per-file result: the Switch simply stops
/// requesting ranges and closes the file. Whether that was a successful install
/// or a skip (title already installed, header rejected) has to be inferred from
/// how much of the file it actually asked for.
///
/// A successful install regularly falls short of the file size, for two reasons:
///
/// - NSP/XCI containers pad their last entry to an alignment boundary — a few
///   hundred bytes the Switch never requests.
/// - NSPs from dumpers carry metadata entries Sphaira does not need and never
///   reads (`*.cnmt.xml`, `*.nacp.xml`, `*.legalinfo.xml`, `*.programinfo.xml`,
///   sometimes `*.cert`). Together these run to some hundred kilobytes.
///
/// A genuine skip, on the other hand, ends after the container header and the
/// content-meta NCA — a few kilobytes up to a few megabytes at most, but always a
/// tiny fraction of the file. The rule therefore combines an absolute bound on
/// the shortfall (metadata is small in absolute terms) with a relative floor on
/// the fraction requested (so a small file that was skipped after its header is
/// not waved through just because the shortfall is small in absolute terms).
nonisolated enum TransferCompletion {
    /// Largest shortfall still attributed to unread metadata and padding.
    static let shortfallTolerance: Int64 = 4 * 1024 * 1024

    /// Smallest share of the file the Switch must have requested for the
    /// transfer to count as complete, regardless of the absolute shortfall.
    static let minimumFraction = 0.5

    /// Whether a file whose transfer the Switch has ended counts as complete.
    ///
    /// `sentBytes` is the sum of all transferred blocks; it may exceed
    /// `totalBytes` because the Switch is allowed to request ranges more than once.
    static func isComplete(sentBytes: Int64, totalBytes: Int64) -> Bool {
        guard totalBytes > 0 else { return true }
        guard sentBytes < totalBytes else { return true }
        let shortfall = totalBytes - sentBytes
        guard shortfall <= shortfallTolerance else { return false }
        return Double(sentBytes) / Double(totalBytes) >= minimumFraction
    }
}
