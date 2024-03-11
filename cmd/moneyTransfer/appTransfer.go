package main

import (
	"context"
	"fmt"

	"github.com/Jiang-Gianni/postgresql-notes/sqlc"
)

func (svc *Service) TransferMoneyApp(ctx context.Context, fromAccountID int32, toAccountID int32, amount int32) error {
	// Start transaction
	tx, err := svc.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	// Rollback if not commit
	defer tx.Rollback()

	// Get the two accounts (fromAcc and toAcc) and then update their balances
	q := svc.s.WithTx(tx)
	fromAcc, err := q.GetAccountByID(ctx, fromAccountID)
	if err != nil {
		return err
	}
	toAcc, err := q.GetAccountByID(ctx, toAccountID)
	if err != nil {
		return err
	}
	if fromAcc.Balance < amount {
		return fmt.Errorf("balance is too low to transfer %d", amount)
	}
	err = q.UpdateAccountBalance(ctx,
		sqlc.UpdateAccountBalanceParams{
			AccountID: fromAcc.AccountID,
			Balance:   fromAcc.Balance - amount,
		},
	)
	if err != nil {
		return err
	}
	err = q.UpdateAccountBalance(ctx,
		sqlc.UpdateAccountBalanceParams{
			AccountID: toAcc.AccountID,
			Balance:   toAcc.Balance + amount,
		},
	)
	if err != nil {
		return err
	}

	// Commit
	return tx.Commit()
}
