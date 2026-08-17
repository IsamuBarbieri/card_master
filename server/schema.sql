-- Card Master online backend, Supabase/Postgres.
--
-- Apply by pasting this whole file into the Supabase SQL editor, then
-- seed_card_defs.sql after it. Re-running it is safe (everything is
-- create-if-not-exists / create-or-replace) EXCEPT the drop of the enum type,
-- so it is written to be idempotent from a fresh project onwards.
--
-- Design note - where the anti-cheat actually lives:
--   Every table has RLS enabled with NO write policy, so a client holding an
--   anon JWT cannot touch a single row directly. All access goes through the
--   mp_* functions below, which are SECURITY DEFINER and therefore run as the
--   owner, past RLS. If a rule isn't enforced in one of these functions, it
--   isn't enforced at all. That is the whole security model - keep it that way
--   and resist the temptation to add a convenience policy.
--
-- The match itself is NOT simulated here. Both clients simulate it from a
-- seed this server hands out (see scripts/BattleRng.gd) and submit a hash of
-- their board after every move; this server only compares the two hashes and
-- voids the match when they disagree. That keeps the game rules in exactly one
-- language (GDScript) instead of duplicating scripts/battle/gsBattle.gd and
-- scripts/Board.gd in SQL and having to keep the two in step forever.

-- ---------------------------------------------------------------- reference

-- Mirror of assets/cards/gen_table.csv. Only the CAPS are stored, not the
-- generation minimums: the minimums are useless as a validation floor because
-- Player.add_captured_rage_quit_card (scripts/Player.gd:44) legitimately
-- rerolls a captured card down to 3-12, far below its species' floor. A
-- cheater wants stats HIGHER than legal, never lower, so an upper bound is the
-- only bound worth checking.
create table if not exists card_defs (
	def_id      int primary key,
	name        text not null,
	atk_cap     int not null,
	pdef_cap    int not null,
	mdef_cap    int not null,
	atype_base  int not null,  -- Card.AttackType: 0=P 1=M 2=X 3=A
	atype_max   int not null
);

-- ------------------------------------------------------------------ players

