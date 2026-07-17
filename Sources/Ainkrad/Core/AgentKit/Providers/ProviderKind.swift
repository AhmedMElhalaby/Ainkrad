// Sources/Ainkrad/Core/AgentKit/Providers/ProviderKind.swift
import Foundation

/// The wire protocol a provider speaks — the only thing that selects an
/// `LLMProvider` implementation. Data-driven providers replace the old
/// hardcoded two-case provider enum.
enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case claude
    case openAICompatible
    case gemini
}
