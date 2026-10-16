import Sparkle

@MainActor
final class SparkleUpdater {
  static let shared = SparkleUpdater()

  private let controller: SPUStandardUpdaterController

  private init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: false,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    controller.updater.automaticallyChecksForUpdates = false
    controller.updater.updateCheckInterval = 3600
  }

  func checkForUpdates() {
    controller.startUpdater()
    controller.checkForUpdates(nil)
  }
}
