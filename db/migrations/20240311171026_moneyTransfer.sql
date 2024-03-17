-- migrate:up
create table accounts(
    -- constraint not_negative_balance check(balance >= 0),
    account_id serial primary key,
    balance integer not null
);

create or replace function assert ( in_assertion boolean, in_errormessage text)
returns boolean immutable language plpgsql security invoker as
$$
  begin
    if not in_assertion
    then raise exception '%', in_errormessage;
    end if;
    return in_assertion;
  end;
$$;

create or replace function transferMoney(in_acc_from integer, in_acc_to integer, amount integer)
returns void language plpgsql as
$$
    declare
        discard record;
    begin
        with updated_rows as (
            update accounts
            set balance =
                case
                    when account_id = in_acc_from then balance - amount
                    when account_id = in_acc_to then balance + amount
                    else balance
                end
            where account_id in (in_acc_from, in_acc_to)
            returning *
        )
        select
            assert( bool_and(balance > 0), 'negative balance') as balance_check,
            assert( count(*) = 2, 'account not found') as account_found
        from updated_rows into discard;
        return;
    end;
$$;

insert into accounts(balance) values (100), (100);

-- migrate:down
drop function assert;
drop table accounts;