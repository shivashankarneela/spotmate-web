import 'package:supabase_flutter/supabase_flutter.dart';

Future<T> selectOptionalColumn<T>(
  String column,
  String fields,
  Future<T> Function(String) query,
) async {
  try {
    return await query(fields);
  } on PostgrestException catch (error) {
    if (error.code != '42703' || !error.message.contains(column)) rethrow;
    final fallback = fields.replaceAll(RegExp(',\\s*${RegExp.escape(column)}\\b'), '');
    return query(fallback);
  }
}
