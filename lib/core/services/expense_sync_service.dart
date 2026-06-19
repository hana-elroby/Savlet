import '../../features/categories/category_data_store.dart';
import '../../features/home/bloc/analytics_bloc.dart';
import '../../features/home/bloc/expense_bloc.dart';
import '../../features/home/bloc/expense_event.dart';
import '../../features/home/bloc/expense_state.dart';
import '../../features/transactions/bloc/transaction_bloc.dart';
import '../../features/transactions/bloc/transaction_event.dart';
import '../../features/transactions/models/transaction_model.dart';
import '../models/expense.dart';
import 'auth_api_service.dart';
import 'transaction_api_service.dart';
import 'transaction_local_store.dart';

/// Keeps ExpenseBloc, TransactionBloc, CategoryDataStore, and Analytics in sync.
class ExpenseSyncService {
  ExpenseSyncService._();
  static final ExpenseSyncService instance = ExpenseSyncService._();

  ExpenseBloc? _expenseBloc;
  TransactionBloc? _transactionBloc;

  void registerExpenseBloc(ExpenseBloc bloc) => _expenseBloc = bloc;
  void registerTransactionBloc(TransactionBloc bloc) => _transactionBloc = bloc;

  static bool isBackendId(String id) =>
      RegExp(r'^[a-f0-9]{24}$').hasMatch(id);

  static String fingerprint({
    required String title,
    required double amount,
    required DateTime date,
  }) {
    final day = '${date.year}-${date.month}-${date.day}';
    return '${title.trim().toLowerCase()}|${amount.toStringAsFixed(2)}|$day';
  }

  /// Delete one expense/transaction everywhere (UI + local cache + backend).
  Future<void> deleteEverywhere(String id) async {
    final expenses = _currentExpenses();
    final transactions = _currentTransactions();

    Expense? targetExpense;
    for (final e in expenses) {
      if (e.id == id) {
        targetExpense = e;
        break;
      }
    }

    TransactionModel? targetTx;
    for (final t in transactions) {
      if (t.id == id) {
        targetTx = t;
        break;
      }
    }

    if (targetExpense == null && targetTx != null) {
      final fp = fingerprint(
        title: targetTx.title,
        amount: targetTx.amount,
        date: targetTx.date,
      );
      for (final e in expenses) {
        if (fingerprint(title: e.title, amount: e.amount, date: e.date) ==
            fp) {
          targetExpense = e;
          break;
        }
      }
    }

    if (targetExpense != null && targetTx == null) {
      final fp = fingerprint(
        title: targetExpense.title,
        amount: targetExpense.amount,
        date: targetExpense.date,
      );
      for (final t in transactions) {
        if (fingerprint(title: t.title, amount: t.amount, date: t.date) ==
            fp) {
          targetTx = t;
          break;
        }
      }
    }

    final idsToRemove = <String>{id};
    if (targetExpense != null) idsToRemove.add(targetExpense.id);
    if (targetTx != null) idsToRemove.add(targetTx.id);

    final fpToRemove = targetExpense != null
        ? fingerprint(
            title: targetExpense.title,
            amount: targetExpense.amount,
            date: targetExpense.date,
          )
        : (targetTx != null
            ? fingerprint(
                title: targetTx.title,
                amount: targetTx.amount,
                date: targetTx.date,
              )
            : null);

    bool shouldRemoveExpense(Expense e) {
      if (idsToRemove.contains(e.id)) return true;
      if (fpToRemove == null) return false;
      return fingerprint(title: e.title, amount: e.amount, date: e.date) ==
          fpToRemove;
    }

    bool shouldRemoveTransaction(TransactionModel t) {
      if (idsToRemove.contains(t.id)) return true;
      if (fpToRemove == null) return false;
      return fingerprint(title: t.title, amount: t.amount, date: t.date) ==
          fpToRemove;
    }

    final remainingExpenses =
        expenses.where((e) => !shouldRemoveExpense(e)).toList();
    final remainingTransactions =
        transactions.where((t) => !shouldRemoveTransaction(t)).toList();

    String? backendId;
    for (final candidate in [id, targetTx?.id, targetExpense?.id]) {
      if (candidate != null && isBackendId(candidate)) {
        backendId = candidate;
        break;
      }
    }

    await _applyLocalState(remainingExpenses, remainingTransactions);

    if (backendId != null &&
        await AuthApiService.instance.isAuthenticated()) {
      try {
        final result =
            await TransactionApiService.instance.deleteTransaction(backendId);
        if (result.isSuccess) {
          print('✅ Unified delete synced to backend: $backendId');
        } else {
          print('⚠️ Backend delete failed: ${result.message}');
        }
      } catch (e) {
        print('⚠️ Backend delete error: $e');
      }
    }

    await AnalyticsBloc.instance?.refresh();
  }

  Future<void> applyTransactionList(
    List<TransactionModel> transactions,
  ) async {
    await TransactionLocalStore.save(transactions);
    _transactionBloc?.add(ReplaceTransactionsLocally(transactions));
  }

  List<Expense> _currentExpenses() {
    final state = _expenseBloc?.state;
    if (state is ExpenseLoaded) return List<Expense>.from(state.expenses);
    return [];
  }

  List<TransactionModel> _currentTransactions() {
    return List<TransactionModel>.from(
      _transactionBloc?.state.transactions ?? const [],
    );
  }

  Future<void> _applyLocalState(
    List<Expense> expenses,
    List<TransactionModel> transactions,
  ) async {
    _expenseBloc?.add(ReplaceExpensesLocally(expenses));
    await TransactionLocalStore.save(transactions);
    _transactionBloc?.add(ReplaceTransactionsLocally(transactions));
    CategoryDataStore.rebuildFromExpenses(expenses);
    AnalyticsBloc.instance?.applyExpenses(expenses);
  }
}
