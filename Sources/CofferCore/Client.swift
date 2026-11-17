import Foundation

public enum Client {
    public static func call(_ request: Request, socketPath: String = CofferPaths.socket) throws -> Response {
        let fd = try LocalSocket.connect(socketPath)
        defer { close(fd) }
        try LocalSocket.send(fd, Wire.encode(request))
        return try Wire.decode(Response.self, from: LocalSocket.receive(fd))
    }
}
