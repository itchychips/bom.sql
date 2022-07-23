-- bom.sql is free software: you can redistribute it and/or modify it under the
-- terms of the GNU Affero Public License as published by the Free Software
-- Foundation, either version 3 of the License, or (at your option) any later
-- version.
--
-- bom.sql is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
-- A PARTICULAR PURPOSE. See the GNU Affero Public License for more details.
--
-- You should have received a copy of the GNU Affero Public License along with
-- bom.sql. If not, see <https://www.gnu.org/licenses/>.
DROP TABLE recipe;

CREATE TABLE recipe (
    output_item STRING,
    output_quantity REAL,
    input_item STRING,
    input_quantity REAL);

INSERT INTO recipe VALUES
    ('Wood plank', 4, 'Log', 1),
    ('Stick', 4, 'Wood plank', 2),
    ('Ladder', 3, 'Stick', 7),
    ('Stone pickaxe', 1, 'Stick', 2),
    ('Stone pickaxe', 1, 'Cobblestone', 3),
    ('Iron ingot', 1, 'Iron ore', 1),
    ('Iron ingot', 1, 'Coal', 0.125);

SELECT *
FROM recipe;

-- +---------------+-----------------+-------------+----------------+
-- |  output_item  | output_quantity | input_item  | input_quantity |
-- +---------------+-----------------+-------------+----------------+
-- | Wood plank    | 4.0             | Log         | 1.0            |
-- | Stick         | 4.0             | Wood plank  | 2.0            |
-- | Ladder        | 3.0             | Stick       | 7.0            |
-- | Stone pickaxe | 1.0             | Stick       | 2.0            |
-- | Stone pickaxe | 1.0             | Cobblestone | 3.0            |
-- | Iron ingot    | 1.0             | Iron ore    | 1.0            |
-- | Iron ingot    | 1.0             | Coal        | 0.125          |
-- +---------------+-----------------+-------------+----------------+

-- Note on the below updates: We may change Output/Input of Ladder/Stick to 8
-- depending on if we want to test with clean numbers.  Ladders are great for
-- testing BOM quantities because 7 sticks used is coprime with the output of
-- the recipe of sticks, so it's a better test if you can determine proper
-- numbers, and supposedly the quantities would become more erroneous as you
-- get quantities for the previous input recipes.
--
-- You could also calculate a known common multiple between all input
-- quantities and see if any of them still have a decimal.
--
-- tl;dr: 8 is easy to parse the output for, but 7 is probably a better test.

UPDATE recipe
SET input_quantity = 8
WHERE output_item = 'Ladder'
    AND input_item = 'Stick';

UPDATE recipe
SET input_quantity = 7
WHERE output_item = 'Ladder'
    AND input_item = 'Stick';

-- This gets all materials involved in creation of an item.  This works, but
-- doesn't give proper quantities.  We could loop over this in an imperative
-- language easily to get those quantities, with the last row numbered n being
-- looped over n times, n-1 being n-1 times, etc.  Not efficient, but probably
-- works for minecraft.  Factorio may be a different story, especially if
-- multiple variant recipes enter the equation.
--
-- We use this to evolve the rest of the CTEs below.
WITH cte AS (
    WITH RECURSIVE
        input(n) AS (
            VALUES('Ladder')
            UNION
            SELECT input_item FROM recipe, input
            WHERE recipe.output_item=input.n
        )
    SELECT r.output_quantity, r.output_item, r.input_item, r.input_quantity,
        (CASE r.output_item WHEN 'Ladder' THEN 1 ELSE 2 END) AS sort
    FROM recipe r
    WHERE r.output_item IN input
    ORDER BY sort,r.output_item)
SELECT output_item, output_quantity, input_item, input_quantity
FROM cte;

-- +-----------------+-------------+------------+----------------+
-- | output_quantity | output_item | input_item | input_quantity |
-- +-----------------+-------------+------------+----------------+
-- | 3.0             | Ladder      | Stick      | 7.0            |
-- | 4.0             | Stick       | Wood plank | 2.0            |
-- | 4.0             | Wood plank  | Log        | 1.0            |
-- +-----------------+-------------+------------+----------------+

-- I _think_ this works for getting proper quantities.
WITH cte AS (
    WITH RECURSIVE
        input(output_item, output_quantity, input_item, input_quantity, repeats) AS (
            VALUES('Ladder', 3, 'Stick', 7, 1)
            UNION
            SELECT next.output_item, current.input_quantity, next.input_item, (current.input_quantity / next.output_quantity * next.input_quantity), (current.input_quantity / next.output_quantity)
            FROM recipe next, input current
            WHERE next.output_item = current.input_item
        )
    SELECT *
        --(CASE r.output_item WHEN 'Ladder' THEN 1 ELSE 2 END) AS sort
    FROM input i
    --WHERE r.output_item IN (SELECT input_item FROM input)
    --ORDER BY sort,r.output_item
)
SELECT output_item, output_quantity, input_item, input_quantity
FROM cte;

