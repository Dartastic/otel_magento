// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_magento_suppression.dart';

const _tracerName = 'dartastic_otel_libs_magento';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class MagentoResult {
  const MagentoResult({
    this.itemCount,
    this.totalCount,
    this.protocol,
    this.scope,
    this.storeCode,
    this.orderState,
    this.paymentMethod,
    this.totalAmountMinor,
    this.currency,
    this.cacheHit,
    this.requestId,
    this.statusCode,
  });

  /// `items.length`.
  final int? itemCount;

  /// `total_count` from search responses.
  final int? totalCount;

  /// `rest` / `graphql` / `async_bulk` — distinct latency profiles.
  final String? protocol;

  /// `default` (admin) / `store` (storefront) / `all` — REST scopes.
  final String? scope;

  /// `Store-Code` header (multi-store deployments).
  final String? storeCode;

  /// `new` / `processing` / `complete` / `closed` / `canceled` /
  /// `holded` / `pending_payment` / `payment_review`.
  final String? orderState;

  /// Payment method code (`stripe`, `braintree`, `paypal_express`,
  /// `checkmo`, `purchaseorder`, ...).
  final String? paymentMethod;

  /// Grand total in minor units.
  final int? totalAmountMinor;

  /// ISO 4217.
  final String? currency;

  /// `X-Magento-Cache-Debug: HIT|MISS` (Varnish/full page cache).
  final bool? cacheHit;

  /// `X-Magento-Tags` style request id (when present).
  final String? requestId;

  final int? statusCode;
}

class MagentoCallResult<T> {
  const MagentoCallResult({required this.value, this.result});
  final T value;
  final MagentoResult? result;
}

/// Wraps a Magento / Adobe Commerce API call in a CLIENT span.
/// [operation] is one of `products.search`, `products.get`,
/// `products.create`, `orders.search`, `orders.get`, `orders.cancel`,
/// `orders.invoice`, `orders.ship`, `customers.search`,
/// `customers.get`, `carts.create`, `carts.add_item`, `carts.totals`,
/// `carts.place_order`, `inventory.source_items.list`,
/// `inventory.reservations.list`, `cms.blocks.list`, `categories.list`,
/// `webhooks.create`.
Future<T> tracedMagento<T>({
  required String operation,
  required Future<MagentoCallResult<T>> Function() invoke,
  String? protocol,
  String? scope,
}) async {
  if (magentoInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'rpc.system': 'magento',
    'rpc.method': operation,
    'magento.operation': operation,
  };
  if (protocol != null) m['magento.protocol'] = protocol;
  if (scope != null) m['magento.scope'] = scope;

  final span = _tracer().startSpan(
    'magento $operation',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.itemCount != null) {
        extras.add(
          OTel.attributeInt('magento.item_count', r.result!.itemCount!),
        );
      }
      if (r.result!.totalCount != null) {
        extras.add(
          OTel.attributeInt('magento.total_count', r.result!.totalCount!),
        );
      }
      if (r.result!.protocol != null) {
        extras.add(
          OTel.attributeString('magento.protocol', r.result!.protocol!),
        );
      }
      if (r.result!.scope != null) {
        extras.add(OTel.attributeString('magento.scope', r.result!.scope!));
      }
      if (r.result!.storeCode != null) {
        extras.add(
          OTel.attributeString('magento.store_code', r.result!.storeCode!),
        );
      }
      if (r.result!.orderState != null) {
        extras.add(
          OTel.attributeString('magento.order.state', r.result!.orderState!),
        );
        if (r.result!.orderState == 'canceled') {
          span.setStatus(SpanStatusCode.Error, 'Magento order canceled');
        }
      }
      if (r.result!.paymentMethod != null) {
        extras.add(
          OTel.attributeString(
            'magento.payment_method',
            r.result!.paymentMethod!,
          ),
        );
      }
      if (r.result!.totalAmountMinor != null) {
        extras.add(
          OTel.attributeInt(
            'magento.amount.total.minor',
            r.result!.totalAmountMinor!,
          ),
        );
      }
      if (r.result!.currency != null) {
        extras.add(
          OTel.attributeString('magento.currency', r.result!.currency!),
        );
      }
      if (r.result!.cacheHit != null) {
        extras.add(
          OTel.attributeBool('magento.cache.hit', r.result!.cacheHit!),
        );
      }
      if (r.result!.requestId != null) {
        extras.add(
          OTel.attributeString('magento.request.id', r.result!.requestId!),
        );
      }
      if (r.result!.statusCode != null) {
        extras.add(
          OTel.attributeInt('http.response.status_code', r.result!.statusCode!),
        );
        if (r.result!.statusCode! >= 400) {
          span.setStatus(
            SpanStatusCode.Error,
            'Magento HTTP ${r.result!.statusCode}',
          );
        }
      }
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(
      OTel.attributes([
        OTel.attributeString(
          ErrorResource.errorType.key,
          e.runtimeType.toString(),
        ),
      ]),
    );
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
