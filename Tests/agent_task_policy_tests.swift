import Foundation

enum TestPermission: String {
    case readOnly, modify, destructive
}

func requiresConfirmation(_ permission: TestPermission) -> Bool {
    permission != .readOnly
}

func isSafeFTPPath(_ path: String) -> Bool {
    path.hasPrefix("/") &&
    !path.contains("\\") &&
    !path.split(separator: "/").contains("..") &&
    !path.contains("\0") &&
    path.utf8.count <= 512
}

func runAgentPolicyTests() {
    assert(!requiresConfirmation(.readOnly))
    assert(requiresConfirmation(.modify))
    assert(requiresConfirmation(.destructive))
    assert(isSafeFTPPath("/data/orbx/gta"))
    assert(isSafeFTPPath("/"))
    assert(!isSafeFTPPath("relative/path"))
    assert(!isSafeFTPPath("/data/../system"))
    assert(!isSafeFTPPath("/data\\system"))
    assert(!isSafeFTPPath("/" + String(repeating: "a", count: 520)))
    print("Autonomous agent policy tests passed.")
}

runAgentPolicyTests()
