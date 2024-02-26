package main

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/Jiang-Gianni/postgresql-notes/db"
	"github.com/Jiang-Gianni/postgresql-notes/sqlc"
	_ "github.com/lib/pq"
)

func main() {
	ctx := context.Background()
	sqlDB, err := sql.Open("postgres", db.DATABASE_URL)
	if err != nil {
		panic(err)
	}
	defer sqlDB.Close()
	query := sqlc.New(sqlDB)
	payload, err := query.DndRecursiveJSON(ctx)
	if err != nil {
		panic(err)
	}
	fmt.Println(string(payload))
	// s := Server{}
	// if err := s.runServer(); err != nil {
	// 	panic(err)
	// }

}
