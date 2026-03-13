defmodule Forgecast.Repo.Migrations.Initial do
    use Ecto.Migration

    def up do
        # ================================================================
        # Extensions
        # ================================================================

        execute "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE"
        execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

        # ================================================================
        # Users
        # ================================================================

        create table(:users) do
            add :github_id, :bigint, null: false
            add :username, :text, null: false
            add :display_name, :text
            add :avatar_url, :text
            add :email, :text

            timestamps()
        end

        create unique_index(:users, [:github_id])
        create unique_index(:users, [:username])

        # ================================================================
        # Sessions
        # ================================================================

        create table(:sessions) do
            add :token, :text, null: false
            add :user_id, references(:users, on_delete: :delete_all), null: false
            add :expires_at, :naive_datetime, null: false

            timestamps(updated_at: false)
        end

        create unique_index(:sessions, [:token])
        create index(:sessions, [:user_id])
        create index(:sessions, [:expires_at])

        # ================================================================
        # Preferences
        # ================================================================

        create table(:preferences) do
            add :user_id, references(:users, on_delete: :delete_all), null: false
            add :key, :text, null: false
            add :value, :jsonb, null: false

            timestamps()
        end

        create unique_index(:preferences, [:user_id, :key])
        create index(:preferences, [:user_id])

        # ================================================================
        # Repos
        #
        # fillfactor=85 leaves page headroom for HOT updates from the
        # scoring worker, which updates every active row every 30s.
        # Tuned autovacuum ensures dead tuples are cleaned before they
        # accumulate — the default 20% threshold is far too lax for a
        # table with millions of rows updated on a 30s cycle.
        # ================================================================

        create table(:repos) do
            add :platform, :text, null: false
            add :platform_id, :text, null: false
            add :name, :text, null: false
            add :owner, :text, null: false
            add :description, :text
            add :language, :text
            add :url, :text, null: false
            add :topics, {:array, :text}, default: []
            add :avatar_url, :text
            add :og_image_url, :text
            add :stars, :integer, null: false, default: 0
            add :forks, :integer, null: false, default: 0
            add :open_issues, :integer, null: false, default: 0
            add :score, :float, null: false, default: 0.0
            add :star_velocity, :float, null: false, default: 0.0
            add :fork_velocity, :float, null: false, default: 0.0
            add :active, :boolean, null: false, default: true
            add :mirrors, :jsonb, null: false, default: "[]"
            add :score_updated_at, :naive_datetime
            add :last_seen_at, :naive_datetime
            add :next_check_at, :naive_datetime
            add :enriched_at, :naive_datetime
            add :og_image_cached_at, :naive_datetime

            timestamps()
        end

        execute """
        ALTER TABLE repos SET (
            autovacuum_vacuum_scale_factor = 0.01,
            autovacuum_analyze_scale_factor = 0.02,
            autovacuum_vacuum_cost_delay = 2,
            fillfactor = 85
        )
        """

        create unique_index(:repos, [:platform, :platform_id])
        create index(:repos, [:platform])
        create index(:repos, [:language])
        create index(:repos, [:next_check_at])
        create index(:repos, [:last_seen_at])

        # -- Active partial indexes (hot read path for trending) --

        execute "CREATE INDEX repos_active_score_desc ON repos (score DESC) WHERE active = true"
        execute "CREATE INDEX repos_active_platform_score ON repos (platform, score DESC) WHERE active = true"
        execute "CREATE INDEX repos_active_language_score ON repos (language, score DESC) WHERE active = true"
        execute "CREATE INDEX repos_active_platform_language_score ON repos (platform, language, score DESC) WHERE active = true"
        execute "CREATE INDEX repos_active_stars_desc ON repos (stars DESC) WHERE active = true"
        execute "CREATE INDEX repos_active_star_velocity_desc ON repos (star_velocity DESC) WHERE active = true"

        # -- Keyset pagination tiebreaker indexes --
        # Row-value comparisons (score, id) use these composite indexes
        # for efficient cursor-based pagination without OFFSET.

        execute "CREATE INDEX repos_active_score_id_desc ON repos (score DESC, id DESC) WHERE active = true"
        execute "CREATE INDEX repos_active_stars_id_desc ON repos (stars DESC, id DESC) WHERE active = true"
        execute "CREATE INDEX repos_active_star_velocity_id_desc ON repos (star_velocity DESC, id DESC) WHERE active = true"
        execute "CREATE INDEX repos_active_forks_id_desc ON repos (forks DESC, id DESC) WHERE active = true"
        execute "CREATE INDEX repos_active_name_id_asc ON repos (name ASC, id ASC) WHERE active = true"
        execute "CREATE INDEX repos_active_language_id_asc ON repos (language ASC, id ASC) WHERE active = true"

        # -- Functional indexes for code paths --

        # Mirror.for_repos canonical owner/name lookup
        execute """
        CREATE INDEX repos_canonical_lookup ON repos (
            (lower(split_part(name, '/', 1)) || '/' || lower(split_part(name, '/', -1)))
        )
        """

        # Enricher: pick repos with NULL enriched_at
        execute "CREATE INDEX repos_unenriched ON repos (enriched_at) WHERE enriched_at IS NULL"

        # Image worker: repos needing OG image refresh
        execute "CREATE INDEX repos_og_image_refresh ON repos (og_image_cached_at, stars) WHERE og_image_url IS NOT NULL"

        # Score worker: stale score detection
        execute "CREATE INDEX repos_score_updated_at ON repos (score_updated_at ASC NULLS FIRST)"

        # Search: trgm on name/description/language
        execute """
        CREATE INDEX repos_search_trgm ON repos USING gin (
            (lower(name) || ' ' || coalesce(lower(description), '') || ' ' || coalesce(lower(language), ''))
            gin_trgm_ops
        )
        """

        # Search: GIN on topics array for unnest queries
        execute "CREATE INDEX repos_topics_gin ON repos USING gin (topics)"

        # Case-insensitive lookups
        execute "CREATE INDEX repos_lower_name ON repos (lower(name))"
        execute "CREATE INDEX repos_lower_language ON repos (lower(language))"

        # ================================================================
        # Snapshots (hypertable)
        #
        # Partitioned by inserted_at with 1-day chunks. The primary key
        # must include the partition column for TimescaleDB.
        #
        # Compression kicks in after 7 days — recent data stays in row
        # format for fast velocity calculations, older data compresses
        # by ~90% for storage efficiency.
        #
        # Retention policy drops chunks older than 90 days automatically,
        # replacing the manual Snapshot.Summarizer entirely.
        # ================================================================

        execute """
        CREATE TABLE snapshots (
            id BIGSERIAL NOT NULL,
            repo_id BIGINT NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
            stars INTEGER NOT NULL,
            forks INTEGER NOT NULL,
            open_issues INTEGER NOT NULL,
            inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (id, inserted_at)
        )
        """

        execute """
        SELECT create_hypertable(
            'snapshots',
            'inserted_at',
            chunk_time_interval => INTERVAL '1 day'
        )
        """

        execute "CREATE INDEX snapshots_repo_id ON snapshots (repo_id, inserted_at DESC)"

        execute """
        ALTER TABLE snapshots SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'repo_id',
            timescaledb.compress_orderby = 'inserted_at DESC, id DESC'
        )
        """

        execute "SELECT add_compression_policy('snapshots', INTERVAL '7 days')"
        execute "SELECT add_retention_policy('snapshots', INTERVAL '90 days')"

        # ================================================================
        # Events (hypertable)
        #
        # Partitioned by occurred_at with 1-day chunks. Includes both
        # the string platform_repo_id (for skeleton repo creation before
        # the repo row exists) and the integer repo_id FK (for efficient
        # joins after backfill).
        #
        # Compression after 3 days — the scoring worker only queries
        # the last 24h, so most event data is read-cold. Compressed
        # chunks still support queries, just not inserts.
        #
        # Retention policy drops chunks older than 30 days, replacing
        # the manual Event.Pruner entirely.
        #
        # Tuned autovacuum handles the high insert rate and keeps
        # uncompressed chunks lean.
        # ================================================================

        execute """
        CREATE TABLE events (
            id BIGSERIAL NOT NULL,
            platform TEXT NOT NULL,
            platform_repo_id TEXT NOT NULL,
            repo_id BIGINT REFERENCES repos(id) ON DELETE SET NULL,
            repo_name TEXT NOT NULL,
            event_type TEXT NOT NULL,
            occurred_at TIMESTAMPTZ NOT NULL,
            PRIMARY KEY (id, occurred_at)
        )
        """

        execute """
        SELECT create_hypertable(
            'events',
            'occurred_at',
            chunk_time_interval => INTERVAL '1 day'
        )
        """

        execute "CREATE INDEX events_repo_id ON events (repo_id, occurred_at DESC) WHERE repo_id IS NOT NULL"
        execute "CREATE INDEX events_repo_type_occurred ON events (repo_id, event_type, occurred_at) WHERE repo_id IS NOT NULL"
        execute "CREATE INDEX events_platform_repo ON events (platform, platform_repo_id, occurred_at)"
        execute "CREATE INDEX events_event_type_occurred ON events (event_type, occurred_at)"

        execute """
        ALTER TABLE events SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'repo_id, event_type',
            timescaledb.compress_orderby = 'occurred_at DESC, id DESC'
        )
        """

        execute "SELECT add_compression_policy('events', INTERVAL '3 days')"
        execute "SELECT add_retention_policy('events', INTERVAL '30 days')"

        execute """
        ALTER TABLE events SET (
            autovacuum_vacuum_scale_factor = 0.02,
            autovacuum_analyze_scale_factor = 0.05,
            autovacuum_vacuum_cost_delay = 2
        )
        """

        # ================================================================
        # Estimated count function for fast unfiltered pagination
        # ================================================================

        execute """
        CREATE OR REPLACE FUNCTION estimated_row_count(table_name text)
        RETURNS bigint AS $$
            SELECT GREATEST(reltuples::bigint, 0)
            FROM pg_class
            WHERE relname = table_name;
        $$ LANGUAGE sql STABLE
        """
    end

    def down do
        # Drop hypertables (cascades chunks, policies, compression)
        execute "DROP TABLE IF EXISTS events CASCADE"
        execute "DROP TABLE IF EXISTS snapshots CASCADE"
        execute "DROP TABLE IF EXISTS preferences CASCADE"
        execute "DROP TABLE IF EXISTS sessions CASCADE"
        execute "DROP TABLE IF EXISTS repos CASCADE"
        execute "DROP TABLE IF EXISTS users CASCADE"
        execute "DROP FUNCTION IF EXISTS estimated_row_count(text)"
        execute "DROP EXTENSION IF EXISTS pg_trgm"
        execute "DROP EXTENSION IF EXISTS timescaledb CASCADE"
    end
end
