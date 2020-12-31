defmodule LoPrice.Bot do
  use PI

  import Ecto.Query

  alias LoPrice.{Repo, User, Product, Monitor}

  @bot :lopricebot
  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start", description: "Show start info")

  regex(~r/^https:\/\/sbermarket.ru\/.*/iu, :sbermarket)

  def handle({:command, :start, _msg}, context), do: select_city(context)

  defp select_city(context, retailer \\ nil), do:
    answer(context, "В каком городе отслеживать цены?", reply_markup: cities_buttons(0, retailer))

  def handle(
        {:text, price_threshold, %{from: %{id: user_id}} = msg},
        %{update: %{message: %{reply_to_message: %{text: "Нужная цена?"}}}} = context
      ) do
    pi(price_threshold)
    pi(msg)
    pi(context)

    {target_price, _} = Float.parse(price_threshold)
    user = User.by_telegram_id(user_id)

    from(
      m in Monitor,
      where: m.user_id == ^user.id and m.target_price == 0,
      update: [
        set: [target_price: ^to_kop(target_price)]
      ]
    )
    |> Repo.update_all([])
  end

  defp to_kop(float), do: trunc(float*100)

  def handle({:text, telegram_bot_text_message, _msg}, context) do
    pi(telegram_bot_text_message)
    pi(context)
    # answer(context, "Не понимаю. Возможные запросы: chat_id")
    :no_answer
  end

  def handle(
        {:regex, :sbermarket, %{text: product_url, chat: %{id: _chat_id}, from: %{id: user_id}} = msg},
        context
      ) do

        pi(msg)

    [retailer, permalink] =
      product_url
      |> URI.parse()
      |> Map.get(:path)
      |> String.split("/", trim: true)
      |> pi()

    case User.by_telegram_id(user_id) do
      nil ->
        select_city(context, retailer)

      user ->
        sber_product = SberMarket.product(permalink)

        current_price = sber_product["offer"]["price"] |> to_kop()

        product =
          %Product{}
          |> Product.changeset(%{url: product_url, user_id: user.id, retailer: retailer, name: sber_product["name"]})
          |> Repo.insert!()

        %Monitor{user_id: user.id, product_id: product.id, target_price: 0, price_history: [current_price]}
        |> Repo.insert!()

        answer(context, "Нужная цена?", reply_markup: %ExGram.Model.ForceReply{force_reply: true, selective: true})
    end
  end

  @lines_in_page 5
  @buttons_in_line 3
  defp cities_buttons(page \\ 0, retailer \\ nil), do:
      retailer
      |> SberMarket.stores_cities()
      |> Enum.map(
        &%{
          text: &1,
          callback_data: "city_" <> &1
        }
      )
      |> Enum.chunk_every(@buttons_in_line)
      |> Enum.slice(page * @lines_in_page, @lines_in_page)
      |> add_browse_buttons(page)
      |> create_inline()

  defp add_browse_buttons(buttons, page), do:
        prev_button(page) ++
        buttons
        ++ next_button(page, last_page?(buttons))

  defp last_page?(buttons_page), do: length(buttons_page) < @lines_in_page || length(List.last(buttons_page)) < @buttons_in_line

  defp prev_button(0), do: []
  defp prev_button(page), do: [[%{text: "Назад", callback_data: "page_#{page-1}"}]]

  defp next_button(page, true = _last_page), do: []
  defp next_button(page, _last_page), do: [[%{text: "Дальше", callback_data: "page_#{page+1}"}]]

  def handle({:callback_query, %{id: query_id, data: "page_" <> page, message: %{chat: %{id: chat_id}, message_id: message_id}}}, context) do
      ExGram.answer_callback_query(query_id, bot: @bot)

    ExGram.edit_message_reply_markup(
      bot: @bot,
      chat_id: chat_id,
      message_id: message_id,
      reply_markup: cities_buttons(String.to_integer(page))
    )
  end

  def handle(
        {:callback_query,
         %{
           data: "city_" <> city = _query_data,
           chat_instance: _chat_instance,
           id: query_id,
           from: %{
             id: user_id,
             first_name: first_name,
             last_name: last_name
           } = from,
           message: %{chat: %{id: chat_id}, message_id: message_id}
         }},
        context
      ) do
    pi(city)
    pi(from)

    ExGram.answer_callback_query(query_id,
      bot: @bot,
      text: "Ваш город: #{city}",
      cache_time: 1000
    )

    ExGram.edit_message_reply_markup(
      bot: @bot,
      chat_id: chat_id,
      message_id: message_id,
      reply_markup: create_inline([[%{text: "✅ " <> city, callback_data: "noop"}]])
    )

    # answer(context, "Location?",
    #   reply_markup: %{keyboard: [[%{text: "Location", request_location: true}]]}
    # )

    case User.by_telegram_id(user_id) do
      nil ->
        %User{}
        |> User.changeset(%{city: city, name: "#{first_name} #{last_name}", telegram_user_id: user_id})
        |> Repo.insert()

      user ->
        user
        |> User.changeset(%{city: city, name: "#{first_name} #{last_name}"})
        |> Repo.update()
    end


    answer(context,
    """
    Бот настроен. Присылайте боту ссылки на карточки товаров на sbermarket.ru, задавайте целевую цену и бот уведомит вас, когда цена снизится до нужного уровня.
    Пример ссылки: https://sbermarket.ru/metro/foriel-okhlazhdiennaia-3-4
    """
    )
  end

  def handle({:location, %{latitude: lat, longitude: lon}}, _context) do
    pi({lat, lon})
    :no_answer
  end
end
