-- Card definition caps, transcribed from assets/cards/gen_table.csv.
-- Run after schema.sql. Re-running is safe (upsert).
--
-- Only the MAX columns of the CSV are here, plus the base attack type - see
-- the card_defs comment in schema.sql for why the generation minimums are
-- deliberately not used as a validation floor.
--
-- Attack type letters map to Card.AttackType (scripts/Card.gd:5):
--   P = 0 physical, M = 1 magical, X = 2 flexible, A = 3 assault
--
-- Transcribed by hand rather than generated: 21 rows is less code than any
-- script that would produce them. If gen_table.csv ever grows a lot, or its
-- caps get rebalanced, revisit that call - but keep this file the single
-- place the server learns what a legal card looks like.

insert into card_defs (def_id, name, atk_cap, pdef_cap, mdef_cap, atype_base, atype_max) values
	( 0, 'Slime',           10,  14,   8, 0, 0),
	( 1, 'Zombie',          20,  14,  17, 0, 0),
	( 2, 'Ghost',           29,  29,  22, 1, 1),
	( 3, 'Skeleton',        43,  34,  30, 0, 0),
	( 4, 'Black Wolf',      53,  46,  43, 0, 2),
	( 5, 'Goblin Sciaman',  62,  53,  59, 1, 2),
	( 6, 'Troll',           77,  73,  64, 0, 2),
	( 7, 'Centaur',         81,  87,  81, 0, 2),
	( 8, 'Ginger',          98,  98,  94, 0, 2),
	( 9, 'Nymph',          112, 101, 116, 1, 2),
	(10, 'Pegasus',        125, 125, 125, 0, 2),
	(11, 'Minotaur',       144, 140, 130, 0, 2),
	(12, 'Griffin',        159, 155, 144, 0, 3),
	(13, 'Elementals',     169, 176, 153, 1, 3),
	(14, 'Lamia',          185, 170, 189, 1, 3),
	(15, 'Kraken Queen',   198, 183, 202, 1, 3),
	(16, 'Lich',           213, 195, 217, 1, 3),
	(17, 'Odin',           228, 217, 221, 2, 3),
	(18, 'Dragon',         242, 231, 239, 2, 3),
	(19, 'The Void',       251, 251, 251, 3, 3),
	(20, 'Rage Quit',      255, 255, 255, 2, 3)
on conflict (def_id) do update set
	name = excluded.name,
	atk_cap = excluded.atk_cap,
	pdef_cap = excluded.pdef_cap,
	mdef_cap = excluded.mdef_cap,
	atype_base = excluded.atype_base,
	atype_max = excluded.atype_max;
