import 'dart:async';

import 'package:argand/core/database/database.dart';
import 'package:argand/core/monetization/monetization.dart';
import 'package:argand/core/monetization/purchases.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements ProStore {
  bool? ownedNow = false;
  Object? buyError;
  bool buyGrants = true;
  bool restoreFinds = false;
  void Function(bool)? listener;

  @override
  Future<ProOffer?> offer() async =>
      const ProOffer(price: r'$9.99', package: 'lifetime');

  @override
  Future<bool> buy(ProOffer offer) async {
    if (buyError case final error?) throw error;
    return buyGrants;
  }

  @override
  Future<bool> restore() async => restoreFinds;

  @override
  Future<bool?> owned() async => ownedNow;

  @override
  void listen(void Function(bool owned) onChange) => listener = onChange;

  bool resets = false;

  /// Holds a reset open, as a store stuck switching customers does.
  Completer<void>? stall;

  @override
  Future<void> reset() async {
    resets = true;
    await stall?.future;
    ownedNow = false;
  }
}

class _Ad implements LoadedRewardedAd {
  _Ad(this.earns);

  final bool earns;
  bool shown = false;

  @override
  Future<bool> present() async {
    shown = true;
    return earns;
  }
}

class _Source implements RewardedAdSource {
  _Source(this.ads);

  final List<LoadedRewardedAd?> ads;
  int loads = 0;

  @override
  Future<LoadedRewardedAd?> load() async {
    loads++;
    return ads.isEmpty ? null : ads.removeAt(0);
  }
}

void main() {
  group('pickProPackage', () {
    test('the lifetime package, wherever it sits', () {
      expect(pickProPackage(['annual', 'lifetime'], (p) => p == 'lifetime'),
          'lifetime');
    });

    test('else the only one, and nothing from nothing', () {
      expect(pickProPackage(['custom'], (p) => p == 'lifetime'), 'custom');
      expect(pickProPackage(<String>[], (p) => true), isNull);
    });
  });

  group('ProPurchases', () {
    late AppDatabase database;
    late _Store store;
    late ProPurchases purchases;
    var changes = 0;

    Future<bool> flag() async =>
        await database.readSetting(proUnlockedKey) == 'true';

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      store = _Store();
      changes = 0;
      purchases = ProPurchases(
        store: store,
        database: database,
        onChanged: () => changes++,
      );
    });

    tearDown(() => database.close());

    test('buying sets the flag every Pro check reads, and says so once',
        () async {
      final result = await purchases.buy((await purchases.offer())!);
      expect(result, ProPurchaseResult.owned);
      expect(await flag(), isTrue);
      expect(await claimProWaiver(database), isNotNull);
      expect(changes, 1);
    });

    test('a cancelled purchase changes nothing', () async {
      store.buyError = const ProStoreException(ProPurchaseResult.cancelled);
      expect(await purchases.buy((await purchases.offer())!),
          ProPurchaseResult.cancelled);
      expect(await flag(), isFalse);
      expect(changes, 0);
    });

    test('restore finds it, or says there was nothing', () async {
      expect(await purchases.restore(), ProPurchaseResult.notOwned);
      store.restoreFinds = true;
      expect(await purchases.restore(), ProPurchaseResult.owned);
      expect(await flag(), isTrue);
    });

    test('starting reconciles with the store, including a revocation',
        () async {
      store.ownedNow = true;
      await purchases.start();
      expect(await flag(), isTrue);

      // Revoked (a refund, a test purchase undone): the store says so.
      store.listener!(false);
      await Future<void>.delayed(Duration.zero);
      expect(await flag(), isFalse);
    });

    test('resetting for a new take turns Pro off as a new customer',
        () async {
      await purchases.buy((await purchases.offer())!);
      expect(await flag(), isTrue);
      await purchases.resetForTesting();
      expect(store.resets, isTrue);
      expect(await flag(), isFalse);
    });

    test('a reset turns Pro off at once, even while the store stalls',
        () async {
      await purchases.start();
      await purchases.buy((await purchases.offer())!);
      store.stall = Completer<void>();

      final reset = purchases.resetForTesting();
      await Future<void>.delayed(Duration.zero);
      expect(await flag(), isFalse);

      // The old customer's Pro, reported mid-switch, does not come back.
      store.listener!(true);
      await Future<void>.delayed(Duration.zero);
      expect(await flag(), isFalse);

      store.stall!.complete();
      await reset;
      // A purchase after the reset counts again.
      store.listener!(true);
      await Future<void>.delayed(Duration.zero);
      expect(await flag(), isTrue);
    });

    test('a test customer is made once and replaced on reset', () async {
      final customer = TestCustomer(database);
      final first = await customer.current();
      expect(await customer.current(), first);
      final next = await customer.next();
      expect(next, isNot(first));
      expect(await customer.current(), next);
    });

    test('a store that cannot be asked leaves Pro as it was (offline)',
        () async {
      await database.writeSetting(proUnlockedKey, 'true');
      store.ownedNow = null;
      await purchases.start();
      expect(await flag(), isTrue);
    });
  });

  group('SdkRewardedAds', () {
    testWidgets('watched to the end: a waiver, and the next ad loads',
        (tester) async {
      final source = _Source([_Ad(true), _Ad(false)]);
      final ads = SdkRewardedAds(source);
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }));

      expect(await ads.canLoad(), isTrue);
      final outcome = await ads.show(context);
      expect(outcome, isA<AdRewarded>());
      await tester.pump();
      expect(source.loads, 2);

      // Closed early: nothing.
      expect(await ads.show(context), isA<AdDismissed>());
    });

    testWidgets('the network has none: the built-in ad plays; offline, none',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }));
      var online = true;
      final ads = FallbackRewardedAds(
        primary: SdkRewardedAds(_Source([])),
        fallback: PlaceholderRewardedAds(
          present: (_) async => true,
          probe: () async => online,
        ),
      );
      expect(await ads.canLoad(), isTrue);
      expect(await ads.show(context), isA<AdRewarded>());

      online = false;
      expect(await ads.canLoad(), isFalse);
      expect(await ads.show(context), isA<AdUnavailable>());
    });

    testWidgets('no ad to load: unavailable, and no waiver', (tester) async {
      final ads = SdkRewardedAds(_Source([]));
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }));
      expect(await ads.canLoad(), isFalse);
      expect(await ads.show(context), isA<AdUnavailable>());
    });
  });
}