-- +-------------+-----------------+------------+----------------+
-- | output_item | output_quantity | input_item | input_quantity |
-- +-------------+-----------------+------------+----------------+
-- | Ladder      | 3               | Stick      | 7              |
-- | Stick       | 7               | Wood plank | 3.5            |
-- | Wood plank  | 3.5             | Log        | 0.875          |
-- +-------------+-----------------+------------+----------------+

-- As previous, except we select the output item from the recipes table (will
-- be helpful once we introduce prepared statements we can create from a
-- programming language).  We can also change the desired output quantity with
-- the intial SELECT in the RECURSIVE CTE.
--
-- In this instance, the quantity 8 is enough to clear out any decimals.
WITH cte AS (
    WITH RECURSIVE
        input(output_item, output_quantity, input_item, input_quantity) AS (
            SELECT output_item, 8*output_quantity, input_item, 8*input_quantity
            FROM recipe
            WHERE output_item = 'Ladder'
            UNION
            SELECT next.output_item, current.input_quantity, next.input_item, (current.input_quantity / next.output_quantity * next.input_quantity)
            FROM recipe next, input current
            WHERE next.output_item = current.input_item
        )
    SELECT *,
        (CASE i.output_item WHEN 'Ladder' THEN 1 ELSE 2 END) AS sort
    FROM input i
)
SELECT output_item,
    output_quantity,
    input_item,
    input_quantity
FROM cte
ORDER BY sort, output_item;

-- +-------------+-----------------+------------+----------------+
-- | output_item | output_quantity | input_item | input_quantity |
-- +-------------+-----------------+------------+----------------+
-- | Ladder      | 24.0            | Stick      | 56.0           |
-- | Stick       | 56.0            | Wood plank | 28.0           |
-- | Wood plank  | 28.0            | Log        | 7.0            |
-- +-------------+-----------------+------------+----------------+

-- Now, a recipe with multiple inputs.
WITH cte AS (
    WITH RECURSIVE
        input(output_item, output_quantity, input_item, input_quantity) AS (
            SELECT output_item, 8*output_quantity, input_item, 8*input_quantity
            FROM recipe
            WHERE output_item = 'Iron ingot'
            UNION
            SELECT next.output_item, current.input_quantity, next.input_item, (current.input_quantity / next.output_quantity * next.input_quantity)
            FROM recipe next, input current
            WHERE next.output_item = current.input_item
        )
    SELECT *,
        (CASE i.output_item WHEN 'Iron ingot' THEN 1 ELSE 2 END) AS sort
    FROM input i
)
SELECT output_item,
    output_quantity,
    input_item,
    input_quantity
FROM cte
ORDER BY sort, output_item;

-- +-------------+-----------------+------------+----------------+
-- | output_item | output_quantity | input_item | input_quantity |
-- +-------------+-----------------+------------+----------------+
-- | Iron ingot  | 8.0             | Iron ore   | 8.0            |
-- | Iron ingot  | 8.0             | Coal       | 1.0            |
-- +-------------+-----------------+------------+----------------+

-- Hell yeah!

--------------------------------------------------------------------------------

-- Now an example with EVE Online

DROP TABLE recipe;

CREATE TABLE recipe (
    output_item STRING,
    output_quantity REAL,
    input_item STRING,
    input_quantity REAL);

INSERT INTO recipe VALUES
    ('Antimatter Charge S', 100, 'Tritanium', 184),
    ('Antimatter Charge S', 100, 'Pyerite', 16),
    ('Antimatter Charge S', 100, 'Nocxium', 1);

WITH cte AS (
    WITH RECURSIVE
        input(output_item, output_quantity, input_item, input_quantity) AS (
            SELECT output_item, 13500*output_quantity, input_item, 13500*input_quantity
            FROM recipe
            WHERE output_item = 'Antimatter Charge S'
            UNION
            SELECT next.output_item, current.input_quantity, next.input_item, (current.input_quantity / next.output_quantity * next.input_quantity)
            FROM recipe next, input current
            WHERE next.output_item = current.input_item
        )
    SELECT *,
        (CASE i.output_item WHEN 'Antimatter Charge S' THEN 1 ELSE 2 END) AS sort
    FROM input i
)
SELECT output_item,
    output_quantity,
    input_item,
    input_quantity
FROM cte
ORDER BY sort, output_item;

-- I know for a fact that for 13,500 runs, according to the game, these are the
-- following materials I _should_ need:
--
--     Tritanium: 2,478,600
--     Pyerite:     206,550
--     Nocxium:      13,500
--
-- Let's see how we did:
--
-- +---------------------+-----------------+------------+----------------+
-- |     output_item     | output_quantity | input_item | input_quantity |
-- +---------------------+-----------------+------------+----------------+
-- | Antimatter Charge S | 1350000.0       | Tritanium  | 2484000.0      |
-- | Antimatter Charge S | 1350000.0       | Pyerite    | 216000.0       |
-- | Antimatter Charge S | 1350000.0       | Nocxium    | 13500.0        |
-- +---------------------+-----------------+------------+----------------+
--
-- Not bad!  There seems to rounding for both tritanium and pyerite.  However,
-- with how commodified they are, they aren't a huge issue.  If it really
-- mattered, dry running a blueprint and getting the max runs ratio might be
-- enough to ensure enough accuracy here.

