defmodule LoPrice.Core do
  import Ecto.Query
  alias LoPrice.{Repo, User, Product, Monitor}

  def create_or_update_user(telegram_user_id, attrs) do
    case User.by_telegram_id(telegram_user_id) do
      nil ->
        %User{}
        |> User.changeset(Map.merge(attrs, %{telegram_user_id: telegram_user_id}))
        |> Repo.insert!()

      user ->
        user
        |> User.changeset(attrs)
        |> Repo.update!()
    end
  end

  def create_or_update_product_and_monitor(product_url, product_name, retailer, user_id, price) do
    product = find_or_create_product(product_url, product_name, retailer)
    create_or_update_monitor(user_id, product.id, price)
  end

  def user_monitors(telegram_user_id) do
    user = User.by_telegram_id(telegram_user_id)

    from(m in Monitor,
      where: m.user_id == ^user.id,
      left_join: product in assoc(m, :product),
      preload: [:product])
    |> Repo.all()
  end

  def get_monitor(monitor_id), do:
    from(m in Monitor, left_join: p in assoc(m, :product), preload: [product: p])
    |> Repo.get!(monitor_id)

  def update_monitor(monitor_id, update_values) when is_list(update_values), do:
    from(
      m in Monitor,
      where: m.id == ^monitor_id
    )
    |> Repo.update_all(set: update_values)

  def set_monitor_target_price(user_id, target_price_message_id, target_price), do:
    from(
      m in Monitor,
      where: m.user_id == ^user_id and m.target_price_message_id == ^target_price_message_id,
      update: [
        set: [target_price: ^target_price, target_price_message_id: nil]
      ]
    )
    |> Repo.update_all([])


  def remove_monitor(monitor_id), do:
    Repo.get!(Monitor, monitor_id)
    |> Repo.delete!()

  defp find_or_create_product(url, name, retailer) do
    case Product.by_url(url) do
      nil ->
        %Product{}
        |> Product.changeset(%{url: url, retailer: retailer, name: name})
        |> Repo.insert!()

      product ->
        product
    end
  end

  defp create_or_update_monitor(user_id, product_id, current_price, target_price \\ nil, target_price_message_id \\ nil) do
    case Monitor.by_user_and_product(user_id, product_id) do
      nil ->
        %Monitor{user_id: user_id, product_id: product_id,
                 target_price: target_price || current_price, price_history: [current_price],
                  target_price_message_id: target_price_message_id}
        |> Repo.insert!()

      monitor ->
        monitor
        |> Monitor.changeset(%{target_price_message_id: target_price_message_id}
                             |> Monitor.maybe_update_price_history(monitor, current_price)
                             |> maybe_add_target_price(target_price)
                             )
        |> Repo.update!()
    end
  end

  defp maybe_add_target_price(attrs, nil), do: attrs
  defp maybe_add_target_price(attrs, target_price) when is_integer(target_price), do: Map.put(attrs, :target_price, target_price)
end
