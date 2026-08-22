import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var backgroundExecutionChannel: FlutterMethodChannel?
  private var nextBackgroundTaskToken = 1
  private var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "sunland.ai/background_execution",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    backgroundExecutionChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }

      switch call.method {
      case "begin":
        let arguments = call.arguments as? [String: Any]
        let name = arguments?["name"] as? String ?? "Sunland background operation"
        result(self.beginBackgroundTask(named: name))
      case "end":
        let arguments = call.arguments as? [String: Any]
        let taskId = (arguments?["taskId"] as? NSNumber)?.intValue
        if let taskId = taskId {
          self.finishBackgroundTask(taskId)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func beginBackgroundTask(named name: String) -> Int? {
    let token = nextBackgroundTaskToken
    nextBackgroundTaskToken += 1

    var identifier = UIBackgroundTaskIdentifier.invalid
    identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      self?.finishBackgroundTask(token)
    }
    guard identifier != .invalid else { return nil }

    backgroundTasks[token] = identifier
    return token
  }

  private func finishBackgroundTask(_ token: Int) {
    let finish = { [weak self] in
      guard let self = self,
        let identifier = self.backgroundTasks.removeValue(forKey: token)
      else {
        return
      }
      UIApplication.shared.endBackgroundTask(identifier)
    }

    if Thread.isMainThread {
      finish()
    } else {
      DispatchQueue.main.async(execute: finish)
    }
  }
}
