import 'package:amwal_ecr/amwal_ecr.dart';

/// Bilingual receipt content shaped like the simulator sample.
///
/// [fromOperation] fills payment fields from [EcrApproved]; merchant branding
/// / item lines use defaults when the ECR envelope has no cart.
class ReceiptLayout {
  const ReceiptLayout({
    required this.businessName,
    required this.tagline,
    required this.mobileLine,
    required this.crLine,
    required this.taxLine,
    required this.orderBox,
    required this.meta,
    required this.orderType,
    required this.customerPhoneLabel,
    required this.customerPhone,
    required this.itemsHeader,
    required this.items,
    required this.totals,
    required this.grandTotalLabel,
    required this.grandTotalValue,
    required this.footerSocial,
    required this.footerThanks,
  });

  final String businessName;
  final String tagline;
  final String mobileLine;
  final String crLine;
  final String taxLine;
  final String orderBox;
  final List<(String, String)> meta;
  final String orderType;
  final String customerPhoneLabel;
  final String? customerPhone;
  final (String, String, String) itemsHeader;
  final List<(String, String, String)> items;
  final List<(String, String)> totals;
  final String grandTotalLabel;
  final String grandTotalValue;
  final String footerSocial;
  final String footerThanks;

  /// Exact structure/values of the attached Dox sample (layout smoke test).
  factory ReceiptLayout.sampleAttached() => const ReceiptLayout(
        businessName: 'Dox - DoxeE',
        tagline:
            'Welcome to DOX, where classic Arabic cuisine meets modern taste. '
            'Enjoy flavorful dishes inspired by Middle Eastern traditions',
        mobileLine: 'Mobile - رقم الهاتف: 963988535034',
        crLine: 'CR - رقم السجل: 12121212',
        taxLine: 'TAX - رقم الضريبي: 1313131313',
        orderBox: 'الطلب: Order - 1#',
        meta: <(String, String)>[
          ('Print Date - تاريخ الطباعة', '2026/09/28 - 10:08 AM'),
          ('Created by - انشأ من قبل', 'Dox For Test'),
          ('Order From - الطلب من', 'POS - نقطة البيع'),
          ('Paid Status - حالة الدفع', 'Paid - مدفوع'),
          ('Invoice - رقم الفاتورة', '1-1902#'),
          ('Order Date - تاريخ الطلب', '2026/09/28'),
          ('Order Time - وقت الطلب', '9:59 AM'),
        ],
        orderType: 'خارج. خارج - Parcel. Parcel',
        customerPhoneLabel: 'User Phone - رقم الزبون',
        customerPhone: '',
        itemsHeader: ('Qty - العدد', 'Name - العنصر', 'Price - السعر'),
        items: <(String, String, String)>[
          ('1', 'Chicken Slider - سلايدر دجاج', '3.300'),
          ('2', 'Shredded Slider - سلايدر مبشور', '7.800'),
        ],
        totals: <(String, String)>[
          ('Subtotal - المجموع الفرعي', 'OMR 11.100'),
          ('Discount - الخصم', 'OMR 0.000'),
          ('Vat - الضريبة (7%)', 'OMR 0.777'),
          ('Other VAT', 'OMR 1.665'),
        ],
        grandTotalLabel: 'Total - الإجمالي',
        grandTotalValue: 'OMR 13.542',
        footerSocial: 'Follow us - متابعة عبر www.instagram.com/fascano_om',
        footerThanks: 'Thank you - شكرا لكم',
      );

  /// Maps an ECR approved operation into the sample layout slots.
  factory ReceiptLayout.fromOperation(
    EcrApproved result,
    EcrTransactionType type, {
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final String paid =
        result.partialApproval ? 'Partial - جزئي' : 'Paid - مدفوع';
    final String amount = result.amount.isEmpty ? '0.000' : result.amount;
    final String currencyAmount = 'OMR $amount';
    final String ref =
        result.merchantReference.isEmpty ? '—' : result.merchantReference;

    final List<(String, String)> meta = <(String, String)>[
      ('Print Date - تاريخ الطباعة', _dateTime(at)),
      ('Created by - انشأ من قبل', 'ECR Till'),
      ('Order From - الطلب من', 'POS - نقطة البيع'),
      ('Paid Status - حالة الدفع', paid),
      ('Invoice - رقم الفاتورة', ref),
      ('Order Date - تاريخ الطلب', _dateOnly(at)),
      ('Order Time - وقت الطلب', _timeOnly(at)),
      if (type != EcrTransactionType.voidTransaction &&
          result.authCode.isNotEmpty)
        ('Auth - رمز التفويض', result.authCode),
      if (result.rrn.isNotEmpty) ('RRN - رقم المرجع', result.rrn),
      if (result.maskedPan.isNotEmpty) ('Card - البطاقة', result.maskedPan),
      if (result.responseCode.isNotEmpty)
        ('Code - رمز الاستجابة', result.responseCode),
    ];

    final String itemName = '${type.displayName} - ${type.messageType}';
    final String itemPrice =
        result.partialApproval && result.requestedAmount.isNotEmpty
            ? '$amount (of ${result.requestedAmount})'
            : amount;

    return ReceiptLayout(
      businessName: 'Amwal Pay',
      tagline: 'Payment receipt - إيصال الدفع',
      mobileLine: '',
      crLine: '',
      taxLine: '',
      orderBox: 'الطلب: Order - $ref',
      meta: meta,
      orderType: type.displayName,
      customerPhoneLabel: 'User Phone - رقم الزبون',
      customerPhone: '',
      itemsHeader: ('Qty - العدد', 'Name - العنصر', 'Price - السعر'),
      items: <(String, String, String)>[('1', itemName, itemPrice)],
      totals: <(String, String)>[
        ('Subtotal - المجموع الفرعي', currencyAmount),
        ('Discount - الخصم', 'OMR 0.000'),
        ('Vat - الضريبة', 'OMR 0.000'),
      ],
      grandTotalLabel: 'Total - الإجمالي',
      grandTotalValue: currencyAmount,
      footerSocial: 'Amwal Pay - أموال باي',
      footerThanks: 'Thank you - شكرا لكم',
    );
  }

  /// `yyyy/MM/dd - h:mm a`
  static String _dateTime(DateTime at) => '${_dateOnly(at)} - ${_timeOnly(at)}';

  /// `yyyy/MM/dd`
  static String _dateOnly(DateTime at) {
    final String y = at.year.toString().padLeft(4, '0');
    final String m = at.month.toString().padLeft(2, '0');
    final String d = at.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  /// `h:mm a` (12-hour, no leading zero on the hour).
  static String _timeOnly(DateTime at) {
    final int hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final String minute = at.minute.toString().padLeft(2, '0');
    final String amPm = at.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $amPm';
  }
}
