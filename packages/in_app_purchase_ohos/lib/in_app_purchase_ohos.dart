import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

const _channel = MethodChannel('lkm.in_app_purchase/ohos');
const _source = 'huawei_iap';

class HuaweiProductDetails extends ProductDetails {
  HuaweiProductDetails(Map<Object?, Object?> data)
      : productType = (data['type'] as num).toInt(),
        super(id: data['id'] as String, title: data['title'] as String,
          description: data['description'] as String, price: data['price'] as String,
          rawPrice: (data['microPrice'] as num).toDouble() / 1000000,
          currencyCode: data['currency'] as String);
  final int productType;
}

class HuaweiPurchaseDetails extends PurchaseDetails {
  HuaweiPurchaseDetails(Map<Object?, Object?> data, PurchaseStatus status)
      : handle = data['handle'] as String, productType = (data['type'] as num).toInt(),
        super(purchaseID: data['orderId'] as String, productID: data['productId'] as String,
          transactionDate: data['purchaseTime']?.toString(), status: status,
          verificationData: PurchaseVerificationData(localVerificationData: data['purchaseData'] as String,
            serverVerificationData: data['purchaseData'] as String, source: _source)) {
    pendingCompletePurchase = data['needsCompletion'] == true;
  }
  final String handle;
  final int productType;
}

/// Store results are receipts to verify; this class never grants app entitlements.
class InAppPurchaseOhosPlatform extends InAppPurchasePlatform {
  InAppPurchaseOhosPlatform() {
    _updates = StreamController<List<PurchaseDetails>>.broadcast(onListen: () {
      unawaited(_recover());
    });
  }
  late final StreamController<List<PurchaseDetails>> _updates;
  static void registerWith() => InAppPurchasePlatform.instance = InAppPurchaseOhosPlatform();
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _updates.stream;
  @override
  Future<bool> isAvailable() async => await _channel.invokeMethod<bool>('isAvailable') ?? false;
  @override
  Future<String> countryCode() async => ''; // The SDK does not expose the account's storefront country.
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async {
    try {
      final rows = await _channel.invokeListMethod<Object?>('queryProducts', identifiers.toList()) ?? [];
      final products = rows.map((value) => HuaweiProductDetails(Map<Object?, Object?>.from(value as Map))).toList();
      return ProductDetailsResponse(productDetails: products,
        notFoundIDs: identifiers.difference(products.map((p) => p.id).toSet()).toList());
    } on PlatformException catch (error) {
      return ProductDetailsResponse(productDetails: [], notFoundIDs: identifiers.toList(),
        error: IAPError(source: _source, code: error.code, message: error.message ?? 'Product query failed'));
    }
  }
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) => _buy(purchaseParam, consumable: false, autoConsume: false);
  @override
  Future<bool> buyConsumable({required PurchaseParam purchaseParam, bool autoConsume = true}) =>
      _buy(purchaseParam, consumable: true, autoConsume: autoConsume);
  Future<bool> _buy(PurchaseParam param, {required bool consumable, required bool autoConsume}) async {
    final product = param.productDetails;
    if (product is! HuaweiProductDetails || (product.productType == 0) != consumable) {
      throw ArgumentError('Use the queried Huawei product and matching purchase type');
    }
    final pending = PurchaseDetails(productID: product.id, verificationData:
      PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: _source),
      transactionDate: null, status: PurchaseStatus.pending);
    _updates.add([pending]);
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>('buy', {
        'productId': product.id, 'type': product.productType,
        if (param.applicationUserName != null) 'developerPayload': param.applicationUserName,
      });
      final purchase = HuaweiPurchaseDetails(data!, PurchaseStatus.purchased);
      // The signed receipt belongs to this exact transaction, never a shared "latest receipt".
      // Applications must verify it server-side before granting anything.
      if (consumable && autoConsume) await completePurchase(purchase);
      _updates.add([purchase]);
      return true;
    } on PlatformException catch (error) {
      pending.status = error.code == '1001860000' ? PurchaseStatus.canceled : PurchaseStatus.error;
      pending.error = IAPError(source: _source, code: error.code, message: error.message ?? 'Purchase failed');
      _updates.add([pending]);
      return false;
    }
  }
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (purchase is! HuaweiPurchaseDetails) throw ArgumentError('Purchase does not belong to Huawei');
    if (!purchase.pendingCompletePurchase) return;
    await _channel.invokeMethod<void>('finish', {'handle': purchase.handle});
    purchase.pendingCompletePurchase = false;
  }
  Future<void> _recover() async {
    try {
      await _queryPurchases(restored: false);
    } catch (error, stack) {
      _updates.addError(error, stack);
    }
  }
  Future<void> _queryPurchases({required bool restored}) async {
    final rows = await _channel.invokeListMethod<Object?>('purchases', {'restored': restored}) ?? [];
    final purchases = rows.map((row) => HuaweiPurchaseDetails(Map<Object?, Object?>.from(row as Map),
      restored ? PurchaseStatus.restored : PurchaseStatus.purchased)).toList();
    if (purchases.isNotEmpty) _updates.add(purchases);
  }
  @override
  Future<void> restorePurchases({String? applicationUserName}) => _queryPurchases(restored: true);
}
