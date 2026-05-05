import Foundation

enum GzipHelper {
    static func isGzipped(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let magic = handle.readData(ofLength: 2)
        return magic.count == 2 && magic[0] == 0x1f && magic[1] == 0x8b
    }

    static func decompress(at source: URL, to destination: URL) throws {
        guard let gz = gzopen(source.path, "rb") else {
            throw NSError(domain: "Gzip", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to open gzip file"])
        }
        defer { gzclose(gz) }

        guard let out = fopen(destination.path, "wb") else {
            throw NSError(domain: "Gzip", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create output file"])
        }
        defer { fclose(out) }

        let bufSize = 65_536
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        while true {
            let n = gzread(gz, buf, UInt32(bufSize))
            if n > 0 {
                fwrite(buf, 1, Int(n), out)
            } else if n == 0 {
                break
            } else {
                throw NSError(domain: "Gzip", code: Int(n),
                              userInfo: [NSLocalizedDescriptionKey: "Gzip decompression error"])
            }
        }
    }
}
