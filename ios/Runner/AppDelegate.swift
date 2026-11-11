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
    // Push: firebase_messaging (15.x) hace toda su preparación de iOS al
    // recibir UIApplicationDidFinishLaunchingNotification (pedir el token de
    // APNs, ser delegado de UNUserNotificationCenter, recibir el token). Con
    // UIScene el motor y los plugins se crean DESPUÉS de esa notificación, así
    // que el plugin se la pierde: sin token de APNs no hay token de FCM y el
    // dispositivo nunca se registra (outbox → skipped/no_devices). Se le
    // reenvía acá, ya registrado. Es el único plugin que la escucha (ver
    // ios/.symlinks/plugins). Sacar cuando el plugin soporte UIScene.
    NotificationCenter.default.post(
      name: UIApplication.didFinishLaunchingNotification,
      object: UIApplication.shared
    )
  }
}
