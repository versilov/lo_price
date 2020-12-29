defmodule LoPrice.Bot do
  use PI

  @bot :lopricebot
  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start")

  regex(~r/^https:\/\/sbermarket.ru\/.*/iu, :sbermarket)

  def handle({:command, :start, _msg}, context), do: answer(context, "Hi!")

  def handle(
        {:text, price_threshold, _msg},
        %{update: %{message: %{reply_to_message: %{text: "Price threshold?"}}}} = context
      ) do
    pi(price_threshold)
  end

  def handle({:text, telegram_bot_text_message, _msg}, context) do
    pi(telegram_bot_text_message)
    pi(context)
    # answer(context, "Не понимаю. Возможные запросы: chat_id")
    :no_answer
  end

  def handle(
        {:regex, :sbermarket, %{text: product_url, chat: %{id: chat_id}} = _msg},
        context
      ) do
    [retailer, permalink] =
      product_url
      |> URI.parse()
      |> Map.get(:path)
      |> String.split("/", trim: true)
      |> pi()

    # answer(
    #   context,
    #   text
    # )
    cities_buttons =
      retailer
      |> SberMarket.stores_cities()
      |> Enum.map(
        &%{
          text: &1,
          callback_data: "city_#{Russian.transliterate(&1)}:#{retailer}:#{permalink}"
        }
      )
      |> Enum.chunk_every(3)

    answer(context, "What city?", reply_markup: create_inline(cities_buttons))
  end

  def handle(
        {:callback_query,
         %{
           data: "city_" <> city = query_data,
           chat_instance: chat_instance,
           id: query_id,
           from: %{
             id: user_id
           },
           message: %{chat: %{id: chat_id}, message_id: message_id}
         }},
        context
      ) do
    pi(city)

    ExGram.answer_callback_query(query_id,
      bot: @bot,
      text: "City: #{city}",
      cache_time: 1000
    )

    ExGram.edit_message_reply_markup(
      bot: @bot,
      chat_id: chat_id,
      message_id: message_id,
      reply_markup: create_inline([[%{text: "Location", callback_data: "loc"}]])
    )

    # answer(context, "Location?",
    #   reply_markup: %{keyboard: [[%{text: "Location", request_location: true}]]}
    # )

    answer(context, "Price threshold (if price goes lower, we will notify you)?",
      reply_markup: %ExGram.Model.ForceReply{force_reply: true, selective: true}
    )
  end

  def handle({:location, %{latitude: lat, longitude: lon}}, context) do
    pi({lat, lon})
    :no_answer
  end
end
