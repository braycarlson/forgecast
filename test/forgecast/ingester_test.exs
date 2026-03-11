defmodule Forgecast.IngesterTest do
    use Forgecast.DataCase

    alias Forgecast.Platform.Result

    test "inserts a new repo and snapshot" do
        results = Forgecast.Ingester.ingest([
            %Result{
                platform: "github",
                platform_id: "999",
                name: "test/new-repo",
                owner: "test",
                description: "A test repo",
                language: "Elixir",
                stars: 42,
                forks: 5,
                open_issues: 3,
                topics: [],
                url: "https://github.com/test/new-repo",
                avatar_url: nil,
                og_image_url: nil
            }
        ])

        assert [{:ok, repo}] = results
        assert repo.platform == "github"
        assert repo.platform_id == "999"

        full_repo = Repo.one!(from r in Repository, where: r.platform_id == "999")
        assert full_repo.name == "test/new-repo"
        assert full_repo.stars == 42

        snapshots = Repo.all(from s in Snapshot, where: s.repo_id == ^full_repo.id)
        assert length(snapshots) == 1
        assert hd(snapshots).stars == 42
    end

    test "sets next_check_at on newly discovered repos" do
        now = NaiveDateTime.utc_now()

        Forgecast.Ingester.ingest([
            %Result{
                platform: "github",
                platform_id: "777",
                name: "test/check-repo",
                owner: "test",
                description: nil,
                language: "Elixir",
                stars: 10,
                forks: 1,
                open_issues: 0,
                topics: [],
                url: "https://github.com/test/check-repo",
                avatar_url: nil,
                og_image_url: nil
            }
        ])

        repo = Repo.one!(from r in Repository, where: r.platform_id == "777")
        assert repo.next_check_at != nil
        assert NaiveDateTime.compare(repo.next_check_at, now) == :gt
    end

    test "preserves next_check_at on re-discovery of existing repo" do
        scheduled = NaiveDateTime.add(NaiveDateTime.utc_now(), 7200) |> NaiveDateTime.truncate(:second)

        insert_repo!(%{
            platform: "github",
            platform_id: "666",
            name: "test/preserve-check",
            owner: "test",
            url: "https://github.com/test/preserve-check",
            next_check_at: scheduled
        })

        Forgecast.Ingester.ingest([
            %Result{
                platform: "github",
                platform_id: "666",
                name: "test/preserve-check",
                owner: "test",
                description: "Updated",
                language: "Elixir",
                stars: 20,
                forks: 2,
                open_issues: 1,
                topics: [],
                url: "https://github.com/test/preserve-check",
                avatar_url: nil,
                og_image_url: nil
            }
        ])

        repo = Repo.one!(from r in Repository, where: r.platform_id == "666")
        assert repo.description == "Updated"
        assert repo.stars == 20
        assert NaiveDateTime.compare(repo.next_check_at, scheduled) == :eq
    end

    test "updates existing repo on re-ingest" do
        original = %Result{
            platform: "github",
            platform_id: "888",
            name: "test/update-me",
            owner: "test",
            description: "Original",
            language: "Elixir",
            stars: 10,
            forks: 1,
            open_issues: 0,
            topics: [],
            url: "https://github.com/test/update-me",
            avatar_url: nil,
            og_image_url: nil
        }

        Forgecast.Ingester.ingest([original])

        Forgecast.Ingester.ingest([
            %Result{original | description: "Updated", stars: 20, forks: 2, open_issues: 1}
        ])

        repos = Repo.all(from r in Repository, where: r.platform_id == "888")
        assert length(repos) == 1
        assert hd(repos).description == "Updated"
        assert hd(repos).stars == 20

        snapshots = Repo.all(from s in Snapshot, where: s.repo_id == ^hd(repos).id)
        assert length(snapshots) == 2
    end

    test "batches multiple results in a single call" do
        results = Forgecast.Ingester.ingest([
            %Result{
                platform: "github",
                platform_id: "101",
                name: "test/batch-1",
                owner: "test",
                description: "First",
                language: "Elixir",
                stars: 10,
                forks: 1,
                open_issues: 0,
                topics: [],
                url: "https://github.com/test/batch-1",
                avatar_url: nil,
                og_image_url: nil
            },
            %Result{
                platform: "github",
                platform_id: "102",
                name: "test/batch-2",
                owner: "test",
                description: "Second",
                language: "Rust",
                stars: 20,
                forks: 2,
                open_issues: 1,
                topics: [],
                url: "https://github.com/test/batch-2",
                avatar_url: nil,
                og_image_url: nil
            }
        ])

        assert length(results) == 2
        assert Enum.all?(results, &match?({:ok, _}, &1))

        total_repos = Repo.aggregate(from(r in Repository, where: r.platform_id in ["101", "102"]), :count)
        assert total_repos == 2

        total_snapshots = Repo.aggregate(Snapshot, :count)
        assert total_snapshots == 2
    end

    test "does not create snapshot when metrics unchanged" do
        insert_repo!(%{
            platform: "github",
            platform_id: "555",
            name: "test/unchanged",
            owner: "test",
            url: "https://github.com/test/unchanged",
            stars: 50,
            forks: 5,
            open_issues: 2
        })
        |> insert_snapshot!(%{stars: 50, forks: 5, open_issues: 2})

        Forgecast.Ingester.ingest([
            %Result{
                platform: "github",
                platform_id: "555",
                name: "test/unchanged",
                owner: "test",
                description: "Same stats",
                language: "Go",
                stars: 50,
                forks: 5,
                open_issues: 2,
                topics: [],
                url: "https://github.com/test/unchanged",
                avatar_url: nil,
                og_image_url: nil
            }
        ])

        repo = Repo.one!(from r in Repository, where: r.platform_id == "555")
        snapshots = Repo.all(from s in Snapshot, where: s.repo_id == ^repo.id)
        assert length(snapshots) == 1
    end
end
