defmodule LoPrice.PriceChecker do
  use PI
  alias LoPrice.{Repo, Monitor, Product, User, Bot}

  def check_prices do
    stream = Repo.stream(Monitor)

    Repo.transaction(fn ->
      stream
      |> Task.async_stream(fn %{id: monitor_id, product_id: product_id, user_id: user_id, target_price: target_price, price_history: price_history} = monitor ->
        product = Product.by_id(product_id)
        user = User.by_id(user_id)

        {retailer, permalink} = SberMarket.parse_product_url(product.url)
        store_ids = SberMarket.stores(retailer, user.city) |> SberMarket.ids() |> pi()

        last_price = List.last(price_history)

        store_ids
        |> Enum.each(fn store_id ->
          if sber_product = SberMarket.product(permalink, store_id) do
            pi(sber_product["name"])
            current_price = sber_product["offer"]["unit_price"] && Product.to_kop(sber_product["offer"]["unit_price"])

            if sber_product["offer"]["active"] && current_price && current_price != last_price do
              Monitor.update_price_history(monitor, current_price)

              if current_price < target_price do
                store = SberMarket.store(store_id)
                image_url = hd(sber_product["images"])["original_url"]
                unit = if(sber_product["offer"]["price_type"] == "per_package", do: "кг", else: nil)

                Bot.notify_about_price_change(user.telegram_user_id, product.name, store["name"], last_price, target_price, current_price, unit, product.url, image_url, monitor_id)
              end
            end
          end
        end)
      end, max_concurrency: 9)
      |> Stream.run()
    end)

  end
end
