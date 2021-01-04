defmodule LoPrice.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      LoPrice.Repo,
      # Start the Telemetry supervisor
      LoPriceWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: LoPrice.PubSub},
      # Start the Endpoint (http/https)
      LoPriceWeb.Endpoint,
      # Start a worker by calling: LoPrice.Worker.start_link(arg)
      # {LoPrice.Worker, arg},
      :hackney_pool.child_spec(:sbermarket, timeout: 63_000, max_connections: 108),
      ExGram,
      {LoPrice.Bot, [method: :polling, token: System.get_env("TELEGRAM_LO_PRICE_BOT_TOKEN")]},
      LoPrice.MonitorServer
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LoPrice.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    LoPriceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
