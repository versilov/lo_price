defmodule LoPrice.PriceChecker do
  use PI
  alias LoPrice.{Repo, Monitor, Product, User, Bot}
  import Ecto.Query

  def check_prices(user_id \\ nil, group_notifications \\ false) do
    Repo.transaction(fn ->
      stream(user_id)
      |> Task.async_stream(fn %{id: monitor_id, product_id: product_id, user_id: user_id, target_price: target_price, price_history: price_history} = monitor ->
        product = Product.by_id(product_id)
        user = User.by_id(user_id)

        {retailer, permalink} = SberMarket.parse_product_url(product.url)
        store_ids = SberMarket.stores(retailer, user.city) |> SberMarket.ids() |> pi()

        last_price = List.last(price_history)


        if sber_product = SberMarket.find_lowest_price_in_stores(permalink, store_ids) do
          current_price = sber_product["offer"]["unit_price"] && Product.to_kop(sber_product["offer"]["unit_price"])

          if sber_product["offer"]["active"] && current_price && current_price != last_price do
            Monitor.update_price_history(monitor, current_price)

            if current_price < target_price do
              store = SberMarket.store(sber_product["offer"]["store_id"])
              image_url = hd(sber_product["images"])["original_url"]
              unit = if(sber_product["offer"]["price_type"] == "per_package", do: "кг", else: nil)

              if group_notifications do
                %{telegram_user_id: user.telegram_user_id, product_name: product.name,
                  store_name: store["name"], last_price: last_price, target_price: target_price,
                  current_price: current_price, unit: unit, product_url: product.url,
                  image_url: image_url, monitor_id: monitor_id}
              else
                Bot.notify_about_price_change(user.telegram_user_id, product.name, store["name"], last_price, target_price, current_price, unit, product.url, image_url, monitor_id)
              end
            end
          end
        end
      end, max_concurrency: 9)
      |> Enum.to_list()
    end)
    |> maybe_send_notifications_groups(group_notifications)
  end

  defp stream(nil), do: Repo.stream(Monitor)
  defp stream(user_id) when is_integer(user_id), do:
    Repo.stream(from(m in Monitor, where: m.user_id == ^user_id))

  defp maybe_send_notifications_groups(_, false), do: :ok
  defp maybe_send_notifications_groups({:ok, results}, true), do:
    results
    |> Enum.map(fn {:ok, result} -> result end)
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(& &1.telegram_user_id)
    |> Enum.each(fn {telegram_user_id, price_changes} ->
      Bot.notify_about_price_change_with_group(telegram_user_id, price_changes)
    end)
end
