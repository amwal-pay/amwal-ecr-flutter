import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:amwal_ecr/amwal_ecr_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contract, frozen.
///
/// Every string here is duplicated in `EcrChannelContract.kt` and
/// `EcrChannelContract.swift`, and there is no compiler on earth that will tell
/// you when one of the three drifts. So the literals are written out again, by
/// hand, in this file: a rename that reaches the Dart constant but not the
/// native hosts fails here, loudly, instead of turning into a call that is
/// simply never answered at a till.
///
/// **Changing a value in this file is not how you rename something.** Rename it
/// in all three contract files and in this test, in one commit, and treat it as
/// a breaking change — an app shipping the old Dart against the new host, or
/// the reverse, stops working.
void main() {
  group('method names', () {
    test('are exactly these eight, spelled exactly this way', () {
      expect(EcrMethods.isReachable, 'isReachable');
      expect(EcrMethods.sale, 'sale');
      expect(EcrMethods.voidTransaction, 'void');
      expect(EcrMethods.refund, 'refund');
      expect(EcrMethods.inquire, 'inquire');
      expect(EcrMethods.inquireByReference, 'inquireByReference');
      expect(EcrMethods.receipt, 'receipt');
      expect(EcrMethods.cancel, 'cancel');
    });

    test('the published list covers them and nothing else', () {
      expect(EcrMethods.all, <String>[
        'isReachable',
        'sale',
        'void',
        'refund',
        'inquire',
        'inquireByReference',
        'receipt',
        'cancel',
      ]);
    });

    test('no two methods share a name', () {
      expect(EcrMethods.all.toSet().length, EcrMethods.all.length);
    });
  });

  group('argument keys', () {
    test('are spelled exactly this way', () {
      expect(EcrArgs.operationId, 'operationId');
      expect(EcrArgs.host, 'host');
      expect(EcrArgs.serialNumber, 'serialNumber');
      expect(EcrArgs.transport, 'transport');
      expect(EcrArgs.config, 'config');
      expect(EcrArgs.amount, 'amount');
      expect(EcrArgs.receiptNumber, 'receiptNumber');
      expect(EcrArgs.transactionDate, 'transactionDate');
      expect(EcrArgs.originalTerminalId, 'originalTerminalId');
      expect(EcrArgs.merchantReferenceId, 'merchantReferenceId');
      expect(EcrArgs.originalMerchantReference, 'originalMerchantReference');
    });

    test('the published list covers them and nothing else', () {
      expect(EcrArgs.all, <String>[
        'operationId',
        'host',
        'serialNumber',
        'transport',
        'config',
        'amount',
        'receiptNumber',
        'transactionDate',
        'originalTerminalId',
        'merchantReferenceId',
        'originalMerchantReference',
      ]);
    });
  });

  group('config keys', () {
    test('are spelled exactly this way, and say their unit', () {
      expect(EcrConfigKeys.ecrId, 'ecrId');
      expect(EcrConfigKeys.currencyCode, 'currencyCode');
      expect(EcrConfigKeys.minorUnitDigits, 'minorUnitDigits');
      expect(EcrConfigKeys.port, 'port');
      // The Ms suffix is load-bearing: Kotlin's Duration and Swift's
      // TimeInterval disagree about units, and a key that does not name one
      // invites each host to guess.
      expect(EcrConfigKeys.connectTimeoutMs, 'connectTimeoutMs');
      expect(EcrConfigKeys.responseTimeoutMs, 'responseTimeoutMs');
      expect(EcrConfigKeys.probeTimeoutMs, 'probeTimeoutMs');
      expect(EcrConfigKeys.secureHashKey, 'secureHashKey');
      expect(EcrConfigKeys.autoInquireOnFailure, 'autoInquireOnFailure');
    });

    test('the published list covers them and nothing else', () {
      expect(EcrConfigKeys.all, <String>[
        'ecrId',
        'currencyCode',
        'minorUnitDigits',
        'port',
        'connectTimeoutMs',
        'responseTimeoutMs',
        'probeTimeoutMs',
        'secureHashKey',
        'autoInquireOnFailure',
      ]);
    });
  });

  group('result keys', () {
    test('are spelled exactly this way', () {
      expect(EcrResultKeys.outcome, 'outcome');
      expect(EcrResultKeys.merchantReferenceId, 'merchantReferenceId');
      expect(EcrResultKeys.amount, 'amount');
      expect(EcrResultKeys.responseCode, 'responseCode');
      expect(EcrResultKeys.rrn, 'rrn');
      expect(EcrResultKeys.authCode, 'authCode');
      expect(EcrResultKeys.maskedPan, 'maskedPan');
      expect(EcrResultKeys.partialApproval, 'partialApproval');
      expect(EcrResultKeys.requestedAmount, 'requestedAmount');
      expect(EcrResultKeys.raw, 'raw');
      expect(EcrResultKeys.failure, 'failure');
      expect(EcrResultKeys.transaction, 'transaction');
      expect(EcrResultKeys.url, 'url');
      expect(EcrResultKeys.nextStep, 'nextStep');
      expect(EcrResultKeys.recovered, 'recovered');
    });

    test('the decline reason travels under "reason", not "responseMessage"', () {
      // The wire calls it responseMessage; the channel calls it reason, because
      // an inquiry and a receipt carry the same field for a different sort of
      // refusal. Both hosts must agree, hence the assertion.
      expect(EcrResultKeys.responseMessage, 'reason');
    });
  });

  group('outcomes', () {
    test('are spelled exactly this way', () {
      expect(EcrOutcomes.approved, 'approved');
      expect(EcrOutcomes.declined, 'declined');
      expect(EcrOutcomes.failed, 'failed');
      expect(EcrOutcomes.found, 'found');
      expect(EcrOutcomes.notFound, 'notFound');
      expect(EcrOutcomes.ready, 'ready');
      expect(EcrOutcomes.unavailable, 'unavailable');
    });

    test('no two outcomes share a name', () {
      expect(EcrOutcomes.all.toSet().length, EcrOutcomes.all.length);
    });
  });

  group('failure kinds', () {
    test('the five native ones are spelled exactly this way', () {
      expect(EcrFailureKinds.unreachable, 'unreachable');
      expect(EcrFailureKinds.timeout, 'timeout');
      expect(EcrFailureKinds.malformed, 'malformed');
      expect(EcrFailureKinds.connectionLost, 'connectionLost');
      expect(EcrFailureKinds.unauthenticated, 'unauthenticated');
    });

    test('the two wrapper-level ones are spelled exactly this way', () {
      expect(EcrFailureKinds.cancelled, 'cancelled');
      expect(EcrFailureKinds.unsupported, 'unsupported');
    });

    test('the published list covers them and nothing else', () {
      expect(EcrFailureKinds.all, <String>[
        'unreachable',
        'timeout',
        'malformed',
        'connectionLost',
        'unauthenticated',
        'cancelled',
        'unsupported',
      ]);
    });

    test('failure sub-map keys are spelled exactly this way', () {
      expect(EcrFailureKeys.kind, 'kind');
      expect(EcrFailureKeys.message, 'message');
    });
  });

  group('transaction keys', () {
    test('are spelled exactly this way', () {
      expect(EcrTransactionKeys.transactionId, 'transactionId');
      expect(EcrTransactionKeys.stan, 'stan');
      expect(EcrTransactionKeys.type, 'type');
      expect(EcrTransactionKeys.status, 'status');
      expect(EcrTransactionKeys.amount, 'amount');
      expect(EcrTransactionKeys.totalAmount, 'totalAmount');
      expect(EcrTransactionKeys.currency, 'currency');
      expect(EcrTransactionKeys.transactionTime, 'transactionTime');
      expect(EcrTransactionKeys.maskedPan, 'maskedPan');
      expect(EcrTransactionKeys.cardHolderName, 'cardHolderName');
      expect(EcrTransactionKeys.rrn, 'rrn');
      expect(EcrTransactionKeys.authCode, 'authCode');
      expect(EcrTransactionKeys.batchId, 'batchId');
      expect(EcrTransactionKeys.terminalId, 'terminalId');
      expect(EcrTransactionKeys.isRefunded, 'isRefunded');
      expect(EcrTransactionKeys.canVoid, 'canVoid');
      expect(EcrTransactionKeys.canRefund, 'canRefund');
    });

    test('all seventeen fields the backend records are carried', () {
      expect(EcrTransactionKeys.all, hasLength(17));
    });
  });

  group('next steps', () {
    test('are the protocol\'s own spelling, shared by all three sides', () {
      // Not re-spelled for the channel: the terminal, both native SDKs and this
      // package say the same word, so there is one name to keep in step rather
      // than a translation on each hop.
      expect(EcrNextSteps.none, 'NONE');
      expect(
        EcrNextSteps.inquireByMerchantReference,
        'INQUIRE_BY_MERCHANT_REFERENCE',
      );
      expect(EcrNextStep.none.channelName, EcrNextSteps.none);
      expect(
        EcrNextStep.inquireByMerchantReference.channelName,
        EcrNextSteps.inquireByMerchantReference,
      );
    });

    test('a step this version has not heard of reads as none, not as a guess', () {
      // A till must not act on an instruction it does not understand; the
      // outcome it is attached to already says whether money may have moved.
      expect(
        EcrNextStep.parse('INQUIRE_BY_MERCHANT_REFERENCE'),
        EcrNextStep.inquireByMerchantReference,
      );
      expect(EcrNextStep.parse('PHONE_THE_ACQUIRER'), EcrNextStep.none);
      expect(EcrNextStep.parse(null), EcrNextStep.none);
      expect(EcrNextStep.parse(''), EcrNextStep.none);
    });
  });

  group('error codes', () {
    test('are spelled exactly this way', () {
      expect(EcrErrorCodes.invalidArgument, 'ecr_invalid_argument');
      expect(EcrErrorCodes.internal, 'ecr_internal');
    });
  });

  test('the channel name is exactly this', () {
    expect(kEcrMethodChannel, 'com.amwalpay.ecr/methods');
  });

  group('transports', () {
    test('are named on the channel exactly as the TMS profile numbers them', () {
      expect(EcrTransport.ethernet.channelName, 'ethernet');
      expect(EcrTransport.wifi.channelName, 'wifi');
      expect(EcrTransport.bluetooth.channelName, 'bluetooth');
      expect(EcrTransport.webService.channelName, 'webService');

      expect(EcrTransport.ethernet.wireValue, 1);
      expect(EcrTransport.wifi.wireValue, 2);
      expect(EcrTransport.bluetooth.wireValue, 3);
      expect(EcrTransport.webService.wireValue, 4);
    });

    test('only the IP transports have a listener to reach', () {
      expect(EcrTransport.ethernet.isIpTransport, isTrue);
      expect(EcrTransport.wifi.isIpTransport, isTrue);
      expect(EcrTransport.bluetooth.isIpTransport, isFalse);
      expect(EcrTransport.webService.isIpTransport, isFalse);
    });

    test('an ecrMode this version has not heard of reads as null, not as a guess', () {
      expect(EcrTransport.fromWireValue(1), EcrTransport.ethernet);
      expect(EcrTransport.fromWireValue(9), isNull);
      expect(EcrTransport.fromChannelName('wifi'), EcrTransport.wifi);
      expect(EcrTransport.fromChannelName('carrier-pigeon'), isNull);
    });
  });

  group('message types on the wire', () {
    test('are what the protocol document says', () {
      expect(EcrTransactionType.sale.messageType, 'SALE');
      expect(EcrTransactionType.voidTransaction.messageType, 'VOID');
      expect(EcrTransactionType.refund.messageType, 'REFUND');
      expect(EcrTransactionType.inquiry.messageType, 'INQUIRY');
      expect(EcrTransactionType.receipt.messageType, 'RECEIPT');
    });

    test('each type declares what the caller has to supply', () {
      expect(EcrTransactionType.sale.requiresAmount, isTrue);
      expect(EcrTransactionType.sale.requiresOriginalStan, isFalse);

      // A void takes the original's amount; only the terminal knows it.
      expect(EcrTransactionType.voidTransaction.requiresAmount, isFalse);
      expect(EcrTransactionType.voidTransaction.requiresOriginalStan, isTrue);
      expect(EcrTransactionType.voidTransaction.requiresOriginalDate, isFalse);

      expect(EcrTransactionType.refund.requiresAmount, isTrue);
      expect(EcrTransactionType.refund.requiresOriginalStan, isTrue);
      expect(EcrTransactionType.refund.requiresOriginalDate, isTrue);
    });

    test('only sale, void and refund move money', () {
      expect(EcrTransactionType.sale.movesMoney, isTrue);
      expect(EcrTransactionType.voidTransaction.movesMoney, isTrue);
      expect(EcrTransactionType.refund.movesMoney, isTrue);
      expect(EcrTransactionType.inquiry.movesMoney, isFalse);
      expect(EcrTransactionType.receipt.movesMoney, isFalse);
    });

    test('receipt is deliberately absent from the operator menu', () {
      expect(EcrTransactionType.menuOptions, <EcrTransactionType>[
        EcrTransactionType.sale,
        EcrTransactionType.voidTransaction,
        EcrTransactionType.refund,
        EcrTransactionType.inquiry,
      ]);
    });
  });
}
