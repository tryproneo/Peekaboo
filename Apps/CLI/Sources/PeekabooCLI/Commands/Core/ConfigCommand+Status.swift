import Foundation

@available(macOS 14.0, *)
@MainActor
struct ProviderStatusReporter {
    private let timeoutSeconds: Double

    init(timeoutSeconds: Double) { self.timeoutSeconds = timeoutSeconds > 0 ? timeoutSeconds : 30 }

    func printSummary() async {
        print("Providers:")
        print("  OpenRouter: \(self.openRouterStatus())")
        print("  Ollama: \(self.ollamaStatus())")
    }

    private func openRouterStatus() -> String {
        let env = ProcessInfo.processInfo.environment
        if let v = env["OPENROUTER_API_KEY"], !v.isEmpty { return "ready (env OPENROUTER_API_KEY)" }
        return "missing"
    }

    private func ollamaStatus() -> String {
        let env = ProcessInfo.processInfo.environment
        if let v = env["PEEKABOO_OLLAMA_BASE_URL"], !v.isEmpty { return "configured (env PEEKABOO_OLLAMA_BASE_URL)" }
        return "configured (default http://localhost:11434)"
    }
}
