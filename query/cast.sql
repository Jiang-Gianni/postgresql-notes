-- name: TextNow :one
select cast(now() as text);

-- name: TimestampNow :one
select cast(now() as timestamp);