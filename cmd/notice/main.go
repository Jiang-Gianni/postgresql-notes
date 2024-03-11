package main

import (
	"context"
	"fmt"
	"log"

	"github.com/Jiang-Gianni/postgresql-notes/db"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v4"
)

func onNotify(c *pgconn.PgConn, n *pgconn.Notice) {
	fmt.Println("Message:", *n)
}
func main() {

	ctx := context.Background()

	connectionString := fmt.Sprintf(db.DATABASE_URL)

	conf, err := pgx.ParseConfig(connectionString)

	if err != nil {
		fmt.Println(err)
	}

	conf.OnNotice = onNotify

	conn, err := pgx.ConnectConfig(ctx, conf)
	if err != nil {
		log.Fatalln(err)
	}
	defer conn.Close(ctx)

	query := `DO language plpgsql $$
BEGIN
   RAISE NOTICE 'hello, world!';
END
$$;`

	_, err = conn.Exec(ctx, query)

	if err != nil {
		log.Fatal(err)
	}

}
