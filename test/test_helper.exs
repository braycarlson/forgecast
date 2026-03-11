ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Forgecast.Repo, :manual)

Mox.defmock(Forgecast.MockPlatform, for: Forgecast.Platform)
