import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class RazorpayService {
  late Razorpay _razorpay;

  void init() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (kDebugMode) debugPrint('Payment success');
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (kDebugMode) debugPrint('Payment error');
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (kDebugMode) debugPrint('External wallet selected');
  }

  void openCheckout({
    required String keyId,
    required double amount,
    required String orderId,
    required String name,
    required String description,
    Map<String, String>? prefill,
    required Function(PaymentSuccessResponse) onSuccess,
    required Function(PaymentFailureResponse) onError,
  }) {
    // Update handlers
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
      onSuccess(response);
    });
    
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      onError(response);
    });

    var options = {
      'key': keyId,
      'amount': (amount * 100).toInt(), // Convert to paise
      'name': name,
      'description': description,
      'order_id': orderId,
      'prefill': prefill ?? {},
      'theme': {'color': '#6366f1'},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      onError(PaymentFailureResponse(
        -1,
        'Failed to open payment gateway. Please try again.',
        null,
      ));
    }
  }

  void dispose() {
    _razorpay.clear();
  }
}
