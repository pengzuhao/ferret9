import Darwin
import Foundation
import Security

do {
    let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? CofferPaths.root, isDirectory: true)
    let socketPath = CommandLine.arguments.dropFirst(2).first ?? CofferPaths.socket
    try? FileManager.default.createDirectory(at: root.appendingPathComponent("grants"), withIntermediateDirectories: true)
    let broker = Broker(store: Store(directory: root)) { AuthorizationCheck.allow($0) }
    let listener = try openListener(socketPath)
    fputs("ferret9-service listening \(socketPath)\n", stderr)
    while true {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { continue }
        DispatchQueue.global().async {
            defer { close(client) }
            let response: Response
            if let data = try? LocalSocket.receive(client), let req = try? Wire.decode(Request.self, from: data) {
                response = broker.handle(req)
            } else {
                response = Response(ok: false, message: "请求无法识别")
            }
            try? LocalSocket.send(client, Wire.encode(response))
        }
    }
} catch {
    fputs("ferret9-service fatal: \(error)\n", stderr)
    exit(1)
}

@_silgen_name("launch_activate_socket")
func launchActivateSocket(_ name: UnsafePointer<CChar>, _ fds: UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>, _ count: UnsafeMutablePointer<UInt>) -> Int32

func openListener(_ path: String) throws -> Int32 {
    var fds: UnsafeMutablePointer<Int32>?
    var count: UInt = 0
    let status = "Listener".withCString { launchActivateSocket($0, &fds, &count) }
    if status == 0, let fds, count > 0 {
        let fd = fds[0]; free(fds); return fd
    }
    return try LocalSocket.listen(path)
}

enum AuthorizationCheck {
    static func allow(_ value: String?) -> Bool {
        guard let value, value.count == 32, value.allSatisfy({ $0.isHexDigit }) else { return false }
        let file = URL(fileURLWithPath: CofferPaths.root).appendingPathComponent("grants").appendingPathComponent(value)
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let expiry = TimeInterval(text), expiry > Date().timeIntervalSince1970 else { return false }
        return true
    }
}
