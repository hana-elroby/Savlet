import 'package:equatable/equatable.dart';
import '../../../core/models/expense.dart';

abstract class ExpenseEvent extends Equatable {
  const ExpenseEvent();

  @override
  List<Object?> get props => [];
}

// Add new expense
class AddExpense extends ExpenseEvent {
  final Expense expense;

  const AddExpense(this.expense);

  @override
  List<Object?> get props => [expense];
}

// Delete expense
class DeleteExpense extends ExpenseEvent {
  final String expenseId;

  const DeleteExpense(this.expenseId);

  @override
  List<Object?> get props => [expenseId];
}

// Load expenses (for future Firebase integration)
class LoadExpenses extends ExpenseEvent {
  /// When true, keep showing current expenses while refreshing in the background.
  final bool silent;

  const LoadExpenses({this.silent = false});

  @override
  List<Object?> get props => [silent];
}

// Update expense
class UpdateExpense extends ExpenseEvent {
  final Expense expense;

  const UpdateExpense(this.expense);

  @override
  List<Object?> get props => [expense];
}

// Clear all expenses
class ClearAllExpenses extends ExpenseEvent {
  const ClearAllExpenses();
}

// Replace local expense list (used by unified sync)
class ReplaceExpensesLocally extends ExpenseEvent {
  final List<Expense> expenses;

  const ReplaceExpensesLocally(this.expenses);

  @override
  List<Object?> get props => [expenses];
}



