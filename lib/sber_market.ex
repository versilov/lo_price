defmodule SberMarket do
  use PI
  use HTTPoison.Base

  @api_url "https://sbermarket.ru/api/"

  @impl HTTPoison.Base
  def process_url(url), do: @api_url <> url

  @impl HTTPoison.Base
  def process_request_options(opts),
    do:
      opts ++
        [
          hackney: [
            pool: :sbermarket,
            ssl_options: [versions: [:"tlsv1.2"]]
          ]
        ]

  @impl HTTPoison.Base
  def process_request_headers(headers), do: headers ++ [Connection: "keep-alive"]

  @impl HTTPoison.Base
  def process_request_body(""), do: ""
  def process_request_body(body), do: Jason.encode!(body)

  @impl HTTPoison.Base
  def process_response_body(body) do
    Jason.decode!(body)
  rescue
    e in Jason.DecodeError ->
      msg = "Cannot decode SberMarket JSON: " <> e.data

      {:error, msg}
  end

  def login(email, password) do
    %{body: %{"csrf_token" => token}, headers: headers} =
      post!(
        "user_sessions",
        %{user: %{email: email, password: password}},
        "Content-Type": "application/json"
      )

    [AuthenticityToken: token, Cookie: get_cookie(headers, "remember_user_token")]
  rescue
    _ ->
      nil
  end

  defp get_cookie(headers, name),
    do:
      headers
      |> Enum.find(fn
        {key, value} ->
          String.match?(key, ~r/\Aset-cookie\z/i) && String.match?(value, ~r/\A#{name}=/i)
      end)
      |> elem(1)

  def product(permalink, store_id \\ "105") do
    get!("stores/#{store_id}/products/#{permalink}").body["product"]
  rescue
    _ ->
      nil
  end

  def product_unit_price(permalink, store_id \\ "105"),
    do:
      case(product(permalink, store_id),
        do:
          (
            %{"offer" => %{"unit_price" => unit_price}} -> unit_price
            _ -> nil
          )
      )

  def search(store_id, query, page \\ 1, per_page \\ 24) do
    get!("v2/products?sid=#{store_id}&per_page=#{per_page}&page=#{page}&q=#{query}").body[
      "products"
    ] || []
  rescue
    _ ->
      []
  end

  def favorites(auth_headers, per_page \\ 1_000),
    do: get!("favorites_list/items?per_page=#{per_page}", auth_headers).body["items"]



  def add_to_favorites(auth_headers, product_sku),
    do:
      post!(
        "favorites_list/items",
        %{item: %{product_sku: product_sku}},
        auth_headers ++ ["Content-Type": "application/json"]
      ).body["item"]

  def remove_from_favorites(auth_headers, product_sku),
    do: delete!("favorites_list/items/#{product_sku}", auth_headers).body["item"]

  def permalink_from_sku(permalink_or_sku) do
    case Integer.parse(permalink_or_sku) do
      # It's not integer value of SKU, probably, it's already permalink
      :error ->
        permalink_or_sku

      {sku, _} ->
        case add_to_favorites(master_account_auth_headers(), sku) do
          %{"product" => %{"permalink" => permalink}} ->
            add_to_permalinks_cache(sku, permalink)
            permalink

          _ ->
            permalinks_cache()[sku]
        end
    end
  end

  defp master_account_auth_headers() do
    case FastGlobal.get(:sbermarket_auth_headers) do
      nil ->
        headers =
          login(
            System.get_env("SBERMARKET_MASTER_LOGIN"),
            System.get_env("SBERMARKET_MASTER_PASSWORD")
          )

        FastGlobal.put(:sbermarket_auth_headers, headers)
        headers

      headers ->
        headers
    end
  end

  def permalinks_cache(),
    do: FastGlobal.get(:sbermarket_permalinks) || load_permalinks_cache()

  defp load_permalinks_cache() do
    permalinks =
      favorites(master_account_auth_headers())
      |> Enum.map(fn %{"product" => %{"sku" => sku, "permalink" => permalink}} ->
        {sku, permalink}
      end)
      |> Map.new()

    FastGlobal.put(:sbermarket_permalinks, permalinks)
    permalinks
  end

  defp add_to_permalinks_cache(sku, permalink), do:
    FastGlobal.put(:sbermarket_permalinks, Map.put(permalinks_cache(), "#{sku}", permalink))

  def search_suggestions(store_id, query) do
    get!("stores/#{store_id}/search_suggestions?q=#{query}").body["suggestion"]["offers"] || []
  rescue
    _ ->
      []
  end

  # Returns closest stores, one of each brand.
  # E.g. for Samara returns one Metro, one Auchan, one Lenta and one Beethoven.
  def stores(%{latitude: lat, longitude: lon}) do
    get!("v2/stores?lon=#{lon}&lat=#{lat}").body["stores"]
  rescue
    _ ->
      []
  end

  # Retailer can be: metro, lenta, alleya
  def stores(retailer \\ nil, city \\ nil) do
    stores_cache()
    |> filter_stores(retailer, city)
  rescue
    _ ->
      nil
  end

  def ids(list), do: Enum.map(list, &(&1["id"] || &1[:id]))

  def store(store_id) when is_integer(store_id),
    do:
      stores()
      |> Enum.find(&(&1["id"] == store_id))

  def stores_by_id(retailer \\ nil),
    do:
      stores(retailer)
      |> Enum.map(fn %{"id" => store_id} = store ->
        {store_id, store}
      end)
      |> Map.new()

  @doc """
  Returns cities names, order by number of stores of the given retailer in each city
  """
  def stores_cities(retailer \\ nil),
    do:
      stores(retailer)
      |> Enum.map(&String.trim(&1["location"]["city"]))
      |> Enum.reject(&(&1 == ""))
      |> Enum.frequencies()
      |> Enum.sort(fn {_city1, count1}, {_city2, count2} -> count1 >= count2 end)
      |> Enum.map(fn {city, _count} -> city end)

  defp filter_stores(stores, retailer, city),
    do:
      stores
      |> filter_by_retailer(retailer)
      |> filter_by_city(city)

  defp filter_by_retailer(stores, nil), do: stores

  defp filter_by_retailer(stores, retailer) when is_binary(retailer),
    do:
      stores
      |> Enum.filter(fn
        %{"retailer_slug" => ^retailer} -> true
        _ -> false
      end)

  defp filter_by_city(stores, nil), do: stores

  defp filter_by_city(stores, city) when is_binary(city),
    do:
      stores
      |> Enum.filter(fn
        %{"location" => %{"city" => ^city}} -> true
        _ -> false
      end)

  defp stores_cache() do
    case FastGlobal.get(:sbermarket_stores) do
      nil ->
        # Put empty list to mark loading in progress
        FastGlobal.put(:sbermarket_stores, [])
        IO.puts("Loading stores...")
        stores = get!("stores").body["stores"]
        IO.puts("Done loading stores.")
        FastGlobal.put(:sbermarket_stores, stores)
        stores

      # Loading in progress, don't start new one
      [] ->
        :timer.sleep(1_000)
        stores_cache()

      stores ->
        stores
    end
  end

  def parse_product_url(url),
    do:
      url
      |> URI.parse()
      |> Map.get(:path)
      |> String.split("/", trim: true)
      |> List.to_tuple()

  def find_lowest_price_in_stores(permalink, store_ids) when is_list(store_ids),
    do:
      store_ids
      |> Enum.map(&product(permalink, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.min_by(& &1["offer"]["unit_price"], fn -> nil end)

  def unit(sber_product), do: if(sber_product["offer"]["price_type"] == "per_package", do: "кг", else: nil)
end
