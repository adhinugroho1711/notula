import AVFoundation
import Cocoa
import FlutterMacOS
import ScreenCaptureKit

class MainFlutterWindow: NSWindow {
  private var systemAudio: AnyObject?  // SystemAudioRecorder (macOS 13+)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Channel untuk perekam audio sistem + mic (native, ScreenCaptureKit).
    let channel = FlutterMethodChannel(
      name: "id.co.bankjateng.notula/system_audio",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleSystemAudio(call, result)
    }

    super.awakeFromNib()
  }

  private func handleSystemAudio(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      if #available(macOS 13.0, *) { result(true) } else { result(false) }

    case "start":
      guard #available(macOS 13.0, *) else {
        result(FlutterError(code: "unsupported",
                            message: "Butuh macOS 13 atau lebih baru.", details: nil))
        return
      }
      let args = call.arguments as? [String: Any]
      guard let path = args?["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path kosong", details: nil))
        return
      }
      let includeMic = (args?["includeMic"] as? Bool) ?? true
      let rec = SystemAudioRecorder()
      self.systemAudio = rec
      rec.start(path: path, includeMic: includeMic) { err in
        DispatchQueue.main.async {
          if let err = err {
            self.systemAudio = nil
            result(FlutterError(code: "start_failed", message: err, details: nil))
          } else {
            result(nil)
          }
        }
      }

    case "stop":
      guard #available(macOS 13.0, *), let rec = self.systemAudio as? SystemAudioRecorder else {
        result(nil)
        return
      }
      rec.stop { path in
        DispatchQueue.main.async {
          self.systemAudio = nil
          result(path)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - Perekam audio sistem (ScreenCaptureKit) + mikrofon (AVAudioEngine)

/// Merekam AUDIO SISTEM digabung dengan MIKROFON ke satu file .m4a — untuk
/// merekam rapat online (Zoom/Teams/Meet) tanpa perangkat loopback eksternal.
/// Butuh macOS 13+ & izin Screen Recording.
@available(macOS 13.0, *)
final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
  private var stream: SCStream?
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var file: AVAudioFile?
  private var outputPath: String = ""
  private var converter: AVAudioConverter?
  private let engineFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
  private let audioQueue = DispatchQueue(label: "notula.systemaudio")
  private var running = false

  func start(path: String, includeMic: Bool, completion: @escaping (String?) -> Void) {
    outputPath = path
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) {
      [weak self] content, error in
      guard let self = self else { return }
      if let error = error {
        completion("Gagal akses layar (izin Screen Recording?): \(error.localizedDescription)")
        return
      }
      guard let display = content?.displays.first else {
        completion("Tidak ada display untuk menangkap audio sistem.")
        return
      }
      let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
      let config = SCStreamConfiguration()
      config.capturesAudio = true
      config.excludesCurrentProcessAudio = true
      config.sampleRate = 48000
      config.channelCount = 2
      config.width = 2
      config.height = 2
      config.minimumFrameInterval = CMTime(value: 1, timescale: 6)

      do {
        try self.setupEngine(includeMic: includeMic)
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.audioQueue)
        self.stream = s
        s.startCapture { err in
          if let err = err {
            self.teardown()
            completion("Gagal memulai capture: \(err.localizedDescription)")
          } else {
            self.running = true
            completion(nil)
          }
        }
      } catch {
        self.teardown()
        completion("Setup perekam gagal: \(error.localizedDescription)")
      }
    }
  }

  private func setupEngine(includeMic: Bool) throws {
    engine.attach(player)
    let mixer = engine.mainMixerNode
    engine.connect(player, to: mixer, format: engineFormat)

    if includeMic {
      let input = engine.inputNode
      let inFormat = input.inputFormat(forBus: 0)
      if inFormat.sampleRate > 0 {
        engine.connect(input, to: mixer, format: inFormat)
      }
    }

    let mixFormat = mixer.outputFormat(forBus: 0)
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: mixFormat.sampleRate,
      AVNumberOfChannelsKey: mixFormat.channelCount,
      AVEncoderBitRateKey: 96000,
    ]
    file = try AVAudioFile(forWriting: URL(fileURLWithPath: outputPath), settings: settings)

    mixer.installTap(onBus: 0, bufferSize: 4096, format: mixFormat) { [weak self] buffer, _ in
      try? self?.file?.write(from: buffer)
    }
    engine.prepare()
    try engine.start()
    player.play()
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
              of type: SCStreamOutputType) {
    guard type == .audio, running else { return }
    guard let src = Self.pcmBuffer(from: sampleBuffer) else { return }
    guard let out = convert(src) else { return }
    if out.format == engineFormat {
      player.scheduleBuffer(out, completionHandler: nil)
    }
  }

  private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    if input.format == engineFormat { return input }
    if converter == nil || converter?.inputFormat != input.format {
      converter = AVAudioConverter(from: input.format, to: engineFormat)
    }
    guard let conv = converter else { return nil }
    let ratio = engineFormat.sampleRate / input.format.sampleRate
    let cap = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
    guard let out = AVAudioPCMBuffer(pcmFormat: engineFormat, frameCapacity: cap) else { return nil }
    var fed = false
    var err: NSError?
    conv.convert(to: out, error: &err) { _, status in
      if fed { status.pointee = .noDataNow; return nil }
      fed = true
      status.pointee = .haveData
      return input
    }
    return err == nil ? out : nil
  }

  private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)
    else { return nil }
    var sd = asbd.pointee
    guard let format = AVAudioFormat(streamDescription: &sd) else { return nil }
    let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
    guard frames > 0,
          let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
    else { return nil }
    pcm.frameLength = frames
    let err = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
    return err == noErr ? pcm : nil
  }

  func stop(completion: @escaping (String?) -> Void) {
    guard running else { completion(outputPath); return }
    running = false
    stream?.stopCapture { [weak self] _ in
      self?.teardown()
      completion(self?.outputPath)
    }
  }

  private func teardown() {
    engine.mainMixerNode.removeTap(onBus: 0)
    if player.isPlaying { player.stop() }
    if engine.isRunning { engine.stop() }
    file = nil
    stream = nil
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    running = false
    teardown()
  }
}
