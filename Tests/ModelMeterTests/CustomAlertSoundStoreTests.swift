import AVFoundation
import XCTest
@testable import ModelMeter

final class CustomAlertSoundStoreTests: XCTestCase {
    func testImportConvertsDecodableAudioToCAFAndMakesItResolvable() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceURL = workspace.appendingPathComponent("Soft Chime.wav")
        let soundsDirectory = workspace.appendingPathComponent("Imported Sounds", isDirectory: true)
        try writePCMFile(to: sourceURL, duration: 0.2)

        let store = CustomAlertSoundStore(directoryURL: soundsDirectory)
        let importedSound = try store.importSound(from: sourceURL)
        let importedURL = try XCTUnwrap(store.url(for: importedSound))

        XCTAssertEqual(importedSound.title, "Soft Chime")
        XCTAssertEqual(importedSound.fileName, importedURL.lastPathComponent)
        XCTAssertEqual(importedURL.pathExtension.lowercased(), "caf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
        XCTAssertTrue(
            importedURL.standardizedFileURL.path.hasPrefix(
                soundsDirectory.standardizedFileURL.path + "/"
            )
        )

        let importedFile = try AVAudioFile(forReading: importedURL)
        let duration = Double(importedFile.length) / importedFile.processingFormat.sampleRate
        XCTAssertGreaterThan(duration, 0)
        XCTAssertEqual(duration, 0.2, accuracy: 0.02)
    }

    func testImportAcceptsAIFFInput() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceURL = workspace.appendingPathComponent("Bell.aiff")
        let soundsDirectory = workspace.appendingPathComponent("Imported Sounds", isDirectory: true)
        try writePCMFile(to: sourceURL, duration: 0.1)

        let store = CustomAlertSoundStore(directoryURL: soundsDirectory)
        let importedSound = try store.importSound(from: sourceURL)
        let importedURL = try XCTUnwrap(store.url(for: importedSound))

        XCTAssertEqual(importedURL.pathExtension.lowercased(), "caf")
        XCTAssertNoThrow(try AVAudioFile(forReading: importedURL))
    }

    func testImportAcceptsMP3Input() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceURL = workspace.appendingPathComponent("Quiet Alert.mp3")
        let soundsDirectory = workspace.appendingPathComponent("Imported Sounds", isDirectory: true)
        try XCTUnwrap(Data(base64Encoded: Self.silentMP3Base64)).write(to: sourceURL)

        let store = CustomAlertSoundStore(directoryURL: soundsDirectory)
        let importedSound = try store.importSound(from: sourceURL)
        let importedURL = try XCTUnwrap(store.url(for: importedSound))

        XCTAssertEqual(importedSound.title, "Quiet Alert")
        XCTAssertEqual(importedURL.pathExtension.lowercased(), "caf")
        XCTAssertNoThrow(try AVAudioFile(forReading: importedURL))
    }

    func testImportRejectsAudioLongerThanNotificationLimit() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceURL = workspace.appendingPathComponent("Too Long.wav")
        let soundsDirectory = workspace.appendingPathComponent("Imported Sounds", isDirectory: true)
        try writePCMFile(to: sourceURL, duration: 30.1)

        let store = CustomAlertSoundStore(directoryURL: soundsDirectory)

        XCTAssertThrowsError(try store.importSound(from: sourceURL))
        let importedFiles = (try? FileManager.default.contentsOfDirectory(
            at: soundsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertFalse(importedFiles.contains { $0.pathExtension.lowercased() == "caf" })
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelMeterCustomSoundTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePCMFile(to url: URL, duration: TimeInterval) throws {
        let sampleRate = 8_000.0
        let frameCount = AVAudioFrameCount((sampleRate * duration).rounded())
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount

        if let samples = buffer.floatChannelData?[0] {
            for frame in 0..<Int(frameCount) {
                samples[frame] = sin(Float(frame) * 0.05) * 0.05
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: url.pathExtension.lowercased() == "aiff",
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    /// 150 ms of synthesized silence encoded as a mono MP3. Keeping the fixture
    /// inline makes this test independent of optional encoders on the host Mac.
    private static let silentMP3Base64 = "SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYyLjMuMTAwAAAAAAAAAAAAAAD/+0DAAAAAAAAAAAAAAAAAAAAAAABJbmZvAAAADwAAAAcAAAORAFBQUFBQUFBQUFBQUFBQbW1tbW1tbW1tbW1tbW2KioqKioqKioqKioqKiqioqKioqKioqKioqKioqMXFxcXFxcXFxcXFxcXF4uLi4uLi4uLi4uLi4uL//////////////////wAAAABMYXZjNjIuMTEAAAAAAAAAAAAAAAAkA2kAAAAAAAADkbmgFvoAAAAAAP/7EMQAA8AAAaQAAAAgAAA0gAAABExBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBV//sSxCmDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sQxFODwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+xLEfQPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+xDEpwPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7EsTQg8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7EMTWA8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV"
}
