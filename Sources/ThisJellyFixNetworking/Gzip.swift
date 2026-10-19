import Foundation
import Compression

/// Minimal gzip reader.
///
/// The OpenSubtitles download endpoint answers with a gzip-compressed body
/// and the subtitle file it points at is a gzipped `.srt`. `URLSession`
/// only decompresses `Content-Encoding: gzip` responses, so a file that is
/// gzip *as a format* reaches the app still compressed. Foundation has no
/// public gzip API, so the container is unwrapped here and the payload is
/// inflated with the Compression framework (raw DEFLATE).
enum Gzip {
    /// Returns the inflated bytes, or the input untouched when it is not
    /// gzipped. Never fails: a file that is not gzip is perfectly valid.
    static func decodeIfNeeded(_ data: Data) -> Data {
        guard isGzipped(data) else { return data }
        guard let inflated = inflate(payload(of: data)) else { return data }
        return inflated
    }

    /// True when the data starts with the gzip magic number.
    static func isGzipped(_ data: Data) -> Bool {
        guard data.count > 2 else { return false }
        let bytes = [UInt8](data.prefix(2))
        return bytes[0] == 0x1f && bytes[1] == 0x8b
    }

    // MARK: - Header

    /// Strips the gzip header and returns the raw DEFLATE payload.
    private static func payload(of data: Data) -> Data {
        let bytes = [UInt8](data)
        var index = 10 // magic (2) + CM (1) + FLG (1) + MTIME (4) + XFL (1) + OS (1)
        guard bytes.count > index else { return Data() }
        let flags = bytes[3]
        if flags & 0x04 != 0 { // FEXTRA
            guard index + 2 <= bytes.count else { return Data() }
            let extraLength = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2 + extraLength
        }
        if flags & 0x08 != 0 { // FNAME
            index = skipZeroTerminated(bytes, from: index)
        }
        if flags & 0x10 != 0 { // FCOMMENT
            index = skipZeroTerminated(bytes, from: index)
        }
        if flags & 0x02 != 0 { // FHCRC
            index += 2
        }
        guard index <= bytes.count else { return Data() }
        return Data(bytes[index...])
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from index: Int) -> Int {
        var cursor = index
        while cursor < bytes.count, bytes[cursor] != 0 {
            cursor += 1
        }
        return min(cursor + 1, bytes.count)
    }

    // MARK: - Inflate

    /// Raw DEFLATE decompression. `COMPRESSION_ZLIB` in Apple's framework is
    /// a raw DEFLATE stream — exactly what sits inside a gzip container.
    private static func inflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(stream) }

        let bufferSize = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        var output = Data()
        let inflated: Bool = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = raw.count
            var status = COMPRESSION_STATUS_OK
            repeat {
                stream.pointee.dst_ptr = destination
                stream.pointee.dst_size = bufferSize
                status = compression_stream_process(
                    stream,
                    Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                )
                let produced = bufferSize - stream.pointee.dst_size
                if produced > 0 {
                    output.append(destination, count: produced)
                }
                if status == COMPRESSION_STATUS_ERROR {
                    return false
                }
            } while status == COMPRESSION_STATUS_OK
            return true
        }
        return inflated ? output : nil
    }
}
