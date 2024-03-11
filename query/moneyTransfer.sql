-- name: GetAccountByID :one
select * from accounts where account_id = $1;

-- name: UpdateAccountBalance :exec
update accounts set balance = $2 where account_id = $1;

-- name: TransferWithCTE :exec
with updated_rows as (
    update accounts
    set balance =
        case
            when account_id = $1::int then balance - $3::int
            when account_id = $2::int then balance + $3::int
            else balance
        end
    where account_id in ($1, $2)
    returning *
)
select
    assert( bool_and(balance > 0), 'negative balance') as balance_check,
    assert( count(*) = 2, 'account not found') as account_found
from updated_rows;

-- name: TransferWithFunction :exec
select transferMoney($1, $2, $3);
