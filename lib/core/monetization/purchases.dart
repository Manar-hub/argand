import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import 'monetization.dart';

part 'purchases.g.dart';

/// RevenueCat's public SDK key.
const String revenueCatApiKey = String.fromEnvironment('REVENUECAT_API_KEY');

/// The entitlement the one-time Pro product is meant to grant.
const String proEntitlementId = 'Pro_tier';

/// Pro as the store offers it: its price, in the store's own format, and the
/// SDK's package to buy.
class ProOffer {
  const ProOffer({required this.price, required this.package});

  final String price;
  final Object package;
}

/// How a purchase or restore ended.
enum ProPurchaseResult {
  /// Pro is owned now.
  owned,

  /// Finished, and Pro is not owned -- a restore with nothing to restore.
  notOwned,

  /// The user backed out of the store's sheet. Nothing to say.
  cancelled,

  /// No connection to the store.
  offline,

  failed,
}

/// The store, as the app needs it. RevenueCat behind it in the app, a fake
/// in tests.
abstract interface class ProStore {
  /// Pro's offer, or null when the store has none set up. Throws
  /// [ProStoreException] when the store cannot be reached.
  Future<ProOffer?> offer();

  /// Whether Pro is owned after buying [offer]. Throws [ProStoreException].
  Future<bool> buy(ProOffer offer);

  /// Whether Pro is owned after restoring. Throws [ProStoreException].
  Future<bool> restore();

  /// Whether Pro is owned, or null when the store could not be asked.
  Future<bool?> owned();

  /// Called whenever the store learns Pro was bought, restored or revoked.
  void listen(void Function(bool owned) onChange);

  /// Starts over as a new customer who owns nothing -- for testing only.
  Future<void> reset();
}

/// Whether Pro can be reset for another test run: only against RevenueCat's
/// Test Store, where purchases are simulated and cost nothing.
bool get proResettable => revenueCatApiKey.startsWith('test_');

class ProStoreException implements Exception {
  const ProStoreException(this.result);

  final ProPurchaseResult result;
}

/// Picks the package that sells Pro: the lifetime one, else the only one,
/// else the first. No product id is written into the app -- the dashboard
/// decides what the current offering holds.
T? pickProPackage<T>(List<T> packages, bool Function(T) isLifetime) {
  if (packages.isEmpty) return null;
  for (final package in packages) {
    if (isLifetime(package)) return package;
  }
  return packages.first;
}