-- We can also enter in time and cost into the equation if we really wanted:

INSERT INTO recipe VALUES
    ('Antimatter Charge S', 100, 'TimeSeconds', 192),
    -- Got this from 11,986 ISK / 10,000 Run
    ('Antimatter Charge S', 100, 'Cost', 1.1986);

WITH cte AS (
    WITH RECURSIVE
        input(output_item, output_quantity, input_item, input_quantity) AS (
            SELECT output_item, 13500*output_quantity, input_item, 13500*input_quantity
            FROM recipe
            WHERE output_item = 'Antimatter Charge S'
            UNION
            SELECT next.output_item, current.input_quantity, next.input_item, (current.input_quantity / next.output_quantity * next.input_quantity)
            FROM recipe next, input current
            WHERE next.output_item = current.input_item
        )
    SELECT *,
        (CASE i.output_item WHEN 'Antimatter Charge S' THEN 1 ELSE 2 END) AS sort
    FROM input i
)
SELECT output_item,
    output_quantity,
    input_item,
    input_quantity
FROM cte
ORDER BY sort, output_item;

-- Should end up with, for 13,500 runs, 16,181 ISK and 2,592,000 seconds (30D even).

WITH cte AS (
    WITH RECURSIVE
        input(output_item, output_quantity, input_item, input_quantity) AS (
            SELECT output_item, 13500*output_quantity, input_item, 13500*input_quantity
            FROM recipe
            WHERE output_item = 'Antimatter Charge S'
            UNION
            SELECT next.output_item, current.input_quantity, next.input_item, (current.input_quantity / next.output_quantity * next.input_quantity)
            FROM recipe next, input current
            WHERE next.output_item = current.input_item
        )
    SELECT *,
        (CASE i.output_item WHEN 'Antimatter Charge S' THEN 1 ELSE 2 END) AS sort
    FROM input i
)
SELECT output_item,
    output_quantity,
    input_item,
    input_quantity
FROM cte
ORDER BY sort, output_item;

-- +---------------------+-----------------+-------------+----------------+
-- |     output_item     | output_quantity | input_item  | input_quantity |
-- +---------------------+-----------------+-------------+----------------+
-- | Antimatter Charge S | 1350000.0       | Tritanium   | 2484000.0      |
-- | Antimatter Charge S | 1350000.0       | Pyerite     | 216000.0       |
-- | Antimatter Charge S | 1350000.0       | Nocxium     | 13500.0        |
-- | Antimatter Charge S | 1350000.0       | TimeSeconds | 2592000.0      |
-- | Antimatter Charge S | 1350000.0       | Cost        | 16181.1        |
-- +---------------------+-----------------+-------------+----------------+

-- Damn, that's good.

-- TODO: Go over using this when there are multiple recipe variants.

--------------------------------------------------------------------------------

-- Some scratch code below

--------------------------------------------------------------------------------

-- Hacky time 2
WITH cte AS (
    WITH RECURSIVE
        input(n) AS (
            VALUES('Ladder')
            UNION
            SELECT input_item FROM recipe, input
            WHERE recipe.output_item=input.n
        )
    SELECT r.output_quantity, r.output_item, r.input_item, r.input_quantity,
        (CASE r.output_item WHEN 'Ladder' THEN 1 ELSE 2 END) AS sort
    FROM recipe r
    WHERE r.output_item IN input
    ORDER BY sort,r.output_item)
SELECT (output_quantity || ' ' || output_item || ' requires ' || input_quantity || ' ' || input_item)
FROM cte;
 
--------------------------------------------------------------------------------

-- Testing some things from
-- https://www.sqlite.org/lang_with.html#outlandish_recursive_query_examples,
-- especially around WITH RECURSIVE.

-- Thank you to the SQLite developers for making such awesome software and
-- documentation and releasing it to the public domain!

--------------------------------------------------------------------------------

CREATE TABLE edge(aa INT, bb INT);
CREATE INDEX edge_aa ON edge(aa);
CREATE INDEX edge_bb ON edge(bb);
INSERT INTO edge VALUES (59, 60), (60, 61), (48, 59), (34, 59), (32, 31), (29, 34);

--------------------------------------------------------------------------------

CREATE TABLE org(
  name TEXT PRIMARY KEY,
  boss TEXT REFERENCES org,
  height INT
  -- other content omitted
);

INSERT INTO org VALUES
    ('Alice', NULL, 42),
    ('Charles', 'Alice', 44),
    ('Donny', 'Charles', 56),
    ('Bob', 'Alice', 56),
    ('Bob2', 'Charles', 56);

INSERT INTO org VALUES
    ('Bob3', 'Marwell', 65);

WITH RECURSIVE
  works_for_alice(n) AS (
    VALUES('Alice')
    UNION
    SELECT name FROM org, works_for_alice
     WHERE org.boss=works_for_alice.n
  )
SELECT * FROM org
 WHERE org.name IN works_for_alice;
