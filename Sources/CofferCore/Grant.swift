import Foundation
import Security

public enum Grant {
    public static func issue() throws -> String {
        var auth: AuthorizationRef?
        let st = CofferPaths.right.withCString { n in
            var it = AuthorizationItem(name: n, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &it) { p in
                var r = AuthorizationRights(count: 1, items: p)
                return AuthorizationCreate(&r, nil, [.interactionAllowed, .extendRights, .preAuthorize], &auth)
            }
        }
        guard st == errAuthorizationSuccess, let auth else { throw CofferError.refused("授权取消") }
        AuthorizationFree(auth, [])
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let file = CofferPaths.root + "/grants/" + token
        let expiry = String(Date().addingTimeInterval(300).timeIntervalSince1970)
        let user = CofferPaths.serviceUser
        let script = "mkdir -p " + CofferPaths.root + "/grants && printf %s " + expiry + " > " + file + " && chown " + user + ":" + user + " " + file + " && chmod 600 " + file
        let source = "do shell script \"" + script + "\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw CofferError.refused("授权票据写入失败") }
        return token
    }
}
