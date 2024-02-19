// Code generated by sqlc. DO NOT EDIT.
// versions:
//   sqlc v1.24.0
// source: cast.sql

package sqlc

import (
	"context"
	"time"
)

const textNow = `-- name: TextNow :one
select cast(now() as text)
`

func (q *Queries) TextNow(ctx context.Context) (string, error) {
	row := q.db.QueryRowContext(ctx, textNow)
	var column_1 string
	err := row.Scan(&column_1)
	return column_1, err
}

const timestampNow = `-- name: TimestampNow :one
select cast(now() as timestamp)
`

func (q *Queries) TimestampNow(ctx context.Context) (time.Time, error) {
	row := q.db.QueryRowContext(ctx, timestampNow)
	var column_1 time.Time
	err := row.Scan(&column_1)
	return column_1, err
}
