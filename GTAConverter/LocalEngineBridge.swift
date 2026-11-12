import Foundation

enum LocalEngineBridge {
    static var version: String {
        String(cString: gta_engine_version())
    }

    static func buildRPF7(from folder: URL, to output: URL) throws -> [String: Any] {
        let pointer = folder.path.withCString { input in
            output.path.withCString { destination in
                gta_engine_build_rpf7(input, destination)
            }
        }
        return try decode(pointer)
    }

    static func inspectRPF(at file: URL) throws -> [String: Any] {
        let pointer = file.path.withCString { gta_engine_probe_rpf($0) }
        return try decode(pointer)
    }

    static func extractRPF(at file: URL, to outputDirectory: URL) throws -> [String: Any] {
        let pointer = file.path.withCString { input in
            outputDirectory.path.withCString { output in
                gta_engine_extract_rpf(input, output)
            }
        }
        return try decode(pointer)
    }

    static func convertResource(at file: URL, to outputDirectory: URL) throws -> [String: Any] {
        let pointer = file.path.withCString { input in
            outputDirectory.path.withCString { output in
                gta_engine_convert_resource(input, output)
            }
        }
        return try decode(pointer)
    }

    static func extractYTD(at file: URL, to outputDirectory: URL) throws -> [String: Any] {
        let pointer = file.path.withCString { input in
            outputDirectory.path.withCString { output in
                gta_engine_extract_ytd(input, output)
            }
        }
        return try decode(pointer)
    }

    static func buildYTD(from folder: URL, to output: URL) throws -> [String: Any] {
        let pointer = folder.path.withCString { input in
            output.path.withCString { destination in
                gta_engine_build_ytd(input, destination)
            }
        }
        return try decode(pointer)
    }

    private static func decode(_ pointer: UnsafeMutablePointer<CChar>?) throws -> [String: Any] {
        guard let pointer else {
            throw NSError(domain: "GTALocalEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "المحرك ما رجّع نتيجة."])
        }
        defer { gta_engine_free_string(pointer) }

        let json = String(cString: pointer)
        guard let data = json.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "GTALocalEngine", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "صيغة تقرير المحرك غير مفهومة."])
        }
        guard (payload["ok"] as? Bool) == true else {
            throw NSError(domain: "GTALocalEngine", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: payload["error"] as? String ?? "فشلت العملية."])
        }
        return payload
    }
}
