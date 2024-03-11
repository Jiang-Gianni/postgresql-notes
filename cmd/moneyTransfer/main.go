package main

import (
	"context"
	"database/sql"
	"log"

	"github.com/Jiang-Gianni/postgresql-notes/db"
	"github.com/Jiang-Gianni/postgresql-notes/sqlc"

	_ "github.com/lib/pq"
)

func main() {
	ctx := context.Background()
	svc := NewService()
	defer svc.db.Close()

	// if err := svc.TransferMoneyApp(ctx, 1, 2, 101); err != nil {
	// 	log.Fatal(err)
	// }

	if err := svc.TransferMoneyDBCTE(ctx, 1, 2, 15); err != nil {
		log.Fatal(err)
	}
}

type Service struct {
	s  *sqlc.Queries
	db *sql.DB
}

func NewService() *Service {
	sqlDB, err := sql.Open("postgres", db.DATABASE_URL)
	if err != nil {
		panic(err)
	}
	query := sqlc.New(sqlDB)
	return &Service{
		s:  query,
		db: sqlDB,
	}
}
