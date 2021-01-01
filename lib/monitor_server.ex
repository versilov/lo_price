defmodule LoPrice.MonitorServer do
  use GenServer

  alias LoPrice.{Bot, PriceChecker}

  use PI

  @fish_permalinks [
    # Metro
    "losos-okhlazhdiennyi-5-slash-6",
    "losos-okhlazhdiennyi-7-8",
    "losos-atlantichieskii-potroshienyi-s-gholovoi-okhlazhdiennyi-6-7",
    "losos-murmansk-okhlazhdiennyi-4-slash-5",
    "losos-murmansk-okhlazhdiennyi-3-slash-4-5",
    "losos-murmansk-okhlazhdiennyi-5-slash-6",
    "losos-okhlazhdiennyi-6-7-10",
    "foriel-okhlazhdiennaia-3-4",
    "foriel-murmanskaia-okhlazhdiennaia-1-3-kgh",
    "foriel-2-slash-3-potroshiennaia-okhlazhdiennaia",
    "forel-morskaya-ohlazhdennaya-razmer-4-5-1-kg",
    "forel-rok-steyk-ohlazhdennaya-1-kg",
    "losos-stieik-okhlazhdiennyi",
    "losos-murmanskiy-steyk-ohlazhdennyy-1-kg",
    # Lenta
    "losos-atlantichieskii-s-gholovoi-okhlazhdiennyi",
    "losos-s-gholovoi-okhlazhdiennaia",
    "losos-atlantichieskii-stieik-okhlazhdiennyi",
    "forel-morskaya-potroshenaya-s-golovoy-ohlazhdennaya-4-kg",
    "foriel-okhlazhdiennaia-s-gholovoi-potroshienaia"
  ]
  @stores [105, 118, 162, 163, 319]
  @acceptable_price_per_kg 700.0
  @telegram_chat_id -1_001_481_233_822

  # API
  def start_link(_) do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  # Callbacks
  def init(_) do
    stores = SberMarket.stores_by_id()

    # Load empty products
    products =
      @stores
      |> Enum.map(fn store_id ->
        {store_id,
         Enum.map(@fish_permalinks, fn permalink ->
           {permalink, %{"offer" => %{}}}
         end)
         |> Map.new()}
      end)
      |> Map.new()

    send(self(), :monitor)
    send(self(), :monitor_predefined)

    {:ok, {products, stores}}
  end

  def handle_info(:monitor_predefined, {products, stores}) do
    products =
      products
      |> Enum.map(fn {store_id, store_products} ->
        {store_id, monitor_store_products(store_id, store_products, stores)}
      end)

    Process.send_after(self(), :monitor_predefined, 3600 * 1_000)

    {:noreply, {products, stores}}
  end

  def handle_info(:monitor, state) do
    PriceChecker.check_prices()

    Process.send_after(self(), :monitor, 3500 * 1_000)

    {:noreply, state}
  end

  defp monitor_store_products(store_id, products, stores) do
    products
    |> Enum.map(fn {permalink, product} ->
      {permalink, check_product_price(permalink, store_id, product, stores)}
    end)
  end

  defp check_product_price(permalink, store_id, product, stores) do
    fresh_product = SberMarket.product(permalink, store_id)

    if fresh_product do
      if fresh_product["offer"]["active"] &&
           fresh_product["offer"]["unit_price"] < @acceptable_price_per_kg &&
           (fresh_product["offer"]["active"] != product["offer"]["active"] ||
              fresh_product["offer"]["unit_price"] != product["offer"]["unit_price"]) do

        store_name = stores[store_id] && stores[store_id]["name"]
        retailer = stores[store_id] && stores[store_id]["retailer_slug"]

        image_url = hd(fresh_product["images"])["original_url"]
        product_url = "https://sbermarket.ru/#{retailer}/#{permalink}"

        Bot.notify_about_price_change(@telegram_chat_id, fresh_product["name"], store_name, product["offer"]["unit_price"], @acceptable_price_per_kg, fresh_product["offer"]["unit_price"], product_url, image_url)

        product
      end

      fresh_product
    else
      product
    end
  end


end
