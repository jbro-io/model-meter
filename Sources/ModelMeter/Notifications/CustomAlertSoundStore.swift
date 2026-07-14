import AVFoundation
import Foundation

struct CustomAlertSound: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let fileName: String
}

final class CustomAlertSoundStore {
    enum ImportError: LocalizedError, Equatable, Sendable {
        case sourceUnavailable
        case unreadableAudio
        case audioTooLong(duration: TimeInterval)
        case cannotCreateDirectory(detail: String)
        case conversionFailed(detail: String)
        case soundNotFound(fileName: String)

        var errorDescription: String? {
            switch self {
            case .sourceUnavailable:
                "The selected sound file could not be accessed."
            case .unreadableAudio:
                "The selected file is not an audio format that macOS can read."
            case .audioTooLong(let duration):
                "The selected sound is \(duration.formattedDuration) long. Custom notification sounds must be 30 seconds or shorter."
            case .cannotCreateDirectory:
                "Model Meter could not prepare your custom sound library."
            case .conversionFailed:
                "Model Meter could not convert the selected sound."
            case .soundNotFound:
                "The custom sound file could not be found."
            }
        }

        var failureReason: String? {
            switch self {
            case .cannotCreateDirectory(let detail), .conversionFailed(let detail):
                detail
            case .soundNotFound(let fileName):
                "\(fileName) is no longer in the Sounds folder."
            default:
                nil
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .sourceUnavailable:
                "Choose the file again and make sure Model Meter has permission to read it."
            case .unreadableAudio:
                "Choose another audio file that can be played by macOS."
            case .audioTooLong:
                "Trim the sound to 30 seconds or less, then import it again."
            case .cannotCreateDirectory:
                "Check the permissions for your user Library/Sounds folder and try again."
            case .conversionFailed:
                "Choose another audio file and try again."
            case .soundNotFound:
                "Import the sound again or select a different alert sound."
            }
        }
    }

    static let maximumDuration: TimeInterval = 30

    static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    let directoryURL: URL

    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    func importSound(from sourceURL: URL) throws -> CustomAlertSound {
        let hasSecurityScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        guard sourceURL.isFileURL,
              fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw ImportError.sourceUnavailable
        }

        let inputFile: AVAudioFile
        do {
            inputFile = try AVAudioFile(forReading: sourceURL)
        } catch {
            throw ImportError.unreadableAudio
        }

        let inputFormat = inputFile.processingFormat
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              inputFile.length > 0 else {
            throw ImportError.unreadableAudio
        }

        let duration = Double(inputFile.length) / inputFormat.sampleRate
        guard duration.isFinite, duration > 0 else {
            throw ImportError.unreadableAudio
        }
        guard duration <= Self.maximumDuration else {
            throw ImportError.audioTooLong(duration: duration)
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ImportError.cannotCreateDirectory(detail: error.localizedDescription)
        }

        let id = UUID().uuidString
        let fileName = "ModelMeter-\(id).caf"
        let destinationURL = directoryURL.appendingPathComponent(fileName)

        do {
            try transcode(inputFile, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if let importError = error as? ImportError {
                throw importError
            }
            throw ImportError.conversionFailed(detail: error.localizedDescription)
        }

        let sourceTitle = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomAlertSound(
            id: id,
            title: sourceTitle.isEmpty ? "Custom Sound" : sourceTitle,
            fileName: fileName
        )
    }

    func url(for sound: CustomAlertSound) -> URL? {
        guard sound.fileName == (sound.fileName as NSString).lastPathComponent else {
            return nil
        }

        let candidate = directoryURL.appendingPathComponent(sound.fileName)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        return candidate
    }

    func requiredURL(for sound: CustomAlertSound) throws -> URL {
        guard let url = url(for: sound) else {
            throw ImportError.soundNotFound(fileName: sound.fileName)
        }
        return url
    }

    private func transcode(_ inputFile: AVAudioFile, to destinationURL: URL) throws {
        let inputFormat = inputFile.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(
                forWriting: destinationURL,
                settings: settings
            )
        } catch {
            throw conversionError(error, stage: "Creating the converted sound")
        }
        let frameCapacity: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw ImportError.conversionFailed(
                detail: "The audio buffer could not be created."
            )
        }

        while inputFile.framePosition < inputFile.length {
            let remainingFrames = inputFile.length - inputFile.framePosition
            let framesToRead = AVAudioFrameCount(
                min(AVAudioFramePosition(frameCapacity), remainingFrames)
            )
            do {
                try inputFile.read(into: buffer, frameCount: framesToRead)
            } catch {
                throw conversionError(error, stage: "Reading the selected sound")
            }
            guard buffer.frameLength > 0 else { break }
            do {
                try outputFile.write(from: buffer)
            } catch {
                throw conversionError(error, stage: "Writing the converted sound")
            }
        }
    }

    private func conversionError(_ error: Error, stage: String) -> ImportError {
        let error = error as NSError
        return .conversionFailed(
            detail: "\(stage) failed (\(error.domain) \(error.code)): \(error.localizedDescription)"
        )
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        formatted(
            .number
                .precision(.fractionLength(1))
                .locale(.current)
        ) + " seconds"
    }
}
