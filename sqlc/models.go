// Code generated by sqlc. DO NOT EDIT.
// versions:
//   sqlc v1.24.0

package sqlc

import (
	"database/sql"
)

type Product struct {
	ID       sql.NullInt32
	Name     sql.NullString
	Quantity sql.NullFloat64
}
