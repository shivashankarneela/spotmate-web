import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_keyboard_models.dart';

class GifSearchService {
  GifSearchService({this.tenorApiKey = '', this.giphyApiKey = ''});

  final String tenorApiKey;
  final String giphyApiKey;

  bool get hasLiveKey => tenorApiKey.isNotEmpty || giphyApiKey.isNotEmpty;

  Future<List<SpotmateGifItem>> search(String query) async {
    final q = query.trim();

    if (tenorApiKey.isNotEmpty) {
      final uri = q.isEmpty
          ? Uri.https('tenor.googleapis.com', '/v2/featured', {
              'key': tenorApiKey,
              'limit': '24',
              'media_filter': 'tinygif,gif',
            })
          : Uri.https('tenor.googleapis.com', '/v2/search', {
              'key': tenorApiKey,
              'q': q,
              'limit': '24',
              'media_filter': 'tinygif,gif',
            });
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (decoded['results'] as List<dynamic>? ?? []);
        return list.whereType<Map<String, dynamic>>().map((item) {
          final media = (item['media_formats'] as Map<String, dynamic>? ?? {});
          final tiny = (media['tinygif'] as Map<String, dynamic>? ?? {});
          final full = (media['gif'] as Map<String, dynamic>? ?? tiny);
          final dims = (full['dims'] as List<dynamic>? ?? [240, 180]);
          return SpotmateGifItem(
            id: (item['id'] ?? '').toString(),
            title: (item['content_description'] ?? 'GIF').toString(),
            previewUrl: (tiny['url'] ?? full['url'] ?? '').toString(),
            gifUrl: (full['url'] ?? tiny['url'] ?? '').toString(),
            width: dims.isNotEmpty ? (dims[0] as num).toInt() : 240,
            height: dims.length > 1 ? (dims[1] as num).toInt() : 180,
          );
        }).where((g) => g.gifUrl.isNotEmpty).toList();
      }
    }

    if (giphyApiKey.isNotEmpty) {
      final uri = q.isEmpty
          ? Uri.https('api.giphy.com', '/v1/gifs/trending', {
              'api_key': giphyApiKey,
              'limit': '24',
              'rating': 'pg-13',
            })
          : Uri.https('api.giphy.com', '/v1/gifs/search', {
              'api_key': giphyApiKey,
              'q': q,
              'limit': '24',
              'rating': 'pg-13',
            });
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (decoded['data'] as List<dynamic>? ?? []);
        return list.whereType<Map<String, dynamic>>().map((item) {
          final imgs = (item['images'] as Map<String, dynamic>? ?? {});
          final preview = (imgs['fixed_width_small'] as Map<String, dynamic>? ?? {});
          final full = (imgs['fixed_width'] as Map<String, dynamic>? ?? preview);
          return SpotmateGifItem(
            id: (item['id'] ?? '').toString(),
            title: (item['title'] ?? 'GIF').toString(),
            previewUrl: (preview['url'] ?? full['url'] ?? '').toString(),
            gifUrl: (full['url'] ?? preview['url'] ?? '').toString(),
            width: int.tryParse((full['width'] ?? '240').toString()) ?? 240,
            height: int.tryParse((full['height'] ?? '180').toString()) ?? 180,
          );
        }).where((g) => g.gifUrl.isNotEmpty).toList();
      }
    }

    return const [];
  }
}
