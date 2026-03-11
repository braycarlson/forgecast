defmodule Forgecast.Api.RouterTest do
    use Forgecast.DataCase

    import Plug.Test

    @opts Forgecast.Api.Router.init([])

    test "GET /api/status returns repo and snapshot counts" do
        insert_repo!() |> insert_snapshot!()

        conn =
            conn(:get, "/api/status")
            |> Forgecast.Api.Router.call(@opts)

        assert conn.status == 200

        body = Jason.decode!(conn.resp_body)
        assert body["repos"] >= 1
        assert body["snapshots"] >= 1
    end

    test "GET /api/trending returns paginated results" do
        insert_repo!(%{language: "Elixir"}) |> insert_snapshot!(%{stars: 100})

        conn =
            conn(:get, "/api/trending?per_page=10")
            |> Forgecast.Api.Router.call(@opts)

        assert conn.status == 200

        body = Jason.decode!(conn.resp_body)
        assert is_list(body["items"])
        assert body["total"] >= 1
        assert body["page"] == 1
    end

    test "GET /api/trending filters by platform" do
        insert_repo!(%{platform: "github"}) |> insert_snapshot!()
        insert_repo!(%{platform: "gitlab"}) |> insert_snapshot!()

        conn =
            conn(:get, "/api/trending?platform=github")
            |> Forgecast.Api.Router.call(@opts)

        body = Jason.decode!(conn.resp_body)
        platforms = Enum.map(body["items"], & &1["platform"]) |> Enum.uniq()
        assert platforms == ["github"]
    end

    test "GET /api/filters returns platforms and languages" do
        insert_repo!(%{platform: "github", language: "Rust"}) |> insert_snapshot!()

        conn =
            conn(:get, "/api/filters")
            |> Forgecast.Api.Router.call(@opts)

        assert conn.status == 200

        body = Jason.decode!(conn.resp_body)
        assert "github" in body["platforms"]
        assert "Rust" in body["languages"]
    end

    test "GET /unknown returns 404" do
        conn =
            conn(:get, "/api/nope")
            |> Forgecast.Api.Router.call(@opts)

        assert conn.status == 404
    end
end
