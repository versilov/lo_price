defmodule LoPrice.Bot do
  use PI

  import Ecto.Query

  alias LoPrice.{Repo, User, Product, Monitor}

  @bot :lopricebot
  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start", description: "Первоначальная настройка — выбор города.")
  command("products", description: "Список отслеживаемых товаров.")

  regex(~r/^https:\/\/sbermarket.ru\/.*/iu, :sbermarket)

  def handle({:command, :start, %{from: %{id: user_id}} = _msg}, context) do
    user = User.by_telegram_id(user_id)
    user_city = user && user.city
    select_city(context, nil, user_city)
  end
  def handle({:command, :products, %{from: %{id: user_id}} = _msg}, context), do: list_products(user_id, context)

  defp select_city(context, retailer \\ nil, selected_city \\ nil), do:
    answer(context, "В каком городе отслеживать цены?", reply_markup: cities_buttons(0, retailer, selected_city))

  def handle(
        {:text, price_threshold, %{from: %{id: user_id}} = msg},
        %{update: %{message: %{reply_to_message: %{text: "Нужная цена?" <> _, message_id: message_id}}}} = context
      ) do
    pi(price_threshold)
    pi(msg)
    pi(context)

    {target_price, _} = Float.parse(price_threshold)
    user = User.by_telegram_id(user_id)

    target_price = Product.to_kop(target_price)

    from(
      m in Monitor,
      where: m.user_id == ^user.id and m.target_price_message_id == ^message_id,
      update: [
        set: [target_price: ^target_price, target_price_message_id: nil]
      ]
    )
    |> Repo.update_all([])

    answer(context, "Сообщу, как подешевеет ниже #{Product.format_price(target_price)}")
  end


  def handle({:text, telegram_bot_text_message, msg}, context) do
    pi(telegram_bot_text_message)
    pi(msg)
    pi(context)
    # answer(context, "Не понимаю. Возможные запросы: chat_id")
    :no_answer
  end

  def handle(
        {:regex, :sbermarket, %{message_id: message_id, text: product_url, chat: %{id: _chat_id}, from: %{id: user_id}} = msg},
        context
      ) do

        pi(msg)

    {retailer, permalink} = SberMarket.parse_product_url(product_url)

    case User.by_telegram_id(user_id) do
      nil ->
        select_city(context, retailer)

      user ->
        sber_product = SberMarket.product(permalink)

        current_price = sber_product["offer"]["unit_price"] |> Product.to_kop()

        product = find_or_create_product(product_url, sber_product["name"], retailer)

        create_or_update_monitor(user.id, product.id, current_price, nil, message_id + 1)

        answer(context, "Нужная цена? (Текущая: #{sber_product["offer"]["unit_price"]}₽)\nОтправьте пустое сообщение, чтобы отслеживать любое снижение цены от текущей.", reply_markup: %ExGram.Model.ForceReply{force_reply: true, selective: true})
    end
  end

  @lines_in_page 5
  @buttons_in_line 3
  defp cities_buttons(page \\ 0, retailer \\ nil, selected_city \\ nil), do:
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
      |> create_inline()

  defp add_browse_buttons(buttons, page), do:
        prev_button(page) ++
        buttons
        ++ next_button(page, last_page?(buttons))

  defp last_page?(buttons_page), do: length(buttons_page) < @lines_in_page || length(List.last(buttons_page)) < @buttons_in_line

  defp prev_button(0), do: []
  defp prev_button(page), do: [[%{text: "▲ Назад ▲", callback_data: "page_#{page-1}"}]]

  defp next_button(page, true = _last_page), do: []
  defp next_button(page, _last_page), do: [[%{text: "▼ Дальше ▼", callback_data: "page_#{page+1}"}]]

  def handle({:callback_query, %{id: query_id, data: "page_" <> page, message: %{chat: %{id: chat_id}, message_id: message_id}}}, context) do
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

    create_or_update_user(user_id, city, "#{first_name} #{last_name}")

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

  defp create_or_update_user(telegram_user_id, city, name) do
    case User.by_telegram_id(telegram_user_id) do
      nil ->
        %User{}
        |> User.changeset(%{city: city, name: name, telegram_user_id: telegram_user_id})
        |> Repo.insert()

      user ->
        user
        |> User.changeset(%{city: city, name: name})
        |> Repo.update()
    end
  end

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

  defp create_or_update_monitor(user_id, product_id, current_price, target_price \\ nil, target_price_message_id \\ nil) do
    case Monitor.by_user_and_product(user_id, product_id) do
      nil ->
        %Monitor{user_id: user_id, product_id: product_id,
                 target_price: target_price || current_price, price_history: [current_price],
                  target_price_message_id: target_price_message_id}
        |> Repo.insert!()

      monitor ->
        monitor
        |> Monitor.changeset(%{target_price_message_id: target_price_message_id}
                             |> Monitor.maybe_update_price_history(monitor, current_price)
                             |> maybe_add_target_price(target_price)
                             )
        |> Repo.update!()
    end
  end

  defp maybe_add_target_price(attrs, nil), do: attrs
  defp maybe_add_target_price(attrs, target_price) when is_integer(target_price), do: Map.put(attrs, :target_price, target_price)

  def notify_about_price_change(chat_id, product_name, store_name, price, unit \\ nil, product_url, image_url) do
    caption =
      "#{product_name}@#{store_name} — #{Product.format_price(price)}#{unit && "/" <> unit || ""}\n#{product_url}"

    ExGram.send_photo(chat_id, image_url, caption: caption, bot: @bot)
  end

  def list_products(telegram_user_id, context) do
    user = User.by_telegram_id(telegram_user_id)

    products_list =
    from(m in Monitor,
    where: m.user_id == ^user.id,
    left_join: product in assoc(m, :product),
    preload: [:product])
    |> Repo.all()
    |> Enum.map(fn %{id: monitor_id, target_price: tprice, price_history: hprice, product: %{name: product_name, url: product_url}} ->
      "#{product_icon(product_name)}<a href=\"#{product_url}\">#{product_name}</a> #{Product.format_price(List.last(hprice))}→<i>#{Product.format_price(tprice)}</i>"
    end)
    |> Enum.join("\n")

    answer(context, products_list, parse_mode: "HTML", disable_web_page_preview: true)
  end

  @product_icons [
    {~w(сыр),"🧀"},
    {~w(форель рыба лосось стерлядь сёмга угорь тунец), "🐟"},
    {~w(стейк), "🥩"},
    {~w(яйцо яйца), "🥚"},
    {~w(хлеб), "🍞"},
    {~w(вода), "💧"},
    {~w(соус), "🍶"},
    {~w(картошка картофель), "🥔"},
    {~w(аперитив ликёр водка вино), "🍾"}
  ]
  defp product_icon(name) do
    @product_icons
    |> Enum.find(fn {words, icon} ->
      name
      |> String.downcase()
      |> String.contains?(words)
    end)
    |> (fn
      nil -> ""
      {_, icon} -> icon <> " "
    end).()
  end
end
