/// Lightweight PHP currency parsing and formatting utilities.
/// Avoids external dependencies (like intl) while providing consistent display.
class PhpCurrency {
  /// Parse any string containing a price into a double.
  /// Examples:
  ///  - "₱1,234.50" -> 1234.50
  ///  - "1,234" -> 1234.0
  ///  - "199.9" -> 199.9
  /// Returns null if no digits found.
  static double? parse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    // Keep digits and at most one decimal point
    final match = RegExp(r"[-+]?[0-9]*\.?[0-9]+").firstMatch(s);
    if (match == null) return null;
    final numStr = match.group(0)!;
    return double.tryParse(numStr);
  }

  /// Format a number as PHP currency with thousands separators and 2 decimals.
  /// Example: 1234.5 -> "₱1,234.50"
  static String format(num amount) {
    final neg = amount < 0;
    final absVal = amount.abs();
    final fixed = absVal.toStringAsFixed(2); // e.g. 1234.50
    final parts = fixed.split('.');
    var intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '00';
    final reg = RegExp(r"(\d+)(\d{3})");
    while (reg.hasMatch(intPart)) {
      intPart = intPart.replaceAllMapped(reg, (m) => "${m[1]},${m[2]}");
    }
    final core = '$intPart.$decPart';
    return (neg ? '-₱' : '₱') + core;
  }

  /// Try to parse a string and format it as PHP currency.
  /// If parsing fails, returns the original string (or empty string if null).
  static String formatFromString(String? raw) {
    final v = parse(raw);
    if (v == null) return raw?.toString() ?? '';
    return format(v);
  }

  /// Convenience for integer totals (e.g., when sums are in whole pesos).
  static String formatInt(int amount) => format(amount);
}