-- One row per account. An account is per SAVE SLOT, not per device: unique_id
-- is a per-slot counter (SaveSystem's next_uid), so two slots on the same PC
-- number their cards identically and would collide if they shared an account.
create table if not exists profiles (
	id       uuid primary key references auth.users on delete cascade,
	name     text not null default 'Player',
	elo      int  not null default 1200,
	wins     int  not null default 0,
	losses   int  not null default 0,
	draws    int  not null default 0,
	voids    int  not null default 0,  -- matches thrown out over a hash mismatch
	quits    int  not null default 0,  -- matches abandoned mid-game
	created_at timestamptz not null default now()
);

-- Every card this account has ever staked online. This is deliberately NOT a
-- full mirror of the local collection: cards only appear here the first time
-- they are actually risked in a match. First sighting is validated against
-- card_defs; from then on the row is a fingerprint, and a card that comes back
-- with different arrows or with stats that went DOWN is rejected outright.
-- Stats going up is allowed - that is level-up (BattleScene's end-of-match
-- pass), and the caps still bound it.
create table if not exists player_cards (
	user_id   uuid not null references profiles on delete cascade,
	unique_id bigint not null,
	def_id    int  not null references card_defs,
	atk       int  not null,
	pdef      int  not null,
	mdef      int  not null,
	atype     int  not null,
	arrows    int  not null,  -- 8-bit mask, MatchState.arrow_mask order
	primary key (user_id, unique_id)
);

-- Display names are unique and are never changed once chosen: the game asks
-- for one when a save slot is created and offers no rename. Deleting the save
-- deletes the profile, which frees the name again.
--
-- Case SENSITIVE, so "Test" and "test" are two different players. That is a
-- deliberate choice, not an oversight: it keeps the rule to a plain equality
-- the player can verify by looking, at the cost of allowing near-identical
-- names to coexist.
--
-- The rename below runs first and only ever does anything once: accounts made
-- before this rule existed can already share a name, and the index cannot be
-- built until they don't. The oldest keeps the name; the others get a number.
with dupes as (
	select id, row_number() over (partition by name order by created_at, id) as n
	from profiles
)
update profiles p set name = p.name || ' ' || d.n
from dupes d where d.id = p.id and d.n > 1;

drop index if exists profiles_name_unique;
create unique index if not exists profiles_name_unique on profiles (name);

-- Cards this account has lost to somebody else. player_cards alone can't
-- express this: losing a card moves its row to the winner, leaving no trace,
-- so a modified client could simply re-stake the card it just lost and
-- mp_validate_deck would happily register it again as a first sighting. A
-- unique_id is never reissued within a save slot (CardManager's counter only
-- goes up), so a name on this list is permanently spent.
create table if not exists lost_cards (
	user_id   uuid not null references profiles on delete cascade,
	unique_id bigint not null,
	lost_at   timestamptz not null default now(),
	primary key (user_id, unique_id)
);

-- -------------------------------------------------------------- matchmaking

-- At most one queue entry per account (the primary key enforces it).
create table if not exists queue (
	user_id    uuid primary key references profiles on delete cascade,
	power      int not null,
	deck       jsonb not null,
	created_at timestamptz not null default now()
);

create index if not exists queue_power_idx on queue (power);

do $$ begin
	create type mp_status as enum ('active', 'done', 'void');
exception when duplicate_object then null;
end $$;

create table if not exists matches (
	id           uuid primary key default gen_random_uuid(),
	p0           uuid not null references profiles on delete cascade,
	p1           uuid not null references profiles on delete cascade,
	seed         bigint not null,
	deck0        jsonb not null,
	deck1        jsonb not null,
	first_player int not null,  -- 0 = p0 moves first
	status       mp_status not null default 'active',
	turn         int not null default 0,
	deadline     timestamptz not null,
	result       int,           -- winner slot: 0, 1, or -1 for a draw
	stolen       jsonb,
	created_at   timestamptz not null default now(),
	ended_at     timestamptz
);

create index if not exists matches_active_idx on matches (p0, p1) where status = 'active';

-- The lockstep channel. Both players write a row per turn index: the mover
-- writes the move itself, the observer writes the same index with its own hash
-- once it has replayed that move. Two rows per index, one per player, and the
-- hashes have to agree.
create table if not exists moves (
	match_id   uuid not null references matches on delete cascade,
	idx        int  not null,
	user_id    uuid not null references profiles on delete cascade,
	payload    jsonb not null,
	state_hash text not null,
	score0     int not null default 0,  -- board control, agreed the same way
	score1     int not null default 0,
	created_at timestamptz not null default now(),
	primary key (match_id, idx, user_id)
);

alter table card_defs    enable row level security;
alter table profiles     enable row level security;
alter table player_cards enable row level security;
alter table lost_cards   enable row level security;
alter table queue        enable row level security;
alter table matches      enable row level security;
alter table moves        enable row level security;
-- No policies on purpose: only the SECURITY DEFINER functions below get in.

-- ------------------------------------------------------------------ helpers

-- Is this name still free? Deliberately callable WITHOUT a session: the game
-- asks while the player is still typing a name for a brand-new save slot,
-- before any account for it exists.
create or replace function mp_name_available(p_name text)
returns boolean
language sql stable security definer set search_path = public as $$
	select trim(p_name) <> ''
		and not exists (select 1 from profiles where name = trim(p_name))
$$;

-- Creates the profile row on first contact. The client calls this right after
-- the player picks a name for a new save slot, which is what reserves it.
--
-- An existing profile is returned untouched: names are chosen once and there
-- is no rename, so a second call with a different name is ignored rather than
-- silently taking a name away from whoever holds it.
create or replace function mp_profile_ensure(p_name text)
returns profiles
language plpgsql security definer set search_path = public as $$
declare
	v_row profiles;
begin
	if auth.uid() is null then
		raise exception 'not authenticated';
	end if;

	select * into v_row from profiles where id = auth.uid();
	if found then
		return v_row;
	end if;

	if trim(coalesce(p_name, '')) = '' then
		raise exception 'a name is required';
	end if;
	if not mp_name_available(p_name) then
		raise exception 'the name "%" is already taken', trim(p_name);
	end if;

	insert into profiles (id, name) values (auth.uid(), trim(p_name))
	returning * into v_row;
	return v_row;
end $$;

-- Deleting a save deletes its online account, which frees the name for
-- anybody else. Everything hanging off the profile - cards, lost-card ledger,
-- queue entry, matches - goes with it through the foreign keys' cascade.
create or replace function mp_delete_account() returns void
language plpgsql security definer set search_path = public as $$
begin
	if auth.uid() is null then
		return;
	end if;
	delete from profiles where id = auth.uid();
end $$;

-- Standard Elo, K=32. s is 1 / 0.5 / 0 for win / draw / loss from a's side.
create or replace function mp_elo(p_a int, p_b int, p_s numeric)
returns int
language sql immutable as $$
	select p_a + round(32 * (p_s - 1.0 / (1.0 + power(10.0, (p_b - p_a) / 400.0))))::int
$$;

-- A match as the client wants it: the row plus both players' display names,
-- so the battle screen can put a real opponent's name on the scoreboard
-- instead of "CPU" without a second round trip.
create or replace function mp_match_json(p_match matches)
returns jsonb
language sql stable security definer set search_path = public as $$
	select to_jsonb(p_match) || jsonb_build_object(
		'p0_name', (select name from profiles where id = p_match.p0),
		'p1_name', (select name from profiles where id = p_match.p1))
$$;

-- Validates one deck against card_defs and the caller's stored fingerprints,
-- registering any card seen here for the first time. Raises on anything
-- illegal. Returns the deck's matchmaking power.
--
-- Deck json shape: [{"uid":int,"def":int,"atk":int,"pdef":int,"mdef":int,
--                    "atype":int,"arrows":int}, ... exactly 5 ...]
create or replace function mp_validate_deck(p_deck jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
	v_card   jsonb;
	v_def    card_defs;
	v_known  player_cards;
	v_power  int := 0;
	v_uids   bigint[] := '{}';
	v_uid    bigint;
begin
	if jsonb_typeof(p_deck) <> 'array' or jsonb_array_length(p_deck) <> 5 then
		raise exception 'deck must hold exactly 5 cards';
	end if;

	for v_card in select * from jsonb_array_elements(p_deck) loop
		v_uid := (v_card->>'uid')::bigint;
		if v_uid = any(v_uids) then
			raise exception 'the same card appears twice in the deck';
		end if;
		v_uids := v_uids || v_uid;

		if exists (select 1 from lost_cards where user_id = auth.uid() and unique_id = v_uid) then
			raise exception 'card % no longer belongs to you', v_uid;
		end if;

		select * into v_def from card_defs where def_id = (v_card->>'def')::int;
		if not found then
			raise exception 'unknown card definition %', v_card->>'def';
		end if;

		-- Caps only, for the reason spelled out on card_defs above.
		if (v_card->>'atk')::int  > v_def.atk_cap
		or (v_card->>'pdef')::int > v_def.pdef_cap
		or (v_card->>'mdef')::int > v_def.mdef_cap
		or (v_card->>'atk')::int  < 0
		or (v_card->>'pdef')::int < 0
		or (v_card->>'mdef')::int < 0 then
			raise exception 'card % has stats above its species cap', v_uid;
		end if;

		-- Attack type is either the species' own, or a level-up along the
		-- P/M -> X -> A ladder, never past the species' max.
		if (v_card->>'atype')::int <> v_def.atype_base
		and ((v_card->>'atype')::int < 2 or (v_card->>'atype')::int > v_def.atype_max) then
			raise exception 'card % has an impossible attack type', v_uid;
		end if;

		if (v_card->>'arrows')::int < 1 or (v_card->>'arrows')::int > 255 then
			raise exception 'card % has an impossible arrow mask', v_uid;
		end if;

		select * into v_known from player_cards
			where user_id = auth.uid() and unique_id = v_uid;

		if found then
			-- Arrows are fixed at creation and are the one property this
			-- server can't re-derive from the CSV, so they are pinned to
			-- whatever was registered the first time.
			if v_known.arrows <> (v_card->>'arrows')::int
			or v_known.def_id <> (v_card->>'def')::int then
				raise exception 'card % does not match its registered identity', v_uid;
			end if;
			if (v_card->>'atk')::int  < v_known.atk
			or (v_card->>'pdef')::int < v_known.pdef
			or (v_card->>'mdef')::int < v_known.mdef
			or (v_card->>'atype')::int < v_known.atype then
				raise exception 'card % lost stats since it was last seen', v_uid;
			end if;
			update player_cards set
				atk = (v_card->>'atk')::int,
				pdef = (v_card->>'pdef')::int,
				mdef = (v_card->>'mdef')::int,
				atype = (v_card->>'atype')::int
				where user_id = auth.uid() and unique_id = v_uid;
		else
			insert into player_cards (user_id, unique_id, def_id, atk, pdef, mdef, atype, arrows)
			values (auth.uid(), v_uid, (v_card->>'def')::int, (v_card->>'atk')::int,
				(v_card->>'pdef')::int, (v_card->>'mdef')::int,
				(v_card->>'atype')::int, (v_card->>'arrows')::int);
		end if;

		-- Stats only, no arrows: matches CardManager.deck_power.
		v_power := v_power + (v_card->>'atk')::int + (v_card->>'pdef')::int + (v_card->>'mdef')::int;
	end loop;

	return v_power;
end $$;

-- --------------------------------------------------------------- match flow

-- How long a player has to make their move before the other side can claim
-- the win. Long enough to absorb the coin-toss and battle animations the
-- player can't skip, short enough that waiting out somebody who has clearly
-- walked away isn't a chore. Mirrored client-side by
-- OnlineMatch.TURN_SECONDS, which drives the on-screen countdown - change
-- both together or the clock on screen stops matching the real one.
create or replace function mp_deadline() returns timestamptz
language sql stable as $$ select now() + interval '60 seconds' $$;

-- Joins the queue, or pairs up immediately if someone is waiting. Returns
-- {"status":"queued"} or {"status":"matched", "match": {...}}.
create or replace function mp_enqueue(p_deck jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	v_me    uuid := auth.uid();
	v_power int;
	v_opp   queue;
	v_match matches;
	v_first int;
begin
	if v_me is null then
		raise exception 'not authenticated';
	end if;
	if exists (select 1 from matches where status = 'active' and (p0 = v_me or p1 = v_me)) then
		raise exception 'you are already in a match';
	end if;

	v_power := mp_validate_deck(p_deck);

	-- Closest opponent by deck power, no tuned window to maintain: with a
	-- small player base a widening window would just reinvent "take whoever
	-- is closest" the slow way.
	select * into v_opp from queue
		where user_id <> v_me
		order by abs(power - v_power), created_at
		limit 1
		for update skip locked;

	if not found then
		insert into queue (user_id, power, deck) values (v_me, v_power, p_deck)
			on conflict (user_id) do update set power = excluded.power, deck = excluded.deck, created_at = now();
		return jsonb_build_object('status', 'queued', 'power', v_power);
	end if;

	delete from queue where user_id in (v_me, v_opp.user_id);

	-- The waiting player is p0 and moves first: a small, predictable reward
	-- for having sat in the queue, and it saves a coin flip nobody can audit.
	v_first := 0;
	insert into matches (p0, p1, seed, deck0, deck1, first_player, deadline)
	values (v_opp.user_id, v_me, (random() * 4294967295)::bigint, v_opp.deck, p_deck, v_first, mp_deadline())
	returning * into v_match;

	return jsonb_build_object('status', 'matched', 'match', mp_match_json(v_match));
end $$;

-- Polled by the matchmaking screen while queued, and used to recover a match
-- after a crash or a restart.
create or replace function mp_current_match()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	v_match matches;
begin
	select * into v_match from matches
		where status = 'active' and (p0 = auth.uid() or p1 = auth.uid())
		order by created_at desc limit 1;
	if not found then
		return jsonb_build_object('status', 'queued');
	end if;
	return jsonb_build_object('status', 'matched', 'match', mp_match_json(v_match));
end $$;

create or replace function mp_dequeue() returns void
language plpgsql security definer set search_path = public as $$
begin
	delete from queue where user_id = auth.uid();
end $$;

-- The referee. Records this player's view of turn p_idx and compares it with
-- the opponent's view of the same turn if that has already arrived.
--
-- p_payload is opaque to the server (the move the client made); the trust
-- comes from p_hash and p_score, which both clients compute independently
-- from their own simulation and which therefore can only agree if both ran
-- the same rules on the same state.
create or replace function mp_submit_move(
	p_match uuid, p_idx int, p_payload jsonb, p_hash text, p_score0 int, p_score1 int)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	v_me    uuid := auth.uid();
	v_match matches;
	v_other moves;
begin
	select * into v_match from matches where id = p_match for update;
	if not found or (v_match.p0 <> v_me and v_match.p1 <> v_me) then
		raise exception 'no such match';
	end if;
	if v_match.status <> 'active' then
		return jsonb_build_object('status', v_match.status::text);
	end if;

	insert into moves (match_id, idx, user_id, payload, state_hash, score0, score1)
	values (p_match, p_idx, v_me, p_payload, p_hash, p_score0, p_score1)
	on conflict do nothing;

	select * into v_other from moves
		where match_id = p_match and idx = p_idx and user_id <> v_me;

	if found and (v_other.state_hash <> p_hash
		or v_other.score0 <> p_score0 or v_other.score1 <> p_score1) then
		-- Somebody's simulation is not the real one. With two players there is
		-- no way to tell which, so nothing changes hands and both carry the
		-- void. The message stays vague on purpose: a cheater who learns
		-- exactly when they were caught learns how to avoid being caught.
		update matches set status = 'void', ended_at = now() where id = p_match;
		update profiles set voids = voids + 1 where id in (v_match.p0, v_match.p1);
		return jsonb_build_object('status', 'void');
	end if;

	update matches set turn = greatest(turn, p_idx), deadline = mp_deadline() where id = p_match;
	return jsonb_build_object('status', 'active');
end $$;

-- Turn-based, so the client polls this instead of holding a realtime socket.
create or replace function mp_fetch_moves(p_match uuid, p_after int)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	v_match matches;
begin
	select * into v_match from matches where id = p_match;
	if not found or (v_match.p0 <> auth.uid() and v_match.p1 <> auth.uid()) then
		raise exception 'no such match';
	end if;
	return jsonb_build_object(
		'status', v_match.status::text,
		'result', v_match.result,
		'stolen', v_match.stolen,
		'deadline', v_match.deadline,
		'moves', coalesce((
			select jsonb_agg(to_jsonb(m) order by m.idx)
			from moves m
			where m.match_id = p_match and m.idx > p_after and m.user_id <> auth.uid()
		), '[]'::jsonb));
end $$;

-- Called by the WINNER only (or by either side on a draw, with an empty
-- steal list). The loser reads the verdict back through mp_fetch_moves and
-- applies it locally - one writer avoids two half-agreeing finalizations.
--
-- p_stolen: [{"from":<loser's unique_id>,"to":<the uid the winner filed it
-- under locally>}, ...]. The client renumbers a stolen card because unique_id
-- is only unique within one save slot, so the winner's collection may already
-- contain that number.
create or replace function mp_finalize(p_match uuid, p_stolen jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	v_me      uuid := auth.uid();
	v_match   matches;
	v_last    moves;
	v_winner  int;
	v_result  int;
	v_loser   uuid;
	v_win_id  uuid;
	v_entry   jsonb;
	v_allowed int;
	v_elo0    int;
	v_elo1    int;
	v_p0_elo  int;
	v_p1_elo  int;
begin
	select * into v_match from matches where id = p_match for update;
	if not found or (v_match.p0 <> v_me and v_match.p1 <> v_me) then
		raise exception 'no such match';
	end if;
	if v_match.status <> 'active' then
		return jsonb_build_object('status', v_match.status::text, 'result', v_match.result, 'stolen', v_match.stolen);
	end if;

	-- The score comes from the last turn both clients agreed on, so the server
	-- never has to know the rules to know who won.
	--
	-- Deliberately the last MUTUALLY CONFIRMED move, not simply the last one:
	-- the winner announces which card they are taking and finalizes in the
	-- same breath, so their own steal move is routinely still unconfirmed at
	-- this point. Demanding confirmation of the very last row made every
	-- payout lose that race, leaving the match stuck open forever.
	select m.* into v_last from moves m
		where m.match_id = p_match
		and exists (select 1 from moves o
			where o.match_id = m.match_id and o.idx = m.idx and o.user_id <> m.user_id)
		order by m.idx desc limit 1;
	if not found then
		raise exception 'the match has no state both players confirmed';
	end if;

	if v_last.score0 > v_last.score1 then
		v_winner := 0;
	elsif v_last.score1 > v_last.score0 then
		v_winner := 1;
	else
		v_winner := -1;
	end if;
	v_result := v_winner;

	if v_winner = -1 then
		v_allowed := 0;
	else
		v_win_id := case when v_winner = 0 then v_match.p0 else v_match.p1 end;
		v_loser  := case when v_winner = 0 then v_match.p1 else v_match.p0 end;
		if v_win_id <> v_me then
			raise exception 'only the winner finalizes a decided match';
		end if;
		-- A perfect (all 10 played cards owned) takes the whole deck; any
		-- other win takes exactly one. Same rule as the AI battles.
		v_allowed := case when greatest(v_last.score0, v_last.score1) >= 10 then 5 else 1 end;
	end if;

	if jsonb_array_length(coalesce(p_stolen, '[]'::jsonb)) <> v_allowed then
		raise exception 'this result allows exactly % stolen card(s)', v_allowed;
	end if;

	for v_entry in select * from jsonb_array_elements(coalesce(p_stolen, '[]'::jsonb)) loop
		-- The card has to have actually been staked by the loser in THIS
		-- match, not merely be something they own.
		if not exists (
			select 1 from jsonb_array_elements(
				case when v_winner = 0 then v_match.deck1 else v_match.deck0 end) d
			where (d->>'uid')::bigint = (v_entry->>'from')::bigint) then
			raise exception 'card % was not staked in this match', v_entry->>'from';
		end if;
		-- The winner tells us the number they filed the card under locally.
		-- An honest client never reuses one (CardManager's counter only goes
		-- up), so a clash means a broken or hostile client - refuse it plainly
		-- instead of surfacing a raw constraint violation.
		if exists (select 1 from player_cards
			where user_id = v_win_id and unique_id = (v_entry->>'to')::bigint) then
			raise exception 'card number % is already in use', v_entry->>'to';
		end if;
		update player_cards
			set user_id = v_win_id, unique_id = (v_entry->>'to')::bigint
			where user_id = v_loser and unique_id = (v_entry->>'from')::bigint;
		insert into lost_cards (user_id, unique_id)
			values (v_loser, (v_entry->>'from')::bigint)
			on conflict do nothing;
	end loop;

	select elo into v_p0_elo from profiles where id = v_match.p0;
	select elo into v_p1_elo from profiles where id = v_match.p1;
	if v_winner = 0 then
		v_elo0 := mp_elo(v_p0_elo, v_p1_elo, 1); v_elo1 := mp_elo(v_p1_elo, v_p0_elo, 0);
		update profiles set wins = wins + 1, elo = v_elo0 where id = v_match.p0;
		update profiles set losses = losses + 1, elo = v_elo1 where id = v_match.p1;
	elsif v_winner = 1 then
		v_elo0 := mp_elo(v_p0_elo, v_p1_elo, 0); v_elo1 := mp_elo(v_p1_elo, v_p0_elo, 1);
		update profiles set losses = losses + 1, elo = v_elo0 where id = v_match.p0;
		update profiles set wins = wins + 1, elo = v_elo1 where id = v_match.p1;
	else
		v_elo0 := mp_elo(v_p0_elo, v_p1_elo, 0.5); v_elo1 := mp_elo(v_p1_elo, v_p0_elo, 0.5);
		update profiles set draws = draws + 1, elo = v_elo0 where id = v_match.p0;
		update profiles set draws = draws + 1, elo = v_elo1 where id = v_match.p1;
	end if;

	update matches set status = 'done', result = v_result, stolen = p_stolen, ended_at = now()
		where id = p_match;

	return jsonb_build_object('status', 'done', 'result', v_result, 'stolen', p_stolen);
end $$;

-- Rage quit. Claimable by the player still sitting there once the abandoner's
-- clock runs out; the client also calls this straight away when it is told the
-- opponent closed the game, so nobody waits out the full timeout for nothing.
-- The winner still picks which card to take, through the normal end-of-match
-- screen, and files it with mp_claim_steal below.
create or replace function mp_claim_timeout(p_match uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	v_me     uuid := auth.uid();
	v_match  matches;
	v_loser  uuid;
	v_p0_elo int;
	v_p1_elo int;
begin
	select * into v_match from matches where id = p_match for update;
	if not found or (v_match.p0 <> v_me and v_match.p1 <> v_me) then
		raise exception 'no such match';
	end if;
	if v_match.status <> 'active' then
		return jsonb_build_object('status', v_match.status::text, 'result', v_match.result);
	end if;
	if now() < v_match.deadline then
		raise exception 'the opponent still has time left';
	end if;

	v_loser := case when v_match.p0 = v_me then v_match.p1 else v_match.p0 end;
	select elo into v_p0_elo from profiles where id = v_match.p0;
	select elo into v_p1_elo from profiles where id = v_match.p1;

	if v_match.p0 = v_me then
		update profiles set wins = wins + 1, elo = mp_elo(v_p0_elo, v_p1_elo, 1) where id = v_match.p0;
		update profiles set losses = losses + 1, quits = quits + 1, elo = mp_elo(v_p1_elo, v_p0_elo, 0) where id = v_match.p1;
		update matches set status = 'done', result = 0, ended_at = now() where id = p_match;
	else
		update profiles set wins = wins + 1, elo = mp_elo(v_p1_elo, v_p0_elo, 1) where id = v_match.p1;
		update profiles set losses = losses + 1, quits = quits + 1, elo = mp_elo(v_p0_elo, v_p1_elo, 0) where id = v_match.p0;
		update matches set status = 'done', result = 1, ended_at = now() where id = p_match;
	end if;

	return jsonb_build_object('status', 'done', 'result', case when v_match.p0 = v_me then 0 else 1 end, 'by_timeout', true);
end $$;

-- The single card a timeout winner takes. Separate from mp_finalize because a
-- timeout has no agreed final score to derive the stakes from.
create or replace function mp_claim_steal(p_match uuid, p_stolen jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	v_match matches;
	v_loser uuid;
	v_entry jsonb;
begin
	select * into v_match from matches where id = p_match for update;
	if not found or (v_match.p0 <> auth.uid() and v_match.p1 <> auth.uid()) then
		raise exception 'no such match';
	end if;
	if v_match.status <> 'done' or v_match.stolen is not null then
		raise exception 'nothing to claim on this match';
	end if;
	if (v_match.result = 0 and v_match.p0 <> auth.uid())
	or (v_match.result = 1 and v_match.p1 <> auth.uid()) then
		raise exception 'only the winner claims';
	end if;
	if jsonb_array_length(coalesce(p_stolen, '[]'::jsonb)) <> 1 then
		raise exception 'a timeout win takes exactly one card';
	end if;

	v_loser := case when v_match.result = 0 then v_match.p1 else v_match.p0 end;
	for v_entry in select * from jsonb_array_elements(p_stolen) loop
		if not exists (
			select 1 from jsonb_array_elements(
				case when v_match.result = 0 then v_match.deck1 else v_match.deck0 end) d
			where (d->>'uid')::bigint = (v_entry->>'from')::bigint) then
			raise exception 'card % was not staked in this match', v_entry->>'from';
		end if;
		if exists (select 1 from player_cards
			where user_id = auth.uid() and unique_id = (v_entry->>'to')::bigint) then
			raise exception 'card number % is already in use', v_entry->>'to';
		end if;
		update player_cards
			set user_id = auth.uid(), unique_id = (v_entry->>'to')::bigint
			where user_id = v_loser and unique_id = (v_entry->>'from')::bigint;
		insert into lost_cards (user_id, unique_id)
			values (v_loser, (v_entry->>'from')::bigint)
			on conflict do nothing;
	end loop;

	update matches set stolen = p_stolen where id = p_match;
	return jsonb_build_object('status', 'done', 'stolen', p_stolen);
end $$;

-- Voluntary surrender: window closed, or a stale match found still open when
-- the player next reaches the lobby.
--
-- This CLOSES the match rather than only nudging the deadline. The earlier
-- version left the win to be claimed by the other side through
-- mp_claim_timeout, which is fine while they are still sitting there and
-- useless once they have closed the game too - the match then stayed 'active'
-- forever and blocked the quitter from ever starting another one. Conceding
-- outright cannot be abused: it only ever costs the caller.
--
-- `stolen` is deliberately left null so the winner can still claim their one
-- card through mp_claim_steal whenever they next connect.
--
-- Dropped first because this used to return void: Postgres refuses to change
-- a function's return type through create-or-replace.
drop function if exists mp_abandon(uuid);

create or replace function mp_abandon(p_match uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	v_me     uuid := auth.uid();
	v_match  matches;
	v_p0_elo int;
	v_p1_elo int;
begin
	select * into v_match from matches where id = p_match for update;
	if not found or (v_match.p0 <> v_me and v_match.p1 <> v_me) then
		return jsonb_build_object('status', 'none');
	end if;
	if v_match.status <> 'active' then
		return jsonb_build_object('status', v_match.status::text, 'result', v_match.result);
	end if;

	select elo into v_p0_elo from profiles where id = v_match.p0;
	select elo into v_p1_elo from profiles where id = v_match.p1;

	if v_match.p0 = v_me then
		update profiles set losses = losses + 1, quits = quits + 1,
			elo = mp_elo(v_p0_elo, v_p1_elo, 0) where id = v_match.p0;
		update profiles set wins = wins + 1,
			elo = mp_elo(v_p1_elo, v_p0_elo, 1) where id = v_match.p1;
		update matches set status = 'done', result = 1, ended_at = now() where id = p_match;
		return jsonb_build_object('status', 'done', 'result', 1);
	else
		update profiles set losses = losses + 1, quits = quits + 1,
			elo = mp_elo(v_p1_elo, v_p0_elo, 0) where id = v_match.p1;
		update profiles set wins = wins + 1,
			elo = mp_elo(v_p0_elo, v_p1_elo, 1) where id = v_match.p0;
		update matches set status = 'done', result = 0, ended_at = now() where id = p_match;
		return jsonb_build_object('status', 'done', 'result', 0);
	end if;
end $$;

-- --------------------------------------------------------------- leaderboard

create or replace function mp_leaderboard(p_limit int default 50)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	v_rows jsonb;
	v_self jsonb;
begin
	-- is_self marks the caller's own row. The client used to locate itself by
	-- comparing the rank below against the row numbers here, which is wrong:
	-- the two rankings run over different populations (this list only counts
	-- players who have finished a match), so the numbers drift apart and the
	-- highlight landed on the wrong row - or past the end of the table.
	select coalesce(jsonb_agg(r order by r.rank), '[]'::jsonb) into v_rows from (
		select rank() over (order by elo desc, wins desc, id) as rank,
			name, elo, wins, losses, draws, quits, id = auth.uid() as is_self
		from profiles
		where wins + losses + draws > 0
		order by elo desc, wins desc, id
		limit greatest(1, least(p_limit, 200))
	) r;

	-- The caller's own standing, over that same played-at-least-once
	-- population so it agrees with the list above.
	select to_jsonb(r) into v_self from (
		select rank, name, elo, wins, losses, draws, quits from (
			select id, rank() over (order by elo desc, wins desc, id) as rank,
				name, elo, wins, losses, draws, quits
			from profiles
			where wins + losses + draws > 0
		) ranked where id = auth.uid()
	) r;

	return jsonb_build_object('top', v_rows, 'self', v_self);
end $$;

grant execute on function
	mp_profile_ensure(text), mp_match_json(matches), mp_delete_account(),
	mp_enqueue(jsonb), mp_dequeue(), mp_current_match(),
	mp_submit_move(uuid, int, jsonb, text, int, int), mp_fetch_moves(uuid, int),
	mp_finalize(uuid, jsonb), mp_claim_timeout(uuid), mp_claim_steal(uuid, jsonb),
	mp_abandon(uuid), mp_leaderboard(int)
to authenticated;

-- The only one a player without an account may call - they need it before
-- they have one.
grant execute on function mp_name_available(text) to anon, authenticated;
