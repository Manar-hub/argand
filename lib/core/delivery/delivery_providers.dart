import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../translation/translator.dart';
import 'asset_pack_delivery.dart';
import 'fake_asset_pack_delivery.dart';

part 'delivery_providers.g.dart';

/// How packs reach the device: the fake until the app is on the store.
@Riverpod(keepAlive: true)
AssetPackDelivery assetPackDelivery(Ref ref) => FakeAssetPackDelivery(
      translator: ref.watch(translatorProvider),
      modelDirectory: getApplicationSupportDirectory,
    );
