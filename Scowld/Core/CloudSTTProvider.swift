import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "CloudSTT")

// MARK: - Cloud STT Provider

enum STTBackend: String, CaseIterable {
    case nativeIOS = "native_ios"
    case openaiWhisper = "openai_whisper"
    case groqWhisper = "groq_whisper"
    case deepgram = "deepgram"
    case assemblyAI = "assemblyai"
    case googleCloud = "google_cloud_stt"
    case whisperBrowser = "whisper_browser"
    case none = "none"

    var displayName: String {
        switch self {
        case .nativeIOS: "Native iOS"
        case .openaiWhisper: "OpenAI Whisper"
        case .groqWhisper: "Groq Whisper"
        case .deepgram: "Deepgram"
        case .assemblyAI: "AssemblyAI"
        case .googleCloud: "Google Cloud STT"
        case .whisperBrowser: "Amica (Browser Whisper)"
        case .none: "None (text input only)"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .nativeIOS, .whisperBrowser, .none: false
        default: true
        }
    }

    var keychainKey: String {
        "com.scowld.stt.\(rawValue)"
    }

    var isCloudBased: Bool {
        switch self {
        case .openaiWhisper, .groqWhisper, .deepgram, .assemblyAI, .googleCloud: true
        default: false
        }
    }

    var footerText: String {
        switch self {
        case .nativeIOS: "Built-in iOS speech recognition. Free, on-device, no API needed."
        case .openaiWhisper: "High accuracy, cloud-based. $0.006/min."
        case .groqWhisper: "Whisper large-v3 on Groq hardware. Free tier: 8 hours/day. Very fast."
        case .deepgram: "Real-time transcription. $200 free credit on signup."
        case .assemblyAI: "High accuracy. 100 hours free."
        case .googleCloud: "Google Speech-to-Text. 60 min/month free."
        case .whisperBrowser: "Runs Whisper locally in the browser. Free, on-device."
        case .none: "Voice input disabled. Use text input only."
        }
    }
}

// MARK: - Cloud STT Manager

enum CloudSTTManager {

    /// Transcribe audio data using the selected cloud STT provider
    static func transcribe(audioData: Data, backend: STTBackend) async throws -> String {
        guard let apiKey = KeychainManager.load(key: backend.keychainKey), !apiKey.isEmpty else {
            throw CloudSTTError.noAPIKey
        }

        switch backend {
        case .openaiWhisper:
            return try await transcribeOpenAI(audioData: audioData, apiKey: apiKey)
        case .groqWhisper:
            return try await transcribeGroq(audioData: audioData, apiKey: apiKey)
        case .deepgram:
            return try await transcribeDeepgram(audioData: audioData, apiKey: apiKey)
        case .assemblyAI:
            return try await transcribeAssemblyAI(audioData: audioData, apiKey: apiKey)
        case .googleCloud:
            return try await transcribeGoogle(audioData: audioData, apiKey: apiKey)
        default:
            throw CloudSTTError.unsupportedBackend
        }
    }

    // MARK: - OpenAI Whisper

    private static func transcribeOpenAI(audioData: Data, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        let (data, _) = try await uploadMultipart(
            url: url,
            audioData: audioData,
            headers: ["Authorization": "Bearer \(apiKey)"],
            modelField: ("model", "whisper-1")
        )
        return try parseJSONText(data)
    }

    // MARK: - Groq Whisper

    private static func transcribeGroq(audioData: Data, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        let (data, _) = try await uploadMultipart(
            url: url,
            audioData: audioData,
            headers: ["Authorization": "Bearer \(apiKey)"],
            modelField: ("model", "whisper-large-v3")
        )
        return try parseJSONText(data)
    }

    // MARK: - Deepgram

    private static func transcribeDeepgram(audioData: Data, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CloudSTTError.apiError(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        // Parse Deepgram response: {"results":{"channels":[{"alternatives":[{"transcript":"..."}]}]}}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String else {
            throw CloudSTTError.parseError
        }
        return transcript
    }

    // MARK: - AssemblyAI

