# In this file, we load production configuration and secrets
# from environment variables. You can also hardcode secrets,
# although such is generally not recommended and you have to
# remember to add this file to your .gitignore.
use Mix.Config

database_url =
  System.get_env("LO_PRICE_DATABASE_URL") ||
    raise """
    environment variable LO_PRICE_DATABASE_URL is missing.
    For example: ecto://USER:PASS@HOST/DATABASE
    """

config :lo_price, LoPrice.Repo,
  # ssl: true,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

secret_key_base =
  System.get_env("LO_PRICE_SECRET_KEY_BASE") ||
    raise """
    environment variable LO_PRICE_SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

config :lo_price, LoPriceWeb.Endpoint,
  http: [
    port: String.to_integer(System.get_env("PORT") || "3333"),
    transport_options: [socket_opts: [:inet6]]
  ],
  server: true,
  secret_key_base: secret_key_base

# ## Using releases (Elixir v1.9+)
#
# If you are doing OTP releases, you need to instruct Phoenix
# to start each relevant endpoint:
#
#     config :lo_price, LoPriceWeb.Endpoint, server: true
#
# Then you can assemble a release by calling `mix release`.
# See `mix help release` for more information.
