-- name: DndGetClasses :many
select * from dndclasses;

-- name: DndRecursiveJSON :one
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
-- Finally, the traversal being done, we can aggregate
-- the top-level classes all into the same JSON document,
-- an array.
-- select jsonb_pretty(jsonb_agg(js))
select jsonb_agg(js)
  from dndclasses_from_children
 where parent_id IS NULL;
