// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_magento/otel_magento.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_magento-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) => {
    for (final a in s.attributes.toList()) a.key: a.value,
  };

  test('carts.place_order records protocol + scope + amount', () async {
    await tracedMagento<String>(
      operation: 'carts.place_order',
      protocol: 'graphql',
      scope: 'store',
      invoke: () async => const MagentoCallResult(
        value: 'ok',
        result: MagentoResult(
          protocol: 'graphql',
          scope: 'store',
          storeCode: 'default',
          orderState: 'processing',
          paymentMethod: 'braintree',
          totalAmountMinor: 14500,
          currency: 'EUR',
          statusCode: 200,
        ),
      ),
    );
    final a = attrsOf(spans.findSpanByName('magento carts.place_order')!);
    expect(a['magento.protocol'], 'graphql');
    expect(a['magento.scope'], 'store');
    expect(a['magento.store_code'], 'default');
    expect(a['magento.payment_method'], 'braintree');
    expect(a['magento.amount.total.minor'], 14500);
  });

  test('canceled order sets span error', () async {
    await tracedMagento<String>(
      operation: 'orders.cancel',
      invoke: () async => const MagentoCallResult(
        value: 'ok',
        result: MagentoResult(orderState: 'canceled'),
      ),
    );
    expect(
      spans.findSpanByName('magento orders.cancel')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutMagentoInstrumentationAsync(() async {
      await tracedMagento<String>(
        operation: 'products.search',
        invoke: () async => const MagentoCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('magento '), isEmpty);
  });
}
