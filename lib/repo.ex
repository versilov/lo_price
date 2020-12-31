defmodule LoPrice.Repo do
  use Ecto.Repo,
    otp_app: :lo_price,
    adapter: Ecto.Adapters.Postgres
end