/// [ProStore] on RevenueCat.
class RevenueCatStore implements ProStore {
  RevenueCatStore() {
    _ready = () async {
      // The SDK's own account of each step, in debug builds only.
      if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(revenueCatApiKey));
    }()
        .catchError((Object error) => debugPrint('RevenueCat: $error'));
  }

  late final Future<void> _ready;

  /// How long a restore or a status check may take before it is given up
  /// as unreachable -- so no button ever spins for good. A purchase has no
  /// limit: the store's own sheet is on screen, waiting for the user.
  static const _patience = Duration(seconds: 30);

  static bool _entitled(CustomerInfo info) =>
      info.entitlements.active.containsKey(proEntitlementId) ||
      info.entitlements.active.isNotEmpty;

  static ProPurchaseResult _resultOf(PlatformException error) =>
      switch (PurchasesErrorHelper.getErrorCode(error)) {
        PurchasesErrorCode.purchaseCancelledError => ProPurchaseResult.cancelled,
        PurchasesErrorCode.networkError ||
        PurchasesErrorCode.offlineConnectionError =>
          ProPurchaseResult.offline,
        _ => ProPurchaseResult.failed,
      };

  @override
  Future<ProOffer?> offer() async {
    await _ready;
    try {
      final offering = (await Purchases.getOfferings()).current;
      final package = pickProPackage<Package>(
        offering?.availablePackages ?? const [],
        (p) => p.packageType == PackageType.lifetime,
      );
      debugPrint(
        'RevenueCat offering ${offering?.identifier}: '
        '${offering?.availablePackages.map((p) => '${p.identifier}/${p.storeProduct.identifier}').join(', ')}',
      );
      return package == null
          ? null
          : ProOffer(price: package.storeProduct.priceString, package: package);
    } on PlatformException catch (error) {
      debugPrint('RevenueCat offerings: ${error.message}');
      // Offline is worth saying; anything else (no products set up) reads as
      // Pro not being on sale.
      if (_resultOf(error) == ProPurchaseResult.offline) {
        throw const ProStoreException(ProPurchaseResult.offline);
      }
      return null;
    }
  }

  @override
  Future<bool> buy(ProOffer offer) async {
    await _ready;
    try {
      final result = await Purchases.purchase(
        PurchaseParams.package(offer.package as Package),
      );
      debugPrint(
        'RevenueCat purchase: active '
        '${result.customerInfo.entitlements.active.keys.join(', ')}',
      );
      return _entitled(result.customerInfo);
    } on PlatformException catch (error) {
      debugPrint('RevenueCat purchase: ${error.code} ${error.message}');
      throw ProStoreException(_resultOf(error));
    }
  }

  @override
  Future<bool> restore() async {
    await _ready;
    try {
      return _entitled(await Purchases.restorePurchases().timeout(_patience));
    } on PlatformException catch (error) {
      debugPrint('RevenueCat restore: ${error.code} ${error.message}');
      throw ProStoreException(_resultOf(error));
    } on TimeoutException {
      debugPrint('RevenueCat restore: timed out');
      throw const ProStoreException(ProPurchaseResult.offline);
    }
  }

  @override
  Future<bool?> owned() async {
    await _ready;
    try {
      final info = await Purchases.getCustomerInfo().timeout(_patience);
      debugPrint(
        'RevenueCat entitlements: ${info.entitlements.all.keys.join(', ')} '
        '(active: ${info.entitlements.active.keys.join(', ')})',
      );
      return _entitled(info);
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// A new anonymous customer. RevenueCat will not log an anonymous user
  /// out, so this logs in as a throwaway id first -- the old purchases go
  /// with it -- and then out, which starts a fresh anonymous customer.
  @override
  Future<void> reset() async {
    await _ready;
    await Purchases.logIn(
      'argand-test-${DateTime.now().millisecondsSinceEpoch}',
    );
    await Purchases.logOut();
  }

  @override
  void listen(void Function(bool owned) onChange) {
    unawaited(_ready.then((_) {
      Purchases.addCustomerInfoUpdateListener((info) => onChange(_entitled(info)));
    }));
  }
}

/// Buying and restoring Pro, and keeping the local flag in step with the store.
class ProPurchases {
  ProPurchases({
    required this.store,
    required this.database,
    required this.onChanged,
  });

  final ProStore store;
  final AppDatabase database;

  /// Tells the app the flag changed, so every Pro check reads it again.
  final void Function() onChanged;

  /// Starts listening and reconciles once with the store.
  Future<void> start() async {
    store.listen(_record);
    final owned = await store.owned();
    if (owned != null) await _record(owned);
  }

  Future<ProOffer?> offer() => store.offer();

  /// Pro off, as a new customer -- another take of a demo, another test of
  /// the purchase. Test Store only ([proResettable]).
  Future<void> resetForTesting() async {
    if (!proResettable) return;
    await store.reset();
    await _record(false);
  }

  Future<ProPurchaseResult> buy(ProOffer offer) =>
      _settle(() => store.buy(offer));

  Future<ProPurchaseResult> restore() => _settle(store.restore);

  Future<ProPurchaseResult> _settle(Future<bool> Function() action) async {
    try {
      final owned = await action();
      await _record(owned);
      return owned ? ProPurchaseResult.owned : ProPurchaseResult.notOwned;
    } on ProStoreException catch (error) {
      return error.result;
    } on Object catch (error) {
      // Anything else the SDK throws still ends the wait: a spinner that
      // never stops is worse than an error that can be tried again.
      debugPrint('Pro purchase failed: $error');
      return ProPurchaseResult.failed;
    }
  }

  Future<void> _record(bool owned) async {
    final was = await database.readSetting(proUnlockedKey) == 'true';
    if (was == owned) return;
    await database.writeSetting(proUnlockedKey, owned ? 'true' : 'false');
    onChanged();
  }
}

@Riverpod(keepAlive: true)
ProPurchases proPurchases(Ref ref) => ProPurchases(
      store: RevenueCatStore(),
      database: ref.watch(appDatabaseProvider),
      onChanged: () => ref.invalidate(proUnlockedProvider),
    );
