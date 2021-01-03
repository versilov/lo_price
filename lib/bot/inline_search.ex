defmodule LoPrice.Bot.InlineSearch do
  alias LoPrice.{Product}
  alias ExGram.Model.{InlineQueryResultPhoto, InlineQueryResultArticle, InputTextMessageContent}

  defmacro __using__(_) do
    quote do
      def handle({:inline_query, %{query: query, offset: offset}}, context), do:
        LoPrice.Bot.InlineSearch.handle_inline_query(query, offset, context)
    end
  end

  def handle_inline_query(query, offset, context) do
    page = case offset do
        "" -> 1
        num -> String.to_integer(num)
      end

    suggestions =
      SberMarket.search(105, query, page, 7)
      |> Enum.reject(& &1["images"] == [])
      |> Enum.map(&sber_product_to_inline/1)

    ExGram.Dsl.answer_inline_query(context, suggestions, is_personal: true, next_offset: "#{page+1}")
  end

  defp sber_suggestion_to_inline(%{"price" => price, "product" => %{
    "permalink" => permalink, "name" => product_name, "sku" => sku,
    "images" => [%{"original_url" => original_url, "small_url" => mini_url} | _]
    }}), do:
    %InlineQueryResultPhoto{id: sku, type: "photo",
      photo_url: original_url,
      photo_width: 100,
      photo_height: 100,
      thumb_url: mini_url,
      caption: "#{product_name} — <b>#{Product.format_price(price)}</b>\nhttps://sbermarket.ru/metro/#{permalink}",
      title: product_name,
      description: product_name,
      parse_mode: "HTML"
    }

  defp sber_product_to_inline(%{"price" => price,
    "name" => product_name, "sku" => sku,
    "images" => [%{"original_url" => original_url, "small_url" => mini_url} | _]
    }), do:
    %InlineQueryResultArticle{id: sku, type: "article",
      thumb_url: mini_url,
      thumb_width: 150,
      thumb_height: 150,
      title: product_name,
      description:  Product.format_price(price),
      input_message_content: %InputTextMessageContent{
        message_text: "<b>#{product_name}</b>\n#{Product.format_price(price)}\nhttps://sbermarket.ru/metro/#{sku}",
        parse_mode: "HTML"
      }
    }

end
