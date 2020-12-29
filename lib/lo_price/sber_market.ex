defmodule SberMarket do
  use PI
  use HTTPoison.Base

  @api_url "https://sbermarket.ru/api/"

  @impl HTTPoison.Base
  def process_url(url), do: @api_url <> url

  @impl HTTPoison.Base
  def process_request_options(opts),
    do: [
      hackney: [
        ssl_options: [versions: [:"tlsv1.2"]]
      ]
    ]

  @impl HTTPoison.Base
  def process_response_body(body) do
    Jason.decode!(body)
  rescue
    e in Jason.DecodeError ->
      msg = "Cannot decode MetroCC JSON: " <> e.data

      {:error, msg}
  end

  def product(permalink, store_id \\ "105") do
    get!("stores/#{store_id}/products/#{permalink}").body["product"]
  rescue
    e ->
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

  # Retailer can be: metro, lenta, alleya
  def stores(retailer \\ nil) do
    stores_cache()
    |> filter_by_retailer(retailer)
  rescue
    e ->
      nil
  end

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
      |> Enum.map(fn {city, count} -> city end)

  defp filter_by_retailer(stores, nil), do: stores

  defp filter_by_retailer(stores, retailer) when is_binary(retailer),
    do:
      stores
      |> Enum.filter(fn
        %{"retailer_slug" => ^retailer} -> true
        _ -> false
      end)

  defp stores_cache() do
    case FastGlobal.get(:sbermarket_stores) do
      nil ->
        stores = get!("stores").body["stores"]
        FastGlobal.put(:sbermarket_stores, stores)
        stores

      stores ->
        stores
    end
  end
end
