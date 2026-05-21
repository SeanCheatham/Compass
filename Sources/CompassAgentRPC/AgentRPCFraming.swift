import Foundation

/// Length-prefixed JSON framing for the guest agent wire protocol.
///
/// One frame is `[ 4-byte big-endian length ][ UTF-8 JSON body ]`. The body
/// length is bounded so a malformed sender can't make either side allocate
/// gigabytes — files much larger than the bound would be unusable to the
/// agent loop anyway (the model receives the data and trips token limits).
public enum AgentRPCFraming {
    /// Hard cap on a single frame's JSON body, in bytes. The largest
    /// legitimate frame is `writeFile` carrying a base64-encoded file —
    /// ~64MB of source after base64 overhead. 128MB leaves slack and is
    /// well clear of accidental "agent wrote a 10GB blob" footguns.
    public static let maxFrameByteCount: Int = 128 * 1024 * 1024

    public enum FramingError: Swift.Error, Equatable {
        case lengthHeaderTooShort
        case frameExceedsMaxByteCount(actual: Int, max: Int)
        case bodyShorterThanDeclared(declared: Int, actual: Int)
        case decodingFailed(String)
        case encodingFailed(String)
    }

    /// Encode a frame: 4-byte big-endian length prefix followed by JSON.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let body: Data
        do {
            body = try JSONEncoder().encode(value)
        } catch {
            throw FramingError.encodingFailed(error.localizedDescription)
        }
        guard body.count <= maxFrameByteCount else {
            throw FramingError.frameExceedsMaxByteCount(actual: body.count, max: maxFrameByteCount)
        }
        var header = Data(count: 4)
        let length = UInt32(body.count).bigEndian
        header.withUnsafeMutableBytes { buf in
            buf.bindMemory(to: UInt32.self).baseAddress?.pointee = length
        }
        return header + body
    }

    /// Decode a frame from a complete `Data` whose first 4 bytes are the
    /// length prefix. Useful for tests; the read loop on the wire is
    /// `readFrame(from:)` below.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count >= 4 else { throw FramingError.lengthHeaderTooShort }
        let declared = Int(readLength(data.prefix(4)))
        guard declared <= maxFrameByteCount else {
            throw FramingError.frameExceedsMaxByteCount(actual: declared, max: maxFrameByteCount)
        }
        guard data.count - 4 >= declared else {
            throw FramingError.bodyShorterThanDeclared(declared: declared, actual: data.count - 4)
        }
        let body = data.subdata(in: 4..<(4 + declared))
        do {
            return try JSONDecoder().decode(type, from: body)
        } catch {
            throw FramingError.decodingFailed(error.localizedDescription)
        }
    }

    /// Read exactly `byteCount` bytes from `read`, retrying short reads.
    /// `read` semantics match POSIX `read(2)`: returns `nil` for EOF, throws
    /// on error, otherwise returns up to that many bytes.
    public static func readExactly(
        _ byteCount: Int,
        from read: (_ wanted: Int) throws -> Data?
    ) throws -> Data {
        var buffer = Data()
        buffer.reserveCapacity(byteCount)
        while buffer.count < byteCount {
            guard let chunk = try read(byteCount - buffer.count) else {
                throw FramingError.bodyShorterThanDeclared(
                    declared: byteCount,
                    actual: buffer.count
                )
            }
            if chunk.isEmpty {
                throw FramingError.bodyShorterThanDeclared(
                    declared: byteCount,
                    actual: buffer.count
                )
            }
            buffer.append(chunk)
        }
        return buffer
    }

    /// Read and decode a single frame from a reader closure. The reader is
    /// expected to be transport-shaped (POSIX `read(2)`-style): each call
    /// returns up to the requested number of bytes; nil/zero-length means EOF.
    public static func readFrame<T: Decodable>(
        _ type: T.Type,
        read: (_ wanted: Int) throws -> Data?
    ) throws -> T {
        let header = try readExactly(4, from: read)
        let declared = Int(readLength(header))
        guard declared <= maxFrameByteCount else {
            throw FramingError.frameExceedsMaxByteCount(actual: declared, max: maxFrameByteCount)
        }
        let body = try readExactly(declared, from: read)
        do {
            return try JSONDecoder().decode(type, from: body)
        } catch {
            throw FramingError.decodingFailed(error.localizedDescription)
        }
    }

    private static func readLength(_ header: Data) -> UInt32 {
        header.withUnsafeBytes { raw -> UInt32 in
            guard let base = raw.bindMemory(to: UInt32.self).baseAddress else { return 0 }
            return UInt32(bigEndian: base.pointee)
        }
    }
}
