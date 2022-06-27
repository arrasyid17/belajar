import Flutter
import UIKit
import AVFoundation

public class SwiftRecordPlugin: NSObject, FlutterPlugin, AVAudioRecorderDelegate {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.llfbandit.record", binaryMessenger: registrar.messenger())
    let instance = SwiftRecordPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  var isRecording = false
  var isPaused = false
  var audioRecorder: AVAudioRecorder?
  var path: String?
  var maxAmplitude:Float = -160.0;

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "start":
        let args = call.arguments as! [String : Any]
        path = args["path"] as? String

        if path == nil {
          let directory = NSTemporaryDirectory()
          let fileName = UUID().uuidString + ".m4a"

            path = NSURL.fileURL(withPathComponents: [directory, fileName])?.absoluteString
        }

        start(
          path: path!,
          encoder: args["encoder"] as! String,
          bitRate: args["bitRate"] as? Int ?? 128000,
          samplingRate: args["samplingRate"] as? Int ?? 44100,
          result: result)
        break
      case "stop":
        stop(result)
        break
      case "pause":
        pause(result)
      case "resume":
        resume(result)
      case "isPaused":
        result(isPaused)
      case "isRecording":
        result(isRecording)
        break
      case "hasPermission":
        hasPermission(result)
        break
      case "getAmplitude":
        getAmplitude(result)
        break
      case "isEncoderSupported":
        let args = call.arguments as! [String : Any]
        let encoder = args["encoder"] as! String
        let settings = getEncoderSettings(encoder)
        result(settings != nil)
        break
      case "dispose":
        dispose(result)
        break
      default:
        result(FlutterMethodNotImplemented)
        break
    }
  }
    
  public func applicationWillTerminate(_ application: UIApplication) {
    stopRecording()
  }

  fileprivate func hasPermission(_ result: @escaping FlutterResult) {
    switch AVAudioSession.sharedInstance().recordPermission {
      case .granted:
        result(true)
        break
      case .denied:
        result(false)
        break
      case .undetermined:
        AVAudioSession.sharedInstance().requestRecordPermission() { allowed in
          DispatchQueue.main.async {
            result(allowed)
          }
        }
        break
      default:
        break
    }
  }

  fileprivate func start(path: String, encoder: String, bitRate: Int, samplingRate: Int, result: @escaping FlutterResult) {
    stopRecording()

    let settings = getSettings(encoder: encoder, bitRate: bitRate, samplingRate: samplingRate)

    let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth]

    do {
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: options)
      try AVAudioSession.sharedInstance().setActive(true)

      let url = URL(string: path) ?? URL(fileURLWithPath: path)
      audioRecorder = try AVAudioRecorder(url: url, settings: settings)
      audioRecorder!.delegate = self
      audioRecorder!.isMeteringEnabled = true
      audioRecorder!.record()

      isRecording = true
      isPaused = false
      result(nil)
    } catch {
      result(FlutterError(code: "", message: "Failed to start recording", details: nil))
    }
  }

  fileprivate func stop(_ result: @escaping FlutterResult) {
    stopRecording()
    result(path)
  }
    
  fileprivate func pause(_ result: @escaping FlutterResult) {
    audioRecorder?.pause()
    isPaused = true
    result(nil)
  }
    
  fileprivate func resume(_ result: @escaping FlutterResult) {
    if isPaused {
      audioRecorder?.record()
      isPaused = false
    }
    
    result(nil)
  }

    fileprivate func isEncoderSupported(encoder: String) -> Bool {
    let encoderSettings = getEncoderSettings(encoder)
    return encoderSettings != nil
  }

  fileprivate func getAmplitude(_ result: @escaping FlutterResult) {
    var amp = ["current" : -160.0, "max" : -160.0] as [String : Float]

    if isRecording {
      audioRecorder?.updateMeters()
      
      guard let current = audioRecorder?.averagePower(forChannel: 0) else {
        result(amp)
        return
      }

      if (current > maxAmplitude) {
        maxAmplitude = current
      }

      amp["current"] = current
      amp["max"] = maxAmplitude
    }

    result(amp)
  }

  fileprivate func stopRecording() {
    audioRecorder?.stop()
    audioRecorder = nil
    isRecording = false
    isPaused = false
    maxAmplitude = -160.0
  }

  fileprivate func dispose(_ result: @escaping FlutterResult) {
    stopRecording()
    result(path)
  }

  fileprivate func getSettings(encoder: String, bitRate: Int, samplingRate: Int) -> [String : Any] {
    let settings = [
      AVEncoderBitRateKey: bitRate,
      AVSampleRateKey: samplingRate,
      AVNumberOfChannelsKey: 2,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ] as [String : Any]

    var encoderSettings = getEncoderSettings(encoder)
    // Defaults to ACC LD
    if (encoderSettings == nil) {
      encoderSettings = [AVFormatIDKey : Int(kAudioFormatMPEG4AAC)]
    }

    return settings.merging(encoderSettings!, uniquingKeysWith: { (_, last) in last })
  }

  // https://developer.apple.com/documentation/coreaudiotypes/coreaudiotype_constants/1572096-audio_data_format_identifiers
  fileprivate func getEncoderSettings(_ encoder: String) -> [String : Any]? {    
    switch(encoder) {
    case "aacEld":
      return [AVFormatIDKey : Int(kAudioFormatMPEG4AAC_ELD)]
    case "aacHe":
      return [AVFormatIDKey : Int(kAudioFormatMPEG4AAC_HE_V2)]
    case "amrNb":
      return [AVFormatIDKey : Int(kAudioFormatAMR)]
    case "amrWb":
      return [AVFormatIDKey : Int(kAudioFormatAMR_WB)]
    case "opus":
      return [AVFormatIDKey : Int(kAudioFormatOpus)]
    case "flac":
      return [AVFormatIDKey : Int(kAudioFormatFLAC)]
    case "pcm8bit":
      return [
        AVFormatIDKey : Int(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: 8,
      ]
    case "pcm16bit":
      return [
        AVFormatIDKey : Int(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: 16,
      ]
    case "aacLc":
      return [AVFormatIDKey : Int(kAudioFormatMPEG4AAC)]
    case "wav":
      return [AVFormatIDKey:Int(kAudioFormatLinearPCM)]
    default:
        return nil
    }
  }
}
