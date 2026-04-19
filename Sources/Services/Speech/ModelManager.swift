import Foundation
import WhisperKit

/// Manages WhisperKit model lifecycle: download, load, and availability.
///
/// Uses a shared storage root at `~/Documents/Models/WhisperKit/` so that
/// CuePrompt and other apps (e.g. Whisp) share the same multi-GB
/// models without duplication. Falls back to the legacy app-specific path
/// for existing installs.
@Observable
final class ModelManager {

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case error(String)
    }

    private(set) var state: ModelState = .notDownloaded
    private(set) var modelPath: String?

    /// Preferred model name. Defaults to a small, fast model.
    var preferredModel: String = "openai_whisper-base"

    // Required CoreML bundles that must exist for a valid model
    private static let requiredBundles = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    /// Shared model storage root: ~/Documents/Models/WhisperKit/
    /// Both CuePrompt and Whisp use this location.
    private var baseDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Models/WhisperKit", isDirectory: true)
    }

    /// Legacy app-specific path for existing installs (read-only fallback).
    private var legacyBaseDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CuePrompt/huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    /// Full path for a specific model variant.
    private func modelDirectory(for variant: String) -> URL? {
        baseDirectory?.appendingPathComponent(variant, isDirectory: true)
    }

    /// Check what models are available locally by validating CoreML bundles.
    /// Checks the shared location first, then legacy fallback paths.
    func scanLocalModels() {
        debugLog("[ModelManager] scanLocalModels — preferred: \(preferredModel)")

        // If we already have a validated model path, keep it
        if let existing = modelPath, isModelValid(at: existing) {
            debugLog("[ModelManager] Existing path still valid: \(existing)")
            state = .downloaded
            return
        }

        // Check the standard location for the preferred model
        if let dir = modelDirectory(for: preferredModel) {
            debugLog("[ModelManager] Checking shared location: \(dir.path)")
            if isModelValid(at: dir.path) {
                modelPath = dir.path
                state = .downloaded
                debugLog("[ModelManager] Found valid model at shared location")
                return
            }
        }

        // Check for any valid model in the base directory
        if let base = baseDirectory {
            debugLog("[ModelManager] Checking base directory: \(base.path)")
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(atPath: base.path) {
                for item in contents where !item.hasPrefix(".") {
                    let path = base.appendingPathComponent(item).path
                    if isModelValid(at: path) {
                        modelPath = path
                        state = .downloaded
                        debugLog("[ModelManager] Found valid model: \(item)")
                        return
                    }
                }
            }
        }

        // Check legacy fallback paths
        debugLog("[ModelManager] Checking fallback locations...")
        if let found = findDownloadedModel() {
            modelPath = found
            state = .downloaded
            debugLog("[ModelManager] Found model at: \(found)")
            return
        }

        debugLog("[ModelManager] No valid model found")
        state = .notDownloaded
    }

    /// Download the preferred model using WhisperKit's built-in mechanism.
    /// WhisperKit handles the download, placement, and structure.
    func downloadModel() async {
        state = .downloading(progress: 0)

        do {
            // Use WhisperKit's standard download — just pass the model name.
            // WhisperKit handles the download, placement, and structure.
            let config = WhisperKitConfig(model: preferredModel)

            state = .downloading(progress: 0.5)

            let kit = try await WhisperKit(config)

            // WhisperKit initialized successfully — the model is downloaded and valid.
            // Find where it put the model.
            if let dir = modelDirectory(for: preferredModel), isModelValid(at: dir.path) {
                modelPath = dir.path
            } else {
                // WhisperKit may have used its own default location — find it
                modelPath = findDownloadedModel()
            }

            _ = kit // keep reference alive through download
            state = .downloaded
        } catch {
            state = .error("Download failed: \(error.localizedDescription)")
        }
    }

    /// Create a WhisperKit instance from the locally downloaded model.
    func loadWhisperKit() async throws -> WhisperKit {
        guard let path = modelPath, isModelValid(at: path) else {
            debugLog("[ModelManager] loadWhisperKit FAILED — no valid model. modelPath=\(modelPath ?? "nil")")
            throw ModelError.noModel
        }

        debugLog("[ModelManager] loadWhisperKit from: \(path)")
        state = .loading

        // Force offline mode so WhisperKit doesn't try network access
        setenv("HF_HUB_OFFLINE", "1", 1)
        setenv("TRANSFORMERS_OFFLINE", "1", 1)
        setenv("HF_HUB_DISABLE_IMPLICIT_TOKEN", "1", 1)

        // Only pass modelFolder — not model name — to avoid confusion
        let config = WhisperKitConfig(modelFolder: path)
        let kit = try await WhisperKit(config)
        debugLog("[ModelManager] WhisperKit loaded successfully. tokenizer=\(kit.tokenizer != nil)")
        state = .ready
        return kit
    }

    // MARK: - Validation

    /// Check that a model directory contains the three required CoreML bundles
    /// with sentinel files, confirming the download completed successfully.
    private func isModelValid(at path: String) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        let url = URL(fileURLWithPath: path)
        for bundle in Self.requiredBundles {
            let bundleURL = url.appendingPathComponent(bundle)
            var isBundleDir: ObjCBool = false
            guard fm.fileExists(atPath: bundleURL.path, isDirectory: &isBundleDir),
                  isBundleDir.boolValue else {
                return false
            }
            // Check for sentinel file
            let sentinel = bundleURL.appendingPathComponent("coremldata.bin")
            if !fm.fileExists(atPath: sentinel.path) {
                return false
            }
        }
        return true
    }

    /// Search known WhisperKit download locations for the model.
    /// Checks the shared root first, then legacy app-specific and generic paths.
    private func findDownloadedModel() -> String? {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first

        let candidates = [
            // 1. Shared root (primary)
            baseDirectory?.appendingPathComponent(preferredModel),
            // 2. Legacy CuePrompt app-specific path (read-only fallback)
            legacyBaseDirectory?.appendingPathComponent(preferredModel),
            // 3. WhisperKit's old default ~/Documents/huggingface/...
            documents?.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(preferredModel)"),
        ]

        for candidate in candidates {
            if let path = candidate?.path, isModelValid(at: path) {
                return path
            }
        }

        return nil
    }

    enum ModelError: LocalizedError {
        case noModel

        var errorDescription: String? {
            switch self {
            case .noModel: return "No model available. Download a model first."
            }
        }
    }
}
