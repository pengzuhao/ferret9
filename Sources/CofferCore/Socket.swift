import Darwin
import Foundation

enum LocalSocket {
    static func connect(_ path: String) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CofferError.unavailable("socket") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd); throw CofferError.invalid("路径过长")
        }
        _ = path.withCString { strncpy(&addr.sun_path.0, $0, MemoryLayout.size(ofValue: addr.sun_path)) }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) }
        }
        guard result == 0 else { Darwin.close(fd); throw CofferError.unavailable("无法连接服务") }
        return fd
    }

    static func listen(_ path: String) throws -> Int32 {
        unlink(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CofferError.unavailable("socket") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd); throw CofferError.invalid("路径过长")
        }
        _ = path.withCString { strncpy(&addr.sun_path.0, $0, MemoryLayout.size(ofValue: addr.sun_path)) }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, size) }
        }
        guard bound == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fd); throw CofferError.unavailable("bind \(path): \(reason)")
        }
        guard Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd); throw CofferError.unavailable("listen")
        }
        _ = chmod(path, 0o666)
        return fd
    }

    static func send(_ fd: Int32, _ data: Data) throws {
        var length = UInt32(data.count).bigEndian
        var payload = Data(bytes: &length, count: 4)
        payload.append(data)
        try payload.withUnsafeBytes { try writeAll(fd, $0) }
    }

    static func receive(_ fd: Int32) throws -> Data {
        var lenBuf = [UInt8](repeating: 0, count: 4)
        try readAll(fd, &lenBuf, 4)
        let length = Int(UInt32(bigEndian: lenBuf.withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard length > 0, length < 16_000_000 else { throw CofferError.invalid("响应过长") }
        var body = [UInt8](repeating: 0, count: length)
        try readAll(fd, &body, length)
        return Data(body)
    }

    private static func writeAll(_ fd: Int32, _ buffer: UnsafeRawBufferPointer) throws {
        var sent = 0
        while sent < buffer.count {
            let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
            if n <= 0 { throw CofferError.unavailable("write") }
            sent += n
        }
    }

    private static func readAll(_ fd: Int32, _ buf: inout [UInt8], _ count: Int) throws {
        var got = 0
        while got < count {
            let n = Darwin.read(fd, &buf[got], count - got)
            if n <= 0 { throw CofferError.unavailable("read") }
            got += n
        }
    }
}
