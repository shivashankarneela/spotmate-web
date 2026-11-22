import 'package:supabase_flutter/supabase_flutter.dart';

final Set<String> _unavailableColumns = {};

Future<T> selectOptionalColumn<T>(
  String column,
  String fields,
  Future<T> Function(String) query,
) async {
  String withoutColumn() =>
      fields.replaceAll(RegExp(',\\s*${RegExp.escape(column)}\\b'), '');

  if (_unavailableColumns.contains(column)) return query(withoutColumn());
  try {
    return await query(fields);
  } on PostgrestException catch (error) {
    if (error.code != '42703' || !error.message.contains(column)) rethrow;
    _unavailableColumns.add(column);
    return query(withoutColumn());
  }
}
