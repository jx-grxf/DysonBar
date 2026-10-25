import Foundation

public enum ProductCatalog {
  /// Marketing names for the model codes the cloud reports. Unknown codes fall
  /// back to the code itself, which is what the sticker on the device says.
  static let names: [String: String] = [
    "TP04": "Pure Cool",
    "TP06": "Pure Cool Cryptomic",
    "TP07": "Purifier Cool",
    "TP09": "Purifier Cool Formaldehyde",
    "TP10": "Purifier Cool Gen1",
    "TP11": "Purifier Cool PC1",
    "TP12": "Purifier Cool PC2 De-NOx",
    "DP04": "Pure Cool Desk",
    "HP04": "Pure Hot+Cool",
    "HP06": "Pure Hot+Cool Cryptomic",
    "HP07": "Purifier Hot+Cool",
    "HP09": "Purifier Hot+Cool Formaldehyde",
    "HP10": "Purifier Hot+Cool Gen1",
    "PH01": "Pure Humidify+Cool",
    "PH02": "Pure Humidify+Cool Cryptomic",
    "PH03": "Purifier Humidify+Cool",
    "PH04": "Purifier Humidify+Cool Formaldehyde",
    "BP02": "Purifier Big+Quiet",
    "BP03": "Purifier Big+Quiet",
    "BP04": "Purifier Big+Quiet Formaldehyde",
  ]

  /// Product types that speak the 2018+ protocol (`fpwr`, `fnsp`, `auto` …).
  /// The older Pure Cool Link family (455, 469, 475) uses `fmod` and is not supported.
  static let legacyTypes: Set<String> = ["455", "469", "475"]

  public static func name(model: String?, type: String) -> String {
    if let model, let name = names[model.uppercased()] { return name }
    return model ?? type
  }

  public static func isSupported(type: String) -> Bool {
    !legacyTypes.contains(String(type.prefix(3)))
  }
}
