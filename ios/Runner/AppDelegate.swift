import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Refresco de fondo del widget. iOS exige registrar el handler del
    // BGTaskScheduler antes de que termine el arranque: con UIScene los
    // plugins se registran después, y si el primer registro llega desde Dart
    // (`Workmanager().registerPeriodicTask`) iOS tira
    // NSInternalInconsistencyException y la app se cierra. El id es el de
    // `widgetRefreshTaskId` y BGTaskSchedulerPermittedIdentifiers.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.portyassistant.app.widget_refresh",
      earliestBeginInSeconds: NSNumber(value: 30 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
