defmodule Forgecast.Application do
    @moduledoc """
    OTP application entry point. Starts the repo, HTTP server,
    event stream poller, enricher, pruner, session pruner, and
    platform pollers.
    """

    use Application
    require Logger

    @impl true
    def start(_type, _args) do
        configure_console_logger()
        setup_file_logger()

        Forgecast.Trending.init_cache()

        port = Application.get_env(:forgecast, :server)[:port] || 4000

        children =
            [
                Forgecast.Repo,
                {Task.Supervisor, name: Forgecast.TaskSupervisor},
                {Bandit, plug: Forgecast.Api.Router, port: port}
            ] ++ env_children()

        opts = [strategy: :one_for_one, name: Forgecast.Supervisor]
        Supervisor.start_link(children, opts)
    end

    defp configure_console_logger do
        :logger.update_handler_config(:default, :formatter,
            {:logger_formatter, %{
                template: [:time, " [", :level, "] ", :msg, "\n"],
                single_line: true
            }}
        )
    end

    defp setup_file_logger do
        log_dir = log_directory()

        case File.mkdir_p(log_dir) do
            :ok ->
                log_file = Path.join(log_dir, "forgecast.log")

                :logger.add_handler(:file_log, :logger_std_h, %{
                    level: :debug,
                    config: %{
                        file: String.to_charlist(log_file),
                        max_no_bytes: 10_485_760,
                        max_no_files: 5,
                        compress_on_rotate: true
                    },
                    formatter: {:logger_formatter, %{
                        template: [:time, ~c" [", :level, ~c"] ", :msg, ~c"\n"],
                        single_line: true
                    }}
                })

                Logger.info("[Application] File logging to #{log_file}")

            {:error, reason} ->
                Logger.warning("[Application] Could not create log directory #{log_dir}: #{inspect(reason)}, file logging disabled")
        end
    end

    defp log_directory do
        cond do
            System.get_env("LOG_DIR") ->
                System.get_env("LOG_DIR")

            File.dir?("/data") ->
                "/data/logs"

            true ->
                Path.expand("../../logs", __DIR__)
        end
    end

    defp env_children do
        cond do
            Application.get_env(:forgecast, :env) == :test -> []
            System.get_env("POLLER") == "false" -> []
            true ->
                [
                    Forgecast.Event.Poller,
                    Forgecast.Event.Enricher,
                    Forgecast.Event.Pruner,
                    Forgecast.Image.Worker,
                    Forgecast.Auth.SessionPruner,
                    Forgecast.Poller.Registry,
                    Forgecast.Poller.Supervisor
                ]
        end
    end
end
