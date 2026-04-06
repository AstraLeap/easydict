import Cocoa
import FlutterMacOS

public class ZstdFfiPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // We only need to load the C library, no platform channels needed
  }
}
