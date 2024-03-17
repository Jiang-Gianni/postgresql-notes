 ## accounts
 | column_name | column_type | key | reference | comment |
 | ----------- | ----------- | --- | --------- | ------- |
 | account_id  | int4        | p   |           |         |
 | balance     | int4        |     |           |         |


 ## bookings

 <i> Member ID associated  with the bookings </i>

 | column_name | column_type | key | reference                       | comment                                          |
 | ----------- | ----------- | --- | ------------------------------- | ------------------------------------------------ |
 | bookid      | int4        | p   |                                 |                                                  |
 | facid       | int4        | f   | [facilities.facid](#facilities) |                                                  |
 | memid       | int4        | f   | [members.memid](#members)       | <i> Member ID associated  with the bookings </i> |
 | starttime   | timestamp   |     |                                 |                                                  |
 | slots       | int4        |     |                                 |                                                  |


 ## dndclasses
 | column_name | column_type | key | reference                    | comment |
 | ----------- | ----------- | --- | ---------------------------- | ------- |
 | id          | int4        | p   |                              |         |
 | parent_id   | int4        | f   | [dndclasses.id](#dndclasses) |         |
 | name        | text        |     |                              |         |


 ## facilities
 | column_name        | column_type | key | reference | comment |
 | ------------------ | ----------- | --- | --------- | ------- |
 | facid              | int4        | p   |           |         |
 | name               | varchar     |     |           |         |
 | membercost         | numeric     |     |           |         |
 | guestcost          | numeric     |     |           |         |
 | initialoutlay      | numeric     |     |           |         |
 | monthlymaintenance | numeric     |     |           |         |


 ## foo
 | column_name | column_type | key | reference | comment |
 | ----------- | ----------- | --- | --------- | ------- |
 | fooid       | int4        |     |           |         |
 | foosubid    | int4        |     |           |         |
 | fooname     | text        |     |           |         |


 ## members
 | column_name   | column_type | key | reference                 | comment |
 | ------------- | ----------- | --- | ------------------------- | ------- |
 | memid         | int4        | p   |                           |         |
 | surname       | varchar     |     |                           |         |
 | firstname     | varchar     |     |                           |         |
 | address       | varchar     |     |                           |         |
 | zipcode       | int4        |     |                           |         |
 | telephone     | varchar     |     |                           |         |
 | recommendedby | int4        | f   | [members.memid](#members) |         |
 | joindate      | timestamp   |     |                           |         |


 ## onlyfib
 | column_name | column_type | key | reference | comment |
 | ----------- | ----------- | --- | --------- | ------- |
 | i           | int4        |     |           |         |


 ## payroll
 | column_name | column_type | key | reference | comment |
 | ----------- | ----------- | --- | --------- | ------- |
 | emp_no      | int4        |     |           |         |
 | emp_name    | varchar     |     |           |         |
 | dept_name   | varchar     |     |           |         |
 | salary_amt  | numeric     |     |           |         |


 ## products
 | column_name | column_type | key | reference | comment |
 | ----------- | ----------- | --- | --------- | ------- |
 | id          | int4        |     |           |         |
 | name        | text        |     |           |         |
 | quantity    | float8      |     |           |         |


 ## products_citus
 | column_name | column_type | key | reference | comment |
 | ----------- | ----------- | --- | --------- | ------- |
 | product_no  | int4        |     |           |         |
 | name        | text        |     |           |         |
 | price       | numeric     |     |           |         |
 | sale_price  | numeric     |     |           |         |


 ## schema_migrations
 | column_name | column_type | key | reference | comment |
 | ----------- | ----------- | --- | --------- | ------- |
 | version     | varchar     | p   |           |         |


 ## table1
 | column_name | column_type | key | reference | comment |
 | ----------- | ----------- | --- | --------- | ------- |
 | key         | int4        | p   |           |         |
 | value       | int4        |     |           |         |
 | value_type  | varchar     |     |           |         |


 ## table2
 | column_name | column_type | key | reference | comment |
 | ----------- | ----------- | --- | --------- | ------- |
 | key         | int4        |     |           |         |
 | value       | int4        |     |           |         |
 | value_type  | varchar     |     |           |         |
 | user_name   | name        |     |           |         |
 | action      | varchar     |     |           |         |
 | action_time | timestamp   |     |           |         |
