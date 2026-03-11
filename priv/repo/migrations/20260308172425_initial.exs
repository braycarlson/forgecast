defmodule Forgecast.Repo.Migrations.Initial do
    use Ecto.Migration

    def change do
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

        create table(:sessions) do
            add :token, :text, null: false
            add :user_id, references(:users, on_delete: :delete_all), null: false
            add :expires_at, :naive_datetime, null: false

            timestamps(updated_at: false)
        end

        create unique_index(:sessions, [:token])
        create index(:sessions, [:user_id])
        create index(:sessions, [:expires_at])

        create table(:preferences) do
            add :user_id, references(:users, on_delete: :delete_all), null: false
            add :key, :text, null: false
            add :value, :jsonb, null: false

            timestamps()
        end

        create unique_index(:preferences, [:user_id, :key])
        create index(:preferences, [:user_id])

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
            add :last_seen_at, :naive_datetime
            add :next_check_at, :naive_datetime
            add :enriched_at, :naive_datetime
            add :og_image_cached_at, :naive_datetime

            timestamps()
        end

        create unique_index(:repos, [:platform, :platform_id])
        create index(:repos, [:platform])
        create index(:repos, [:language])
        create index(:repos, [:next_check_at])
        create index(:repos, [:last_seen_at])
        create index(:repos, [:og_image_cached_at])
        create index(:repos, ["lower(name)"], name: :repos_lower_name_index)
        create index(:repos, ["lower(language)"], name: :repos_lower_language_index)
        execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", "DROP EXTENSION IF EXISTS pg_trgm"

        execute(
            """
            CREATE INDEX repos_search_index ON repos USING gin (
                (lower(name) || ' ' || coalesce(lower(description), '') || ' ' || coalesce(lower(language), ''))
                gin_trgm_ops
            )
            """,
            "DROP INDEX IF EXISTS repos_search_index"
        )

        create table(:snapshots) do
            add :repo_id, references(:repos, on_delete: :delete_all), null: false
            add :stars, :integer, null: false
            add :forks, :integer, null: false
            add :open_issues, :integer, null: false

            timestamps(updated_at: false)
        end

        create index(:snapshots, [:repo_id])
        create index(:snapshots, [:inserted_at])
        create index(:snapshots, [:repo_id, :inserted_at])

        create table(:events) do
            add :platform, :text, null: false
            add :platform_repo_id, :text, null: false
            add :repo_name, :text, null: false
            add :event_type, :text, null: false
            add :occurred_at, :naive_datetime, null: false
        end

        create index(:events, [:platform, :platform_repo_id])
        create index(:events, [:occurred_at])
        create index(:events, [:event_type, :occurred_at])
        create index(:events, [:platform, :platform_repo_id, :occurred_at])
    end
end
