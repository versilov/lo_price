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

  def add_monitor(product_url, telegram_user_id) do
    retailer = URI.parse(product_url).host |> retailer()

    html = HTTPoison.get!(product_url, [Connection: "keep-alive"],
      hackney: [
        pool: :default,
        ssl_options: [versions: [:"tlsv1.2"]]
      ]
    ).body

    price(html, retailer)
  end

  defp retailer("www.dns-shop.ru"), do: "dns"
  defp retailer("www.citilink.ru"), do: "citilink"
  defp retailer("mvideo.ru"), do: "mvideo"
  defp retailer("sbermarket.ru"), do: "sbermarket"

  def get_price("https://sbermarket.ru" <> _) do

  end

  def get_price(product_url) do
    retailer = URI.parse(product_url).host |> retailer()

    html = HTTPoison.get!(product_url, [Connection: "keep-alive"],
      hackney: [
        pool: :default,
        ssl_options: [versions: [:"tlsv1.2"]]
      ]
    ).body

    price(html, retailer)
  end

  defp price(html, "dns") do
    case Regex.scan(
             ~r/ga\(\"set\",\"dimension5\",([0-9]+)\)/,
             html
           ) do
        [] ->
          nil

        [[_, price]] ->
          price
    end
  end

  defp price(html, "citilink") do
    {:ok, document} = Floki.parse_document(html)
    Floki.find(document, "span[itemprop=price]")
    |> hd()
    |> (fn {_tag, [_, {"content", price}], _children} -> price end).()
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
      preload: [:product]
    )
    |> Repo.all()
  end

  def get_monitor(monitor_id),
    do:
      from(m in Monitor, left_join: p in assoc(m, :product), preload: [product: p])
      |> Repo.get!(monitor_id)

  def update_monitor(monitor_id, update_values) when is_list(update_values),
    do:
      from(
        m in Monitor,
        where: m.id == ^monitor_id
      )
      |> Repo.update_all(set: update_values)

  def set_monitor_target_price(user_id, target_price_message_id, target_price),
    do:
      from(
        m in Monitor,
        where: m.user_id == ^user_id and m.target_price_message_id == ^target_price_message_id,
        update: [
          set: [target_price: ^target_price, target_price_message_id: nil]
        ]
      )
      |> Repo.update_all([])

  def remove_monitor(monitor_id),
    do:
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

  defp create_or_update_monitor(
         user_id,
         product_id,
         current_price,
         target_price \\ nil,
         target_price_message_id \\ nil
       ) do
    case Monitor.by_user_and_product(user_id, product_id) do
      nil ->
        %Monitor{
          user_id: user_id,
          product_id: product_id,
          target_price: target_price || current_price,
          price_history: [current_price],
          target_price_message_id: target_price_message_id
        }
        |> Repo.insert!()

      monitor ->
        monitor
        |> Monitor.changeset(
          %{target_price_message_id: target_price_message_id}
          |> Monitor.maybe_update_price_history(monitor, current_price)
          |> maybe_add_target_price(target_price)
        )
        |> Repo.update!()
    end
  end

  defp maybe_add_target_price(attrs, nil), do: attrs

  defp maybe_add_target_price(attrs, target_price) when is_integer(target_price),
    do: Map.put(attrs, :target_price, target_price)
end
