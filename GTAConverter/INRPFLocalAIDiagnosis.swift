import Foundation
import SwiftLlama

@MainActor
enum INRPFLocalAIDiagnosis {
    static func analyze(reportText: String) async throws -> String {
        let modelName = "qwen2.5-1.5b-instruct-q4_k_m"
        guard let modelURL =
            Bundle.main.url(forResource: modelName, withExtension: "gguf", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: modelName, withExtension: "gguf")
            ?? Bundle.main.resourceURL?.appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(modelName + ".gguf"),
              FileManager.default.fileExists(atPath: modelURL.path) else {
            throw NSError(domain: "INRPF.LocalAI", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "ملف Qwen المحلي غير موجود داخل التطبيق."])
        }

        let service = LlamaService(
            modelUrl: modelURL,
            config: LlamaConfig(
                batchSize: 256,
                maxTokenCount: 3072,
                useGPU: true,
                microBatchSize: 128,
                nThreads: 1,
                nThreadsBatch: 1
            )
        )
        let system = """
        أنت محلل INRPF محلي لمودات GTA V وFiveM. حلل الأدلة المرفقة فقط.
        اكتب بالعربية وبشكل عملي: نوع المود، المشاكل المؤكدة مع مساراتها، المشاكل المحتملة، ثم إصلاحات آمنة قابلة للعكس.
        لا تخترع محتوى ملفات لم يتم قراءتها. لا تدّعِ أن ملفات تم تعديلها.
        لا تقترح تعديل ملفات YFT أو YTD أو RPF الثنائية كنص. لا تضمن توافق PS4 من أسماء الملفات فقط.
        إذا كانت الأدلة غير كافية، اذكر بالضبط ما يلزم فحصه لاحقاً.
        """
        let user = """
        افحص تقرير المود التالي، وحدد المشاكل ذات الأولوية والحلول التي يمكن تنفيذها بأمان.
        التقرير:
        \(String(reportText.prefix(12_000)))
        """
        do {
            let messages = [
                LlamaChatMessage(role: .system, content: system),
                LlamaChatMessage(role: .user, content: user)
            ]
            let stream = try await service.streamCompletion(
                of: messages,
                samplingConfig: LlamaSamplingConfig(temperature: 0.2, seed: 42, topP: 0.9, topK: 40)
            )
            var output = ""
            for try await token in stream {
                output += token
                if output.count >= 12_000 { break }
            }
            await service.stopCompletion()
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "INRPF.LocalAI", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "النموذج لم يُرجع تشخيصاً."])
            }
            return output
        } catch {
            await service.stopCompletion()
            throw error
        }
    }
}
