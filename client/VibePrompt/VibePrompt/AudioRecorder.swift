import AVFoundation
import CoreAudio
import Foundation

// MARK: - Audio Device

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case engineFailure(String)
    case noAudioCaptured

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permiso de micrófono denegado. Actívalo en Preferencias del Sistema > Privacidad > Micrófono."
        case .engineFailure(let msg):
            return "Error al iniciar el audio: \(msg)"
        case .noAudioCaptured:
            return "No se capturó audio. Verifica que el micrófono esté conectado y seleccionado correctamente."
        }
    }
}

final class AudioRecorder {
    private var engine = AVAudioEngine()
    private var samples: [Int16] = []
    private let sampleRate: Double = 16000
    private var configObserver: NSObjectProtocol?
    private var warmedUp = false

    /// Prime the HAL by briefly starting the engine. Runs on the same engine
    /// instance used for recording so the HAL session carries over.
    func warmup() {
        guard Self.hasPermission() else { return }
        let node = engine.inputNode
        let fmt = node.inputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { return }
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { _, _ in }
        do { try engine.start() } catch { return }
        // Let HAL initialize briefly
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        node.removeTap(onBus: 0)
        engine.stop()
        warmedUp = true
        #if DEBUG
        print("[AudioRecorder] Warmup completo — HAL primed")
        #endif
    }
    private var selectedDeviceUID: String?

    // MARK: - Device enumeration

    static func availableInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        var devices: [AudioInputDevice] = []
        for deviceID in deviceIDs {
            // Check if device has input streams
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &streamSize)
            if streamSize == 0 { continue }

            // Skip aggregate devices (virtual "Default Device Aggregate" etc.)
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType)
            if transportType == kAudioDeviceTransportTypeAggregate { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef)
            let name = nameRef?.takeUnretainedValue() as String? ?? ""

            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidRef)
            let uid = uidRef?.takeUnretainedValue() as String? ?? ""

            devices.append(AudioInputDevice(id: deviceID, uid: uid, name: name))
        }
        return devices
    }

    /// Resolve AudioDeviceID from a UID string. Returns nil if not found (will use system default).
    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        availableInputDevices().first(where: { $0.uid == uid })?.id
    }

    // MARK: - Permissions

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func hasPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Recording

    func startRecording(deviceUID: String? = nil) throws {
        samples = []
        selectedDeviceUID = deviceUID

        guard Self.hasPermission() else {
            throw AudioRecorderError.permissionDenied
        }

        try startEngine()

        // Reiniciar si el dispositivo cambia (AirPods conectan/desconectan)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            try? self.restartEngine()
        }
    }

    private var isRunning: Bool { engine.isRunning }

    private func setInputDevice(on engine: AVAudioEngine) {
        guard let uid = selectedDeviceUID,
              let deviceID = Self.deviceID(forUID: uid) else { return }

        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else { return }

        var devID = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private func startEngine() throws {
        // Reuse the same engine to avoid orphaned HAL proxy contexts.
        // Just remove old tap and restart — keeps the HAL session alive.
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }

        try configureAndStart()
    }

    /// Configure input device, validate format, install tap, and start engine.
    private func configureAndStart() throws {
        setInputDevice(on: engine)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.engineFailure(
                "Dispositivo de audio no listo (sample rate: \(inputFormat.sampleRate)). " +
                "Si usas AirPods, espera un momento y vuelve a intentarlo."
            )
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioRecorderError.engineFailure("No se pudo crear el formato objetivo")
        }

        inputNode.removeTap(onBus: 0)
        installTap(on: inputNode, inputFormat: inputFormat, targetFormat: targetFormat)

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineFailure(error.localizedDescription)
        }
    }

    private func installTap(on inputNode: AVAudioInputNode, inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat),
                  let converted = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: AVAudioFrameCount(
                        Double(buffer.frameLength) * (self.sampleRate / inputFormat.sampleRate)
                    )
                  ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
            if error == nil, let channelData = converted.int16ChannelData {
                let chunk = Array(UnsafeBufferPointer(start: channelData[0], count: Int(converted.frameLength)))
                self.samples.append(contentsOf: chunk)
            }
        }
    }

    private func restartEngine() throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try startEngine()
    }

    func stopRecording() throws -> Data {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        guard !samples.isEmpty else {
            samples = []
            throw AudioRecorderError.noAudioCaptured
        }

        let peak = samples.map { abs(Int32($0)) }.max() ?? 0
        #if DEBUG
        let nonZero = samples.filter { $0 != 0 }.count
        print("[AudioRecorder] samples: \(samples.count), peak: \(peak), nonZero: \(nonZero)/\(samples.count) (\(samples.count > 0 ? nonZero * 100 / samples.count : 0)%)")
        #endif

        // Detect silent audio (HAL I/O failure delivers zero-filled buffers)
        guard peak > 0 else {
            samples = []
            throw AudioRecorderError.engineFailure(
                "El micrófono no capturó audio real. Intenta de nuevo."
            )
        }

        let data = makeWAVData(samples: samples)
        samples = []
        return data
    }

    private func makeWAVData(samples: [Int16]) -> Data {
        let sampleRateInt = UInt32(sampleRate)
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRateInt * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = UInt32(samples.count * 2)
        let chunkSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRateInt.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        var pcmData = Data(capacity: samples.count * 2)
        for sample in samples {
            pcmData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        return header + pcmData
    }
}
