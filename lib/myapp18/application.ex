defmodule Myapp18.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Myapp18Web.Telemetry,
      Myapp18.Repo,
      {DNSCluster, query: Application.get_env(:myapp18, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Myapp18.PubSub},
      # Start a worker by calling: Myapp18.Worker.start_link(arg)
      # {Myapp18.Worker, arg},
      # Start to serve requests, typically the last entry
      Myapp18Web.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Myapp18.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Myapp18Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
