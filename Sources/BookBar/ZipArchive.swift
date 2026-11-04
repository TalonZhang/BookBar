import CZlib
import Foundation

struct ZipArchive {
    private struct Entry {
        let path: String
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let offset: Int
    }

    private let bytes: Data

    init(_ bytes: Data) {
        self.bytes = bytes
    }

    func extract(to destination: URL) throws {
        for entry in try entries() {
            guard !entry.path.hasSuffix("/") else { continue }
            let target = destination.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try contents(of: entry).write(to: target, options: .withoutOverwriting)
        }
    }

    private func entries() throws -> [Entry] {
        let footer = try footerOffset()
        let count = Int(bytes.u16(footer + 10))
        let directorySize = Int(bytes.u32(footer + 12))
        var cursor = Int(bytes.u32(footer + 16))
        let end = cursor + directorySize
        guard bytes.u16(footer + 4) == 0, bytes.u16(footer + 6) == 0,
              bytes.u16(footer + 8) == count, count > 0, count < 65_535, end <= footer else {
            throw LibraryError.invalidArchive
        }

        var totalSize = 0
        var paths = Set<String>()
        var result: [Entry] = []
        for _ in 0..<count {
            guard cursor + 46 <= end, bytes.u32(cursor) == 0x02014b50 else {
                throw LibraryError.invalidArchive
            }
            let nameEnd = cursor + 46 + Int(bytes.u16(cursor + 28))
            let next = nameEnd + Int(bytes.u16(cursor + 30)) + Int(bytes.u16(cursor + 32))
            guard next <= end, bytes.u16(cursor + 34) == 0,
                  let path = String(data: bytes[(cursor + 46)..<nameEnd], encoding: .utf8),
                  Self.isSafe(path), paths.insert(path).inserted else {
                throw LibraryError.invalidArchive
            }
            let flags = bytes.u16(cursor + 8)
            guard flags & 1 == 0 else { throw LibraryError.protected }

            let size = Int(bytes.u32(cursor + 24))
            totalSize += size
            guard totalSize <= 300 * 1024 * 1024 else { throw LibraryError.tooLarge }
            result.append(Entry(
                path: path, flags: flags, method: bytes.u16(cursor + 10),
                crc: bytes.u32(cursor + 16), compressedSize: Int(bytes.u32(cursor + 20)),
                size: size, offset: Int(bytes.u32(cursor + 42))
            ))
            cursor = next
        }
        return result
    }

    private func footerOffset() throws -> Int {
        guard bytes.count >= 22 else { throw LibraryError.invalidArchive }
        for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1) {
            if bytes.u32(offset) == 0x06054b50,
               offset + 22 + Int(bytes.u16(offset + 20)) == bytes.count {
                return offset
            }
        }
        throw LibraryError.invalidArchive
    }

    private func contents(of entry: Entry) throws -> Data {
        let offset = entry.offset
        guard offset + 30 <= bytes.count, bytes.u32(offset) == 0x04034b50,
              bytes.u16(offset + 6) == entry.flags, bytes.u16(offset + 8) == entry.method else {
            throw LibraryError.invalidArchive
        }
        let start = offset + 30 + Int(bytes.u16(offset + 26)) + Int(bytes.u16(offset + 28))
        let end = start + entry.compressedSize
        guard end <= bytes.count else { throw LibraryError.invalidArchive }

        let expanded: Data
        switch entry.method {
        case 0:
            expanded = Data(bytes[start..<end])
        case 8:
            expanded = try inflate(start..<end, expectedSize: entry.size)
        default:
            throw LibraryError.invalidArchive
        }
        let checksum = expanded.withUnsafeBytes {
            crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(expanded.count))
        }
        guard expanded.count == entry.size, checksum == entry.crc else { throw LibraryError.invalidArchive }
        return expanded
    }

    private func inflate(_ range: Range<Int>, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw LibraryError.invalidArchive
        }
        defer { inflateEnd(&stream) }

        var result = Data(count: max(1, expectedSize))
        let status = bytes.withUnsafeBytes { input in
            result.withUnsafeMutableBytes { output in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress?.advanced(by: range.lowerBound))
                stream.avail_in = uInt(range.count)
                stream.next_out = output.bindMemory(to: UInt8.self).baseAddress
                stream.avail_out = uInt(output.count)
                return CZlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.total_out == expectedSize, stream.avail_in == 0 else {
            throw LibraryError.invalidArchive
        }
        result.count = expectedSize
        return result
    }

    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}

private extension Data {
    func u16(_ index: Int) -> UInt16 {
        UInt16(self[index]) | UInt16(self[index + 1]) << 8
    }

    func u32(_ index: Int) -> UInt32 {
        UInt32(u16(index)) | UInt32(u16(index + 2)) << 16
    }
}
