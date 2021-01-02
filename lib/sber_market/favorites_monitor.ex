defmodule SberMarket.FavoritesMonitor do
  import Ecto.Query

  alias LoPrice.{User, Repo, Bot}
  def monitor() do
    from(u in User, where: not is_nil(fragment("extra->>'sbermarket_auth'")))
    |> Repo.all()
    |> Enum.each(fn %{id: user_id, extra: %{"sbermarket_auth" => auth}} ->
      {email, password} = User.decode_credentials(auth)
      Bot.add_monitors_from_sbermarket_favorites(email, password, user_id)
    end)
  end
end
