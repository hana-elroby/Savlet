import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/expense.dart';
import '../../../core/models/transaction_model.dart' as core;
import '../../../core/services/transaction_api_service.dart';
import '../../../core/services/transaction_local_store.dart';
import '../../../core/services/expense_sync_service.dart';
import '../../../core/services/item_api_service.dart';
import '../../../core/services/category_api_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/storage/simple_storage.dart';
import '../../categories/category_data_store.dart';
import 'analytics_bloc.dart';
import 'expense_event.dart';
import 'expense_state.dart';

class ExpenseBloc extends Bloc<ExpenseEvent, ExpenseState> {
  static ExpenseBloc? instance;

  static const String _storageKey = 'expenses_data';
  final SimpleStorage _storage = SimpleStorage();
  final TransactionApiService _transactionApi = TransactionApiService.instance;
  final ApiService _api = ApiService();
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  ExpenseBloc() : super(const ExpenseLoaded([])) {
    instance = this;
    ExpenseSyncService.instance.registerExpenseBloc(this);
    on<AddExpense>(_onAddExpense);
    on<DeleteExpense>(_onDeleteExpense);
    on<UpdateExpense>(_onUpdateExpense);
    on<LoadExpenses>(_onLoadExpenses);
    on<ClearAllExpenses>(_onClearAllExpenses);
    on<ReplaceExpensesLocally>(_onReplaceExpensesLocally);

    // Auto-load on creation
    add(const LoadExpenses());

    // Connect to WebSocket for real-time analytics updates
    _connectWebSocket();
  }

  void _connectWebSocket() {
    final ws = WebSocketService.instance;
    ws.connect();
    _wsSubscription = ws.analyticsStream.listen((payload) {
      // Backend sent analytics_update — refresh expenses from backend
      print('📊 [ExpenseBloc] Real-time update received, refreshing...');
      add(const LoadExpenses(silent: true));
    });
  }

  @override
  Future<void> close() {
    if (identical(ExpenseBloc.instance, this)) {
      ExpenseBloc.instance = null;
    }
    _wsSubscription?.cancel();
    return super.close();
  }

  // ─── Persistence helpers ───────────────────────────────────────────────────

  Future<void> _saveLocal(List<Expense> expenses) async {
    final jsonList = expenses.map((e) => e.toMap()).toList();
    await _storage.write(_storageKey, jsonEncode(jsonList));
  }

