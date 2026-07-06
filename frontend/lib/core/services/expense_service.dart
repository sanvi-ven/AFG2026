import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/expense.dart';

/// manages business expense entries (materials, gas, etc.) in firestore
class ExpenseService {
  ExpenseService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('expenses');

  /// stream all expenses, most recent first
  static Stream<List<Expense>> watchAllExpenses() {
    return _collection.snapshots().map((snapshot) {
      final expenses = snapshot.docs.map((doc) => Expense.fromMap({...doc.data(), 'id': doc.id})).toList();
      expenses.sort((a, b) => b.date.compareTo(a.date));
      return expenses;
    });
  }

  static Future<void> createExpense({
    required String description,
    required String category,
    required double amount,
    required DateTime date,
  }) async {
    final doc = _collection.doc();
    final expense = Expense(
      id: doc.id,
      description: description.trim(),
      category: category,
      amount: amount,
      date: date,
      createdAt: DateTime.now(),
    );
    await doc.set(expense.toMap());
  }

  static Future<void> deleteExpense(String id) async {
    await _collection.doc(id.trim()).delete();
  }
}
