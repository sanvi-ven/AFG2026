import 'package:anchor/models/invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice numbers swap the estimate EST prefix for INV', () {
    expect(Invoice.numberFromEstimate('EST-0042'), 'INV-0042');
    expect(Invoice.numberFromEstimate('EST-0042-2'), 'INV-0042-2');
    expect(Invoice.numberFromEstimate('INV-0042'), 'INV-0042');
    expect(Invoice.numberFromEstimate('Custom-7'), 'Custom-7');
  });

  test('invoices stored with an EST number display as INV', () {
    final invoice = Invoice.fromMap({'id': 'i1', 'invoiceNumber': 'EST-0042'});
    expect(invoice.invoiceNumber, 'INV-0042');
  });
}