  Future<List<Expense>> _loadLocal() async {
    final jsonString = await _storage.read(_storageKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList
        .map((e) => Expense.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Mirror a new expense into TransactionBloc's local storage (upsert — no duplicates)
  Future<void> _mirrorToTransactions(Expense expense) async {
    try {
      await TransactionLocalStore.upsert(
        TransactionLocalStore.fromCore(
          core.TransactionModel(
            id: expense.id,
            text: expense.title,
            price: expense.amount,
            categoryName: expense.category,
            userId: '',
            createdAt: expense.date,
          ),
        ),
      );
    } catch (e) {
      print('⚠️ Mirror to transactions failed: $e');
    }
  }

  Future<void> _onReplaceExpensesLocally(
      ReplaceExpensesLocally event, Emitter<ExpenseState> emit) async {
    emit(ExpenseLoaded(event.expenses));
    await _saveLocal(event.expenses);
  }

  // ─── Event handlers ────────────────────────────────────────────────────────

  Future<void> _onAddExpense(
      AddExpense event, Emitter<ExpenseState> emit) async {
    if (state is! ExpenseLoaded) return;
    final current = state as ExpenseLoaded;

    // Optimistic update — show immediately in UI
    final updated = List<Expense>.from(current.expenses)..add(event.expense);
    emit(ExpenseLoaded(updated));
    await _saveLocal(updated);

    // Mirror to TransactionBloc storage so Transactions page sees it
    await _mirrorToTransactions(event.expense);

    // Send to backend if logged in
    final isLoggedIn = await AuthApiService.instance.isAuthenticated();
    if (!isLoggedIn) return;

    try {
      // Step 1: Find or create category on backend first
      final categoryResult = await CategoryApiService.instance.getCategories();
      String? categoryId;
      if (categoryResult.isSuccess) {
        final match = categoryResult.categories
            .where((c) => c.name.toLowerCase() == event.expense.category.toLowerCase())
            .firstOrNull;
        categoryId = match?.id;
      }

      // Create category if not found
      if (categoryId == null) {
        final newCat = await CategoryApiService.instance.createCategory(
          name: event.expense.category,
          icon: 'category',
          color: '#1976D2',
        );
        if (newCat.isSuccess && newCat.category != null) {
          categoryId = newCat.category!.id;
          print('✅ New category created: ${event.expense.category}');
        }
      }

      if (categoryId == null) {
        print('⚠️ Could not find or create category');
        return;
      }

      // Step 2: Create item linked to category
      final itemResult = await ItemApiService.instance.createItem(
        name: event.expense.title,
        categoryId: categoryId,
        price: event.expense.amount,
      );

      if (!itemResult.isSuccess || itemResult.item == null) {
        print('⚠️ Failed to create item: ${itemResult.message}');
        return;
      }

      final itemId = itemResult.item!.id;
      print('✅ Item created: ${event.expense.title} (id: $itemId)');

      // Build body as raw JSON string to avoid Dio array serialization issues
      final bodyJson = '{"text":${jsonEncode(event.expense.title)},"price":${event.expense.amount},"categoryId":${jsonEncode(categoryId)},"items":["${itemId}"],"quantity":${event.expense.quantity},"transactionDate":"${event.expense.date.toIso8601String()}"}';
      
      print('🚀 Sending transaction body: $bodyJson');
      final result = await _api.postRaw('/transactions/createWithText', bodyJson);
      if (result.isSuccess) {
        print('✅ Transaction synced to backend: ${event.expense.title}');
        // Refresh from backend so UI shows the saved data
        add(const LoadExpenses(silent: true));
        // Trigger analytics refresh immediately
        Future.delayed(const Duration(milliseconds: 500), () {
          AnalyticsBloc.instance?.refresh();
        });
      } else {
        print('⚠️ Transaction sync failed: ${result.message}');
      }
    } catch (e) {
      print('⚠️ Backend sync error: $e');
    }
  }

  Future<void> _onDeleteExpense(
      DeleteExpense event, Emitter<ExpenseState> emit) async {
    await ExpenseSyncService.instance.deleteEverywhere(event.expenseId);
  }

  Future<void> _onUpdateExpense(
      UpdateExpense event, Emitter<ExpenseState> emit) async {
    if (state is! ExpenseLoaded) return;
    final current = state as ExpenseLoaded;
    final updated = current.expenses
        .map((e) => e.id == event.expense.id ? event.expense : e)
        .toList();
    emit(ExpenseLoaded(updated));
    await _saveLocal(updated);
  }

  Future<void> _onLoadExpenses(
      LoadExpenses event, Emitter<ExpenseState> emit) async {
    final cachedExpenses =
        state is ExpenseLoaded ? (state as ExpenseLoaded).expenses : null;

    if (!event.silent || cachedExpenses == null) {
      emit(const ExpenseLoading());
    }

    try {
      final isLoggedIn = await AuthApiService.instance.isAuthenticated();

      if (isLoggedIn) {
        // Try to load from backend first
        try {
          final result = await _transactionApi.getMyTransactions(limit: 200);
          print('📡 Backend response: success=${result.isSuccess}, count=${result.transactions.length}, msg=${result.message}');
          if (result.isSuccess) {
            final deduped = TransactionLocalStore.dedupe(
              result.transactions.map(TransactionLocalStore.fromCore).toList(),
            );
            await TransactionLocalStore.save(deduped);

            if (deduped.isEmpty) {
              emit(const ExpenseLoaded([]));
              await _saveLocal([]);
              return;
            }

            // Load local data to preserve quantities (not stored in backend)
            final localExpenses = await _loadLocal();
            final localMap = {for (final e in localExpenses) e.id: e};

            final expenses = deduped.map((t) {
              final local = localMap[t.id];
              return Expense(
                id: t.id,
                title: t.title,
                amount: t.amount,
                category: t.category.isNotEmpty ? t.category : 'Other',
                date: t.date,
                isVoiceInput: t.type == 'voice',
                quantity: local?.quantity ?? 1,
              );
            }).toList();

            emit(ExpenseLoaded(expenses));
            await _saveLocal(expenses);
            CategoryDataStore.rebuildFromExpenses(expenses);
            await ExpenseSyncService.instance.applyTransactionList(deduped);
            print('✅ Loaded ${expenses.length} expenses from backend');
            return;
          }
        } catch (e) {
          print('⚠️ Backend load failed, falling back to local: $e');
        }
      }

      // Fallback to local storage
      final local = await _loadLocal();
      if (local.isNotEmpty || cachedExpenses == null) {
        emit(ExpenseLoaded(local));
        print('📦 Loaded ${local.length} expenses from local storage');
      } else {
        emit(ExpenseLoaded(cachedExpenses));
        print('📦 Kept ${cachedExpenses.length} cached expenses after load failure');
      }
    } catch (e) {
      if (cachedExpenses != null) {
        emit(ExpenseLoaded(cachedExpenses));
      } else {
        emit(ExpenseError(e.toString()));
      }
    }
  }

  Future<void> _onClearAllExpenses(
      ClearAllExpenses event, Emitter<ExpenseState> emit) async {
    emit(const ExpenseLoaded([]));
    await _storage.delete(_storageKey);
  }

  void refreshExpenses({bool silent = true}) =>
      add(LoadExpenses(silent: silent));
  void clearAllExpenses() => add(ClearAllExpenses());
}
