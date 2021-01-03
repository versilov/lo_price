defmodule LoPrice.Bot.CitySelector do
  alias LoPrice.{User, Bot}

  defmacro __using__(_) do
    quote do
      alias LoPrice.Bot.CitySelector

      def handle({:callback_query, %{id: query_id, data: "page_" <> page, message: %{chat: %{id: chat_id}, message_id: message_id}}}, _context), do:
        LoPrice.Bot.CitySelector.handle_callback_query(query_id, page, chat_id, message_id)
    end
  end

  @bot :lopricebot

  def handle_callback_query(query_id, page, chat_id, message_id) do
    ExGram.answer_callback_query(query_id, bot: @bot)

    user = User.by_telegram_id(chat_id)
    user_city = user && user.city

    ExGram.edit_message_reply_markup(
      bot: @bot,
      chat_id: chat_id,
      message_id: message_id,
      reply_markup: cities_buttons(String.to_integer(page), nil, user_city)
    )
  end

  def select_city(context, retailer, selected_city \\ nil), do:
    ExGram.Dsl.answer(context, "В каком городе отслеживать цены?", reply_markup: cities_buttons(0, retailer, selected_city))

  @lines_in_page 5
  @buttons_in_line 3
  def cities_buttons(page, retailer, selected_city), do:
      retailer
      |> SberMarket.stores_cities()
      |> Enum.map(
        &%{
          text: if(&1 == selected_city, do: "✅ ", else: "") <> &1,
          callback_data: "city_" <> &1
        }
      )
      |> Enum.chunk_every(@buttons_in_line)
      |> Enum.slice(page * @lines_in_page, @lines_in_page)
      |> add_browse_buttons(page)
      |> ExGram.Dsl.create_inline()

  defp add_browse_buttons(buttons, page), do:
        prev_button(page) ++
        buttons
        ++ next_button(page, last_page?(buttons))

  defp last_page?(buttons_page), do: length(buttons_page) < @lines_in_page || length(List.last(buttons_page)) < @buttons_in_line

  defp prev_button(0), do: []
  defp prev_button(page), do: [[%{text: "▲ Назад ▲", callback_data: "page_#{page-1}"}]]

  defp next_button(_page, true = _last_page), do: []
  defp next_button(page, _last_page), do: [[%{text: "▼ Дальше ▼", callback_data: "page_#{page+1}"}]]

end
