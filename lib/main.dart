import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'content/content_repository.dart';
import 'storage/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final store = await LocalStore.open();
  final repository = ContentRepository(store: store);
  runApp(PaperApp(store: store, repository: repository));
}
