import Foundation
import Supabase

enum AuthDiagnostics {
    static func trace<Value>(
        _ operation: String,
        status: (Value) -> Int? = { _ in nil },
        perform: () async throws -> Value
    ) async rethrows -> Value {
        #if DEBUG
        let start = ProcessInfo.processInfo.systemUptime
        log(operation, "start", elapsed: 0)
        do {
            let value = try await perform()
            log(operation, "success", elapsed: ProcessInfo.processInfo.systemUptime - start,
                status: status(value))
            return value
        } catch {
            log(operation, outcome(error), elapsed: ProcessInfo.processInfo.systemUptime - start,
                error: error)
            throw error
        }
        #else
        return try await perform()
        #endif
    }

    #if DEBUG
    static func outcome(_ error: Error?) -> String {
        guard let error else { return "success" }
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return "cancelled"
        }
        return "failure"
    }

    static func log(_ operation: String, _ event: String, elapsed: TimeInterval,
                    status: Int? = nil, code: String? = nil, error: Error? = nil) {
        var httpStatus = status
        var errorCode = code
        if let authError = error as? AuthError {
            errorCode = authError.errorCode.rawValue
            if case .api(_, _, _, let response) = authError {
                httpStatus = response.statusCode
            }
        } else if let databaseError = error as? PostgrestError {
            errorCode = databaseError.code
        }

        let safeCode = errorCode.flatMap { value in
            value.range(of: #"\A[A-Za-z0-9_]{1,64}\z"#, options: .regularExpression) == nil ? nil : value
        } ?? "-"
        let urlCode = (error as? URLError).map { String($0.code.rawValue) } ?? "-"
        let milliseconds = Int(elapsed * 1000)
        let hasSession = SupabaseManager.client.auth.currentSession != nil
        print("[SkillSwapAuthDebug] operation=\(operation) event=\(event) http=\(httpStatus.map(String.init) ?? "-") supabaseCode=\(safeCode) urlError=\(urlCode) elapsedMs=\(milliseconds) sessionPresent=\(hasSession)")
    }
    #endif
}

#if DEBUG
final class AuthDiagnosticsSessionDelegate: NSObject, URLSessionDataDelegate {
    private func operation(for task: URLSessionTask) -> String? {
        guard let url = task.originalRequest?.url else { return nil }
        if url.path == "/auth/v1/token" {
            let grant = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "grant_type" }?.value
            switch grant {
            case "refresh_token": return "tokenRefresh"
            case "password": return "signIn.http"
            default: return nil
            }
        }

        guard task.originalRequest?.httpMethod == "GET" else { return nil }
        switch url.path {
        case "/rest/v1/profiles": return "profiles.http"
        case "/rest/v1/student_skills": return "student_skills.http"
        case "/rest/v1/availability": return "availability.http"
        default: return nil
        }
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        guard operation(for: task) != nil else { return }
        task.taskDescription = String(ProcessInfo.processInfo.systemUptime)
        if operation(for: task) == "tokenRefresh" {
            AuthDiagnostics.log("tokenRefresh", "start", elapsed: 0)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let operation = operation(for: task) else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let event = (status ?? 0) >= 400 ? "failure" : AuthDiagnostics.outcome(error)
        let now = ProcessInfo.processInfo.systemUptime
        let start = task.taskDescription.flatMap(Double.init) ?? now
        AuthDiagnostics.log(operation, event, elapsed: now - start, status: status, error: error)
    }
}
#endif
