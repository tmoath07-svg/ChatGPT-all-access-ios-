import Foundation
import Combine

struct INRPFTransferRecord: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let direction: String
    var completedBytes: Int64
    var totalBytes: Int64
    var state: String
    var updatedAt: Date

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

@MainActor
final class INRPFBackgroundTransferManager: NSObject, ObservableObject,
    URLSessionDataDelegate, URLSessionDownloadDelegate, URLSessionTaskDelegate {

    static let shared = INRPFBackgroundTransferManager()

    @Published private(set) var transfers: [INRPFTransferRecord] = []

    private let sessionIdentifier = "com.tmoath07.gta-converter.background-transfers"
    private let recordsKey = "inrpf.background-transfer-records"
    private let destinationsKey = "inrpf.background-transfer-destinations"
    private var backgroundCompletionHandler: (() -> Void)?
    private var uploadContinuations: [String: CheckedContinuation<Data, Error>] = [:]
    private var downloadContinuations: [String: CheckedContinuation<URL, Error>] = [:]
    private var responseBodies: [String: Data] = [:]
    private var downloadDestinations: [String: URL] = [:]
    private var downloadResults: [String: URL] = [:]
    private var session: URLSession!

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let saved = try? JSONDecoder().decode([INRPFTransferRecord].self, from: data) {
            transfers = saved
        }
        if let saved = UserDefaults.standard.dictionary(forKey: destinationsKey) as? [String: String] {
            downloadDestinations = saved.mapValues { URL(fileURLWithPath: $0) }
        }
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
        restoreActiveTasks()
    }

    func upload(_ request: URLRequest, from fileURL: URL, name: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID().uuidString
            uploadContinuations[id] = continuation
            responseBodies[id] = Data()
            upsertRecord(INRPFTransferRecord(
                id: id, name: name, direction: "رفع",
                completedBytes: 0, totalBytes: fileSize(fileURL),
                state: "قيد الرفع", updatedAt: Date()
            ))
            let task = session.uploadTask(with: request, fromFile: fileURL)
            task.taskDescription = id
            task.resume()
        }
    }

    func download(_ request: URLRequest, to destination: URL, name: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID().uuidString
            downloadContinuations[id] = continuation
            downloadDestinations[id] = destination
            persistDestinations()
            upsertRecord(INRPFTransferRecord(
                id: id, name: name, direction: "تنزيل",
                completedBytes: 0, totalBytes: 0,
                state: "قيد التنزيل", updatedAt: Date()
            ))
            let task = session.downloadTask(with: request)
            task.taskDescription = id
            task.resume()
        }
    }

    func handleEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == sessionIdentifier else {
            completionHandler()
            return
        }
        backgroundCompletionHandler = completionHandler
        _ = session
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let id = task.taskDescription else { return }
        Task { @MainActor [weak self] in
            self?.updateProgress(
                id: id, completed: totalBytesSent,
                total: totalBytesExpectedToSend, state: "قيد الرفع"
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor [weak self] in
            self?.updateProgress(
                id: id, completed: totalBytesWritten,
                total: totalBytesExpectedToWrite, state: "قيد التنزيل"
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard let id = dataTask.taskDescription else { return }
        Task { @MainActor [weak self] in
            self?.responseBodies[id, default: Data()].append(data)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor [weak self] in
            guard let self, let destination = self.downloadDestinations[id] else { return }
            do {
                let parent = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
                self.downloadResults[id] = destination
            } catch {
                self.finishDownload(id: id, result: .failure(error))
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = task.taskDescription else { return }
        let response = task.response as? HTTPURLResponse
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.completeTask(id: id, response: response, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let handler = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            handler?()
        }
    }

    private func completeTask(id: String, response: HTTPURLResponse?, error: Error?) {
        if let continuation = uploadContinuations.removeValue(forKey: id) {
            let body = responseBodies.removeValue(forKey: id) ?? Data()
            if let error {
                setState(id: id, state: "فشل")
                continuation.resume(throwing: error)
            } else if let response, (200...299).contains(response.statusCode) {
                setState(id: id, state: "اكتمل")
                continuation.resume(returning: body)
            } else {
                let code = response?.statusCode ?? 0
                setState(id: id, state: "فشل")
                continuation.resume(throwing: NSError(
                    domain: "INRPFBackgroundTransfer",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: "فشل رفع الملف إلى GitHub (HTTP \(code))."]
                ))
            }
            return
        }

        guard downloadContinuations[id] != nil else {
            if let error {
                setState(id: id, state: "فشل: \(error.localizedDescription)")
            } else if let response, (200...299).contains(response.statusCode) {
                setState(id: id, state: "اكتمل")
            }
            return
        }

        if let error {
            finishDownload(id: id, result: .failure(error))
        } else if let response, !(200...299).contains(response.statusCode) {
            finishDownload(id: id, result: .failure(NSError(
                domain: "INRPFBackgroundTransfer", code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "فشل تنزيل الملف (HTTP \(response.statusCode))."]
            )))
        } else if let url = downloadResults[id] {
            finishDownload(id: id, result: .success(url))
        } else {
            finishDownload(id: id, result: .failure(NSError(
                domain: "INRPFBackgroundTransfer", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "اكتمل اتصال التنزيل لكن الملف المؤقت لم يُحفظ."]
            )))
        }
    }

    private func finishDownload(id: String, result: Result<URL, Error>) {
        guard let continuation = downloadContinuations.removeValue(forKey: id) else { return }
        downloadResults[id] = nil
        downloadDestinations[id] = nil
        persistDestinations()
        switch result {
        case .success(let url):
            setState(id: id, state: "اكتمل")
            continuation.resume(returning: url)
        case .failure(let error):
            setState(id: id, state: "فشل")
            continuation.resume(throwing: error)
        }
    }

    private func updateProgress(id: String, completed: Int64, total: Int64, state: String) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        var record = transfers[index]
        record.completedBytes = completed
        if total > 0 { record.totalBytes = total }
        record.state = state
        record.updatedAt = Date()
        transfers[index] = record
        persistRecords()
    }

    private func setState(id: String, state: String) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        var record = transfers[index]
        record.state = state
        if state == "اكتمل", record.totalBytes > 0 {
            record.completedBytes = record.totalBytes
        }
        record.updatedAt = Date()
        transfers[index] = record
        persistRecords()
    }

    private func upsertRecord(_ record: INRPFTransferRecord) {
        transfers.removeAll { $0.id == record.id }
        transfers.insert(record, at: 0)
        if transfers.count > 30 { transfers = Array(transfers.prefix(30)) }
        persistRecords()
    }

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(transfers) else { return }
        UserDefaults.standard.set(data, forKey: recordsKey)
    }

    private func persistDestinations() {
        UserDefaults.standard.set(
            downloadDestinations.mapValues { $0.path },
            forKey: destinationsKey
        )
    }

    private func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func restoreActiveTasks() {
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                for task in tasks {
                    guard let id = task.taskDescription,
                          !self.transfers.contains(where: { $0.id == id }) else { continue }
                    self.upsertRecord(INRPFTransferRecord(
                        id: id, name: "نقل مستعاد", direction: task is URLSessionDownloadTask ? "تنزيل" : "رفع",
                        completedBytes: task.countOfBytesReceived + task.countOfBytesSent,
                        totalBytes: max(task.countOfBytesExpectedToReceive, task.countOfBytesExpectedToSend),
                        state: "قيد النقل", updatedAt: Date()
                    ))
                }
            }
        }
    }
}
