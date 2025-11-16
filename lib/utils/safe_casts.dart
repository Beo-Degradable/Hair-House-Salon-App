List<Map<String, dynamic>> safeListOfMaps(dynamic v) {
  if (v == null) return <Map<String, dynamic>>[];
  if (v is List) {
    return v.map<Map<String, dynamic>>((e) {
      if (e is Map) return Map<String, dynamic>.from(e);
      return <String, dynamic>{};
    }).toList();
  }
  return <Map<String, dynamic>>[];
}

List<String> safeListOfStrings(dynamic v) {
  if (v == null) return <String>[];
  if (v is List) {
    return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }
  return <String>[];
}
