package main

import (
	"context"
	"testing"
)

func BenchmarkApplicationMoneyTransfer(b *testing.B) {
	svc := NewService()
	defer svc.db.Close()
	var err error
	ctx := context.Background()
	// errgrp := errgroup.Group{}
	for i := 0; i < b.N; i++ {

		// WILL DEADLOCK
		// errgrp.Go(func() error { return svc.TransferMoneyApp(ctx, 1, 2, 1) })
		// errgrp.Go(func() error { return svc.TransferMoneyApp(ctx, 2, 1, 1) })
		// err = errgrp.Wait()
		// if err != nil {
		// 	b.Fatal(err)
		// }

		err = svc.TransferMoneyApp(ctx, 1, 2, 1)
		if err != nil {
			b.Fatal(err)
		}
		err = svc.TransferMoneyApp(ctx, 2, 1, 1)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkDatabaseCTEMoneyTransfer(b *testing.B) {
	svc := NewService()
	defer svc.db.Close()
	var err error
	ctx := context.Background()
	// errgrp := errgroup.Group{}
	for i := 0; i < b.N; i++ {
		// errgrp.Go(func() error { return svc.TransferMoneyDBCTE(ctx, 1, 2, 1) })
		// errgrp.Go(func() error { return svc.TransferMoneyDBCTE(ctx, 2, 1, 1) })
		// err = errgrp.Wait()
		// if err != nil {
		// 	b.Fatal(err)
		// }
		err = svc.TransferMoneyDBCTE(ctx, 1, 2, 1)
		if err != nil {
			b.Fatal(err)
		}
		err = svc.TransferMoneyDBCTE(ctx, 2, 1, 1)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkDatabaseFunctionMoneyTransfer(b *testing.B) {
	svc := NewService()
	defer svc.db.Close()
	var err error
	ctx := context.Background()
	// errgrp := errgroup.Group{}
	for i := 0; i < b.N; i++ {
		// errgrp.Go(func() error { return svc.TransferMoneyDBFunction(ctx, 1, 2, 1) })
		// errgrp.Go(func() error { return svc.TransferMoneyDBFunction(ctx, 2, 1, 1) })
		// err = errgrp.Wait()
		// if err != nil {
		// 	b.Fatal(err)
		// }
		err = svc.TransferMoneyDBFunction(ctx, 1, 2, 1)
		if err != nil {
			b.Fatal(err)
		}
		err = svc.TransferMoneyDBFunction(ctx, 2, 1, 1)
		if err != nil {
			b.Fatal(err)
		}
	}
}