    private static func transcribeAssemblyAI(audioData: Data, apiKey: String) async throws -> String {
        // Step 1: Upload audio
        let uploadURL = URL(string: "https://api.assemblyai.com/v2/upload")!
        var uploadReq = URLRequest(url: uploadURL)
        uploadReq.httpMethod = "POST"
        uploadReq.setValue(apiKey, forHTTPHeaderField: "Authorization")
        uploadReq.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        uploadReq.httpBody = audioData

        let (uploadData, _) = try await URLSession.shared.data(for: uploadReq)
        guard let uploadJSON = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let uploadUrl = uploadJSON["upload_url"] as? String else {
            throw CloudSTTError.apiError("Failed to upload audio")
        }

        // Step 2: Create transcription
        let transcriptURL = URL(string: "https://api.assemblyai.com/v2/transcript")!
        var transcriptReq = URLRequest(url: transcriptURL)
        transcriptReq.httpMethod = "POST"
        transcriptReq.setValue(apiKey, forHTTPHeaderField: "Authorization")
        transcriptReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        transcriptReq.httpBody = try JSONSerialization.data(withJSONObject: ["audio_url": uploadUrl])

        let (transcriptData, _) = try await URLSession.shared.data(for: transcriptReq)
        guard let transcriptJSON = try? JSONSerialization.jsonObject(with: transcriptData) as? [String: Any],
              let transcriptId = transcriptJSON["id"] as? String else {
            throw CloudSTTError.apiError("Failed to create transcription")
        }

        // Step 3: Poll for completion
        let pollURL = URL(string: "https://api.assemblyai.com/v2/transcript/\(transcriptId)")!
        for _ in 0..<30 {
            try await Task.sleep(for: .seconds(1))
            var pollReq = URLRequest(url: pollURL)
            pollReq.setValue(apiKey, forHTTPHeaderField: "Authorization")
            let (pollData, _) = try await URLSession.shared.data(for: pollReq)
            guard let pollJSON = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any],
                  let status = pollJSON["status"] as? String else { continue }

            if status == "completed", let text = pollJSON["text"] as? String {
                return text
            } else if status == "error" {
                throw CloudSTTError.apiError(pollJSON["error"] as? String ?? "Transcription failed")
            }
        }
        throw CloudSTTError.timeout
    }

    // MARK: - Google Cloud STT

    private static func transcribeGoogle(audioData: Data, apiKey: String) async throws -> String {
        let url = URL(string: "https://speech.googleapis.com/v1/speech:recognize?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Audio = audioData.base64EncodedString()
        let body: [String: Any] = [
            "config": [
                "encoding": "LINEAR16",
                "sampleRateHertz": 16000,
                "languageCode": "en-US"
            ],
            "audio": [
                "content": base64Audio
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CloudSTTError.apiError(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        // Parse: {"results":[{"alternatives":[{"transcript":"..."}]}]}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let firstResult = results.first,
              let alternatives = firstResult["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String else {
            // Empty response means no speech detected
            return ""
        }
        return transcript
    }

    // MARK: - Helpers

    /// Upload audio as multipart/form-data (OpenAI/Groq compatible)
    private static func uploadMultipart(
        url: URL,
        audioData: Data,
        headers: [String: String],
        modelField: (String, String)
    ) async throws -> (Data, URLResponse) {
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var body = Data()
        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(modelField.0)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(modelField.1)\r\n".data(using: .utf8)!)
        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CloudSTTError.apiError(String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return (data, response)
    }

    /// Parse {"text":"..."} response
    private static func parseJSONText(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw CloudSTTError.parseError
        }
        return text
    }

    // MARK: - WAV Encoding

    /// Convert raw PCM audio buffers to WAV format
    static func createWAV(from buffers: [AVAudioPCMBuffer], format: AVAudioFormat) -> Data {
        // Calculate total frame count
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else { return Data() }

        let sampleRate = Int(format.sampleRate)
        let channels = Int(format.channelCount)
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let dataSize = totalFrames * channels * bytesPerSample

        var wavData = Data()

        // WAV header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(UInt32(36 + dataSize).littleEndianData)
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(UInt32(16).littleEndianData) // chunk size
        wavData.append(UInt16(1).littleEndianData) // PCM format
        wavData.append(UInt16(channels).littleEndianData)
        wavData.append(UInt32(sampleRate).littleEndianData)
        wavData.append(UInt32(sampleRate * channels * bytesPerSample).littleEndianData) // byte rate
        wavData.append(UInt16(channels * bytesPerSample).littleEndianData) // block align
        wavData.append(UInt16(bitsPerSample).littleEndianData)
        wavData.append("data".data(using: .ascii)!)
        wavData.append(UInt32(dataSize).littleEndianData)

        // Convert float samples to 16-bit PCM
        for buffer in buffers {
            guard let floatData = buffer.floatChannelData else { continue }
            let frameCount = Int(buffer.frameLength)
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let sample = floatData[channel][frame]
                    let clamped = max(-1.0, min(1.0, sample))
                    let int16 = Int16(clamped * Float(Int16.max))
                    wavData.append(int16.littleEndianData)
                }
            }
        }

        return wavData
    }
}

// MARK: - Errors

enum CloudSTTError: Error, LocalizedError {
    case noAPIKey
    case unsupportedBackend
    case apiError(String)
    case parseError
    case timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No API key configured for STT"
        case .unsupportedBackend: "Unsupported STT backend"
        case .apiError(let msg): "STT API error: \(msg)"
        case .parseError: "Failed to parse STT response"
        case .timeout: "STT transcription timed out"
        }
    }
}

// MARK: - Data Extensions for WAV

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: 4)
    }
}

extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: 2)
    }
}

extension Int16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: 2)
    }
}
