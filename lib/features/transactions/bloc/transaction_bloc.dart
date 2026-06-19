import 'package:flutter_bloc/flutter_bloc.dart';
import 'transaction_event.dart';
import 'transaction_state.dart';
import '../models/transaction_model.dart';
import '../../../core/services/transaction_api_service.dart';
import '../../../core/services/transaction_local_store.dart';
import '../../../core/services/expense_sync_service.dart';
import '../../../core/services/auth_api_service.dart';

class TransactionBloc extends Bloc<TransactionEvent, TransactionState> {
  static TransactionBloc? instance;

  final TransactionApiService _service = TransactionApiService.instance;

  TransactionBloc() : super(const TransactionState()) {
    instance = this;
    ExpenseSyncService.instance.registerTransactionBloc(this);
    on<LoadTransactions>(_onLoad);
    on<DeleteTransaction>(_onDelete);
    on<AddTransaction>(_onAdd);
    on<ReplaceTransactionsLocally>(_onReplaceTransactionsLocally);
  }

  Future<void> _onLoad(
      LoadTransactions event, Emitter<TransactionState> emit) async {
    emit(state.copyWith(status: TransactionStatus.loading));

    final isLoggedIn = await AuthApiService.instance.isAuthenticated();

    if (isLoggedIn) {
      try {
        const limit = 100;
        var page = 1;
        final all = <TransactionModel>[];
        var fetchedFromBackend = false;

        while (true) {
          final result = await _service.getMyTransactions(page: page, limit: limit);
          if (!result.isSuccess) {
            if (!fetchedFromBackend) throw Exception('backend fetch failed');
            break;
          }
          fetchedFromBackend = true;
          all.addAll(result.transactions.map(TransactionLocalStore.fromCore));
          if (page >= result.totalPages) break;
          page++;
        }

        final transactions = TransactionLocalStore.dedupe(all);
        await TransactionLocalStore.save(transactions);
        emit(state.copyWith(
          status: TransactionStatus.loaded,
          transactions: transactions,
        ));
        return;
      } catch (_) {
        // fall through to local cache
      }
    }

    final local = await TransactionLocalStore.load();
    emit(state.copyWith(
      status: TransactionStatus.loaded,
      transactions: local,
    ));
  }

  Future<void> _onDelete(
      DeleteTransaction event, Emitter<TransactionState> emit) async {
    await ExpenseSyncService.instance.deleteEverywhere(event.transactionId);
  }

  Future<void> _onReplaceTransactionsLocally(
      ReplaceTransactionsLocally event, Emitter<TransactionState> emit) async {
    emit(state.copyWith(
      status: TransactionStatus.loaded,
      transactions: event.transactions,
    ));
  }

  @override
  Future<void> close() {
    if (identical(TransactionBloc.instance, this)) {
      TransactionBloc.instance = null;
    }
    return super.close();
  }

  Future<void> _onAdd(AddTransaction event, Emitter<TransactionState> emit) async {
    final newT = TransactionModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: event.title,
      description: event.description,
      amount: event.amount,
      category: event.category,
      type: event.type,
      date: event.date,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await TransactionLocalStore.upsert(newT);
    final updated = await TransactionLocalStore.load();
    emit(state.copyWith(
        status: TransactionStatus.loaded, transactions: updated));

    if (AuthApiService.instance.isLoggedIn) {
      try {
        final result = await _service.createWithText(
            text: event.title, price: event.amount);
        if (result.isSuccess) {
          add(const LoadTransactions());
        }
      } catch (_) {}
    }
  }
}
