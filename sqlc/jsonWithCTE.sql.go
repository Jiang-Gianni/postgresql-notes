// Code generated by sqlc. DO NOT EDIT.
// versions:
//   sqlc v1.24.0
// source: jsonWithCTE.sql

package sqlc

import (
	"context"
	"encoding/json"
)

const dndGetClasses = `-- name: DndGetClasses :many
select id, parent_id, name from dndclasses
`

func (q *Queries) DndGetClasses(ctx context.Context) ([]Dndclass, error) {
	rows, err := q.db.QueryContext(ctx, dndGetClasses)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var items []Dndclass
	for rows.Next() {
		var i Dndclass
		if err := rows.Scan(&i.ID, &i.ParentID, &i.Name); err != nil {
			return nil, err
		}
		items = append(items, i)
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return items, nil
}

const dndRecursiveJSON = `-- name: DndRecursiveJSON :one
with recursive dndclasses_from_parents as
(
         -- Classes with no parent, our starting point
      select id, name, '{}'::int[] as parents, 0 as level
        from dndclasses
       where parent_id is NULL

   union all

         -- Recursively find sub-classes and append them to the result-set
      select c.id, c.name, parents || c.parent_id, level+1
        from      dndclasses_from_parents p
             join dndclasses c
               on c.parent_id = p.id
       where not c.id = any(parents)
),
    dndclasses_from_children as
(
         -- Now start from the leaf nodes and recurse to the top-level
         -- Leaf nodes are not parents (level > 0) and have no other row
         -- pointing to them as their parents, directly or indirectly
         -- (not id = any(parents))
     select c.parent_id,
            json_agg(jsonb_build_object('Name', c.name))::jsonb as js
       from dndclasses_from_parents tree
            join dndclasses c using(id)
      where level > 0 and not id = any(parents)
   group by c.parent_id

  union all

         -- build our JSON document, one piece at a time
         -- as we're traversing our graph from the leaf nodes,
         -- the bottom-up traversal makes it possible to accumulate
         -- sub-classes as JSON document parts that we glue together
     select c.parent_id,

               jsonb_build_object('Name', c.name)
            || jsonb_build_object('Sub Classes', js) as js

       from dndclasses_from_children tree
            join dndclasses c on c.id = tree.parent_id
)
select jsonb_agg(js)
  from dndclasses_from_children
 where parent_id IS NULL
`

// Finally, the traversal being done, we can aggregate
// the top-level classes all into the same JSON document,
// an array.
// select jsonb_pretty(jsonb_agg(js))
func (q *Queries) DndRecursiveJSON(ctx context.Context) (json.RawMessage, error) {
	row := q.db.QueryRowContext(ctx, dndRecursiveJSON)
	var jsonb_agg json.RawMessage
	err := row.Scan(&jsonb_agg)
	return jsonb_agg, err
}
