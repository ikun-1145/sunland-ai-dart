import CoreHaptics
import UIKit

final class AIHapticManager {
  enum Feedback {
    case aiStarted
    case answerStarted
    case answerCompleted
  }

  private let hapticQueue = DispatchQueue(
    label: "sunland.ai.core-haptics",
    qos: .userInitiated
  )
  private let notificationCenter: NotificationCenter
  private let supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
  private var engine: CHHapticEngine?
  private var activePlayer: CHHapticPatternPlayer?
  private var engineStarted = false
  private var applicationIsActive = UIApplication.shared.applicationState == .active
  private var notificationObservers: [NSObjectProtocol] = []
  private var fallbackSequence = 0

  init(notificationCenter: NotificationCenter = .default) {
    self.notificationCenter = notificationCenter
    notificationObservers = [
      notificationCenter.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.hapticQueue.async {
          self?.handleDidEnterBackground()
        }
      },
      notificationCenter.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.hapticQueue.async {
          self?.handleDidBecomeActive()
        }
      },
    ]

    guard supportsCoreHaptics else { return }
    hapticQueue.async { [weak self] in
      _ = self?.ensureEngineStarted()
    }
  }

  deinit {
    for observer in notificationObservers {
      notificationCenter.removeObserver(observer)
    }
  }

  func play(_ feedback: Feedback) {
    hapticQueue.async { [weak self] in
      guard let self = self, self.applicationIsActive else { return }
      if self.supportsCoreHaptics {
        self.playCoreHaptic(feedback)
      } else {
        self.playUIKitFallback(feedback)
      }
    }
  }

  private func ensureEngineStarted() -> CHHapticEngine? {
    if engine == nil {
      do {
        let newEngine = try CHHapticEngine()
        newEngine.isAutoShutdownEnabled = true
        newEngine.stoppedHandler = { [weak self] _ in
          self?.hapticQueue.async {
            self?.engineStarted = false
            self?.activePlayer = nil
          }
        }
        newEngine.resetHandler = { [weak self] in
          self?.hapticQueue.async {
            guard let self = self else { return }
            self.engineStarted = false
            self.activePlayer = nil
            guard self.applicationIsActive else { return }
            if self.startEngine(newEngine) == false {
              self.engine = nil
            }
          }
        }
        engine = newEngine
      } catch {
        engine = nil
        engineStarted = false
        return nil
      }
    }

    guard let engine = engine else { return nil }
    if !engineStarted && !startEngine(engine) {
      self.engine = nil
      return nil
    }
    return engine
  }

  private func startEngine(_ engine: CHHapticEngine) -> Bool {
    do {
      try engine.start()
      engineStarted = true
      return true
    } catch {
      engineStarted = false
      return false
    }
  }

  private func playCoreHaptic(_ feedback: Feedback) {
    guard let engine = ensureEngineStarted() else {
      playUIKitFallback(feedback)
      return
    }

    do {
      try activePlayer?.stop(atTime: CHHapticTimeImmediate)
      let pattern = try CHHapticPattern(
        events: events(for: feedback),
        parameters: []
      )
      let player = try engine.makePlayer(with: pattern)
      activePlayer = player
      try player.start(atTime: CHHapticTimeImmediate)
    } catch {
      activePlayer = nil
    }
  }

  private func events(for feedback: Feedback) -> [CHHapticEvent] {
    switch feedback {
    case .aiStarted:
      return [transient(time: 0.0, intensity: 0.42, sharpness: 0.86)]
    case .answerStarted:
      return [
        transient(time: 0.00, intensity: 0.62, sharpness: 0.88),
        transient(time: 0.14, intensity: 0.46, sharpness: 0.84),
        transient(time: 0.29, intensity: 0.32, sharpness: 0.78),
        transient(time: 0.46, intensity: 0.20, sharpness: 0.70),
        transient(time: 0.66, intensity: 0.11, sharpness: 0.60),
        transient(time: 0.88, intensity: 0.05, sharpness: 0.48),
      ]
    case .answerCompleted:
      return [
        transient(time: 0.00, intensity: 0.32, sharpness: 0.80),
        transient(time: 0.19, intensity: 0.50, sharpness: 0.90),
      ]
    }
  }

  private func transient(
    time: TimeInterval,
    intensity: Float,
    sharpness: Float
  ) -> CHHapticEvent {
    return CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
      ],
      relativeTime: time
    )
  }

  private func playUIKitFallback(_ feedback: Feedback) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self,
        UIApplication.shared.applicationState == .active
      else {
        return
      }

      self.fallbackSequence += 1
      let sequence = self.fallbackSequence

      switch feedback {
      case .aiStarted:
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
      case .answerStarted:
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.55)
      case .answerCompleted:
        let first = UIImpactFeedbackGenerator(style: .light)
        first.prepare()
        first.impactOccurred(intensity: 0.45)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) { [weak self] in
          guard let self = self,
            self.fallbackSequence == sequence,
            UIApplication.shared.applicationState == .active
          else {
            return
          }
          let second = UIImpactFeedbackGenerator(style: .rigid)
          second.prepare()
          second.impactOccurred(intensity: 0.65)
        }
      }
    }
  }

  private func handleDidEnterBackground() {
    applicationIsActive = false
    DispatchQueue.main.async { [weak self] in
      self?.fallbackSequence += 1
    }
    try? activePlayer?.stop(atTime: CHHapticTimeImmediate)
    activePlayer = nil
    guard let engine = engine else { return }
    engine.stop { [weak self] _ in
      self?.hapticQueue.async {
        self?.engineStarted = false
      }
    }
  }

  private func handleDidBecomeActive() {
    applicationIsActive = true
    guard supportsCoreHaptics else { return }
    _ = ensureEngineStarted()
  }
}
