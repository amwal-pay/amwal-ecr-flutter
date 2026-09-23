import 'dart:async';

import '../model/ecr_errors.dart';
import '../model/ecr_failure.dart';
import '../model/ecr_inquiry.dart';
import '../model/ecr_reachability.dart';
import '../model/ecr_receipt.dart';
import '../model/ecr_result.dart';
import '../model/ecr_transaction_type.dart';
import '../model/ecr_transport.dart';
import '../platform/amwal_ecr_platform.dart';
import '../platform/ecr_request.dart';
import 'lan_ecr_client.dart';
import 'web_service/web_service_ecr_client.dart';

/// Pure-Dart [AmwalEcrPlatform] for desktop (Windows) — LAN TCP + Web Service.
///
/// Holds the same one-completion / no-retry / cancel semantics as
/// `MethodChannelAmwalEcr`. USB cable and Bluetooth are unsupported here.
base class DartIoAmwalEcrPlatform extends AmwalEcrPlatform {
  /// Creates the Dart IO host.
  DartIoAmwalEcrPlatform();

  final Map<String, _OperationHandle> _inFlight = <String, _OperationHandle>{};

  /// How many operations are still waiting. Visible for tests.
  int get inFlightCount => _inFlight.length;

  @override
  Future<bool> isReachable(EcrRequest request) async {
    final EcrReachability probe = await probeReachability(request);
    return probe.reachable;
  }

  @override
  Future<EcrReachability> probeReachability(EcrRequest request) async {
    if (request.transport != EcrTransport.wifi) {
      return EcrReachability(
        reachable: false,
        host: request.host,
        port: request.transport.isIpTransport ? request.config.port : 0,
        error: request.transport == EcrTransport.webService
            ? null
            : 'Transport ${request.transport.name} has no LAN probe',
        endpoint: request.transport == EcrTransport.webService
            ? 'webService'
            : (request.host.isEmpty
                ? request.transport.name
                : '${request.host}:${request.config.port}'),
      );
    }

    final LanEcrClient client = LanEcrClient(
      host: request.host,
      serialNumber: request.serialNumber,
      config: request.config,
    );
    try {
      final ({bool reachable, String? error}) probe = await client.probe();
      return EcrReachability(
        reachable: probe.reachable,
        host: request.host,
        port: request.config.port,
        error: probe.error,
      );
    } on Object catch (error) {
      return EcrReachability(
        reachable: false,
        host: request.host,
        port: request.config.port,
        error: error.toString(),
      );
    }
  }

  @override
  Future<EcrResult> sale(EcrRequest request) => _invokeResult(
        request,
        (LanEcrClient lan, WebServiceEcrClient? web) {
          if (web != null) {
            return web.sale(
              amount: request.amount!,
              merchantReference: request.merchantReference,
            );
          }
          return lan.run(
            type: EcrTransactionType.sale,
            amount: request.amount,
            merchantReference: request.merchantReference,
          );
        },
      );

  @override
  Future<EcrResult> voidTransaction(EcrRequest request) => _invokeResult(
        request,
        (LanEcrClient lan, WebServiceEcrClient? web) {
          if (web != null) {
            return web.voidTransaction(
              receiptNumber: request.receiptNumber,
              merchantReference: request.merchantReference,
            );
          }
          return lan.run(
            type: EcrTransactionType.voidTransaction,
            originalStan: request.receiptNumber,
            originalTerminalId: request.originalTerminalId,
            merchantReference: request.merchantReference,
          );
        },
      );

  @override
  Future<EcrResult> refund(EcrRequest request) => _invokeResult(
        request,
        (LanEcrClient lan, WebServiceEcrClient? web) {
          if (web != null) {
            return web.refund(
              amount: request.amount!,
              receiptNumber: request.receiptNumber,
              transactionDate: request.transactionDate,
              merchantReference: request.merchantReference,
            );
          }
          return lan.run(
            type: EcrTransactionType.refund,
            amount: request.amount,
            originalStan: request.receiptNumber,
            originalTerminalId: request.originalTerminalId,
            originalDate: request.transactionDate,
            merchantReference: request.merchantReference,
          );
        },
      );

  @override
  Future<EcrInquiry> inquire(EcrRequest request) => _invokeInquiry(
        request,
        (LanEcrClient lan, WebServiceEcrClient? web) {
          if (web != null) {
            return web.inquire(
              receiptNumber: request.receiptNumber,
              transactionDate: request.transactionDate,
              merchantReference: request.merchantReference,
            );
          }
          return lan.inquire(
            receiptNumber: request.receiptNumber,
            transactionDate: request.transactionDate,
            originalTerminalId: request.originalTerminalId,
            merchantReference: request.merchantReference,
          );
        },
      );

  @override
  Future<EcrInquiry> inquireByReference(EcrRequest request) => _invokeInquiry(
        request,
        (LanEcrClient lan, WebServiceEcrClient? web) {
          if (web != null) {
            return web.inquireByReference(
              originalReference: request.originalMerchantReference,
              transactionDate: request.transactionDate,
              merchantReference: request.merchantReference,
            );
          }
          return lan.inquireByReference(
            originalReference: request.originalMerchantReference,
            transactionDate: request.transactionDate,
            originalTerminalId: request.originalTerminalId,
            merchantReference: request.merchantReference,
          );
        },
      );

  @override
  Future<EcrReceipt> receipt(EcrRequest request) {
    if (request.transport != EcrTransport.wifi) {
      return Future<EcrReceipt>.value(
        EcrReceiptFailed(
          merchantReference: '',
          failure: EcrUnsupported(
            'Receipt is not available over ${request.transport.name}',
          ),
        ),
      );
    }
    return _invoke<EcrReceipt>(
      request: request,
      run: (LanEcrClient lan, WebServiceEcrClient? web) => lan.receipt(
        receiptNumber: request.receiptNumber,
        transactionDate: request.transactionDate,
        originalTerminalId: request.originalTerminalId,
        merchantReference: request.merchantReference,
      ),
      onFailure: (EcrFailure failure) =>
          EcrReceiptFailed(merchantReference: '', failure: failure),
    );
  }

  @override
  Future<bool> cancel(String operationId) async {
    final _OperationHandle? handle = _inFlight[operationId];
    if (handle == null) return false;

    handle.cancelRequested = true;
    handle.abort();
    handle.settleCancelled();
    return true;
  }

  Future<EcrResult> _invokeResult(
    EcrRequest request,
    Future<EcrResult> Function(LanEcrClient lan, WebServiceEcrClient? web) run,
  ) =>
      _invoke<EcrResult>(
        request: request,
        run: run,
        onFailure: (EcrFailure failure) =>
            EcrFailed(merchantReference: '', failure: failure),
      );

  Future<EcrInquiry> _invokeInquiry(
    EcrRequest request,
    Future<EcrInquiry> Function(LanEcrClient lan, WebServiceEcrClient? web) run,
  ) =>
      _invoke<EcrInquiry>(
        request: request,
        run: run,
        onFailure: (EcrFailure failure) =>
            EcrInquiryFailed(merchantReference: '', failure: failure),
      );

  Future<T> _invoke<T extends Object>({
    required EcrRequest request,
    required Future<T> Function(LanEcrClient lan, WebServiceEcrClient? web) run,
    required T Function(EcrFailure failure) onFailure,
  }) {
    if (_inFlight.containsKey(request.operationId)) {
      throw EcrArgumentError(
        'Operation "${request.operationId}" is already in flight. '
        'Each call needs its own operation id.',
      );
    }

    final EcrFailure? unsupported = _unsupported(request.transport);
    if (unsupported != null) {
      return Future<T>.value(onFailure(unsupported));
    }

    final _Clients clients = _openClients(request);
    final _OperationHandle handle = _OperationHandle(
      abort: clients.abort,
      settleCancelled: () {},
    );

    final Completer<T> completer = Completer<T>();
    handle.settleCancelled = () {
      if (completer.isCompleted) return;
      completer.complete(onFailure(const EcrCancelled()));
    };

    _inFlight[request.operationId] = handle;

    unawaited(
      () async {
        try {
          if (handle.cancelRequested) {
            handle.settleCancelled();
            return;
          }
          final T value = await run(clients.lan, clients.web);
          if (!completer.isCompleted) {
            completer.complete(value);
          }
        } on EcrArgumentError catch (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        } on Object catch (error) {
          if (!completer.isCompleted) {
            completer.complete(
              onFailure(
                EcrMalformed(
                  'The Dart ECR host failed unexpectedly ($error). '
                  'The transaction may still have happened — inquire '
                  'before retrying.',
                ),
              ),
            );
          }
        } finally {
          _inFlight.remove(request.operationId);
          clients.abort();
        }
      }(),
    );

    return completer.future;
  }

  EcrFailure? _unsupported(EcrTransport transport) {
    switch (transport) {
      case EcrTransport.wifi:
      case EcrTransport.webService:
        return null;
      case EcrTransport.usbCable:
        return const EcrUnsupported(
          'USB cable ECR is not supported on Windows. Use Wi‑Fi or '
          'Web Service.',
        );
      case EcrTransport.appToApp:
        return const EcrUnsupported(
          'App to app ECR is supported on Android only. On Windows use '
          'Wi‑Fi or Web Service.',
        );
      case EcrTransport.bluetooth:
        return const EcrUnsupported(
          'Bluetooth ECR is not supported by this plugin.',
        );
    }
  }

  _Clients _openClients(EcrRequest request) {
    final LanEcrClient lan = LanEcrClient(
      host: request.host.isEmpty ? '127.0.0.1' : request.host,
      serialNumber: request.serialNumber,
      config: request.config,
    );
    if (request.transport == EcrTransport.webService) {
      final WebServiceEcrClient web = WebServiceEcrClient(
        terminalSerial: request.serialNumber,
        config: request.config,
      );
      return _Clients(
        lan: lan,
        web: web,
        abort: () {
          lan.abort();
          web.abort();
        },
      );
    }
    return _Clients(lan: lan, web: null, abort: lan.abort);
  }
}

final class _Clients {
  const _Clients({
    required this.lan,
    required this.web,
    required this.abort,
  });

  final LanEcrClient lan;
  final WebServiceEcrClient? web;
  final void Function() abort;
}

final class _OperationHandle {
  _OperationHandle({
    required this.abort,
    required this.settleCancelled,
  });

  final void Function() abort;
  void Function() settleCancelled;
  bool cancelRequested = false;
}
