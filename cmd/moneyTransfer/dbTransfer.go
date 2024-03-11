package main

import (
	"context"

	"github.com/Jiang-Gianni/postgresql-notes/sqlc"
)

func (svc *Service) TransferMoneyDBCTE(ctx context.Context, fromAccountID int32, toAccountID int32, amount int32) error {
	return svc.s.TransferWithCTE(ctx, sqlc.TransferWithCTEParams{
		Column1: fromAccountID,
		Column2: toAccountID,
		Column3: amount,
	})
}

func (svc *Service) TransferMoneyDBFunction(ctx context.Context, fromAccountID int32, toAccountID int32, amount int32) error {
	return svc.s.TransferWithFunction(ctx, sqlc.TransferWithFunctionParams{
		InAccFrom: fromAccountID,
		InAccTo:   toAccountID,
		Amount:    amount,
	})
}
