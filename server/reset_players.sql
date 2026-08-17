-- DESTRUCTIVE. Wipes every online account and everything hanging off it:
-- leaderboard standings, Elo, the registry of cards ever staked, the
-- lost-card ledger, the queue, and all match history. Card Master save files
-- on players' own machines are untouched.
--
-- This exists for testing a still-private server. Do not run it once real
-- people have accounts - there is no undo, and their names come free for
-- anyone else to take.
--
-- Everything else cascades from profiles through its foreign keys, so one
-- delete is enough. auth.users rows are deliberately left alone: they cost
-- nothing, and a client whose stored session outlives its profile simply
-- creates a fresh profile under the same save name the next time it connects.

delete from profiles;

-- What is left, for a quick eyeball afterwards.
select
	(select count(*) from profiles)     as profiles,
	(select count(*) from player_cards) as player_cards,
	(select count(*) from lost_cards)   as lost_cards,
	(select count(*) from queue)        as queued,
	(select count(*) from matches)      as matches,
	(select count(*) from moves)        as moves;
