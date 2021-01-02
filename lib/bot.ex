defmodule LoPrice.Bot do
  use PI

  import Ecto.Query

  alias LoPrice.{Repo, User, Product, Monitor, PriceChecker}
  alias ExGram.Model.{InputMediaPhoto, InlineQueryResultPhoto, InlineQueryResultArticle, InputTextMessageContent}

  @bot :lopricebot
  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start", description: "Первоначальная настройка — выбор города.")
  command("location", description: "Смена города в котором следим за ценами.")
  command("products", description: "Список отслеживаемых товаров.")
  command("login", description: "Введите логин и пароль от СберМаркета, чтобы загрузить любимые товары.")

  regex(~r/^https:\/\/sbermarket.ru\/.*/iu, :sbermarket)

  def handle({:command, command, %{from: %{id: user_id}} = _msg}, context) when command in [:start, :location] do
    user = User.by_telegram_id(user_id)
    user_city = user && user.city
    select_city(context, nil, user_city)
  end

  def handle({:command, :products, %{from: %{id: user_id}} = _msg}, context), do: list_products(user_id, context)

  def handle({:command, :login, %{from: %{id: telegram_user_id}, text: params}}, context) do
    [email, password] = String.split(params)
    sbermarket_auth = User.encode_credentials(email, password)

    %{id: user_id} = create_or_update_user(telegram_user_id, %{extra: %{sbermarket_auth: sbermarket_auth}})

    add_monitors_from_sbermarket_favorites(email, password, user_id)
  end


  def handle(
        {:text, price_threshold, %{from: %{id: user_id}} = _msg},
        %{update: %{message: %{reply_to_message: %{text: "Нужная цена на " <> product_name, message_id: message_id}}}} = context
      ) do
    pi(price_threshold)

    product_name = String.trim_trailing(product_name, "?")

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

    answer(context, "Сообщу когда <b>#{product_name}</b> подешевеет ниже <b>#{Product.format_price(target_price)}</b>",
      parse_mode: "HTML")
  end


  def handle({:text, telegram_bot_text_message, msg}, context) do
    pi(telegram_bot_text_message)
    pi(msg)
    pi(context)
    # answer(context, "Не понимаю. Возможные запросы: chat_id")
    :no_answer
  end

  def handle(
        {:regex, :sbermarket, %{text: product_url, chat: %{id: _chat_id}, from: %{id: telegram_user_id}} = _msg},
        context
      ), do:
    add_product_monitor(product_url, telegram_user_id, context)

  def handle({:callback_query, %{id: query_id, data: "page_" <> page, message: %{chat: %{id: chat_id}, message_id: message_id}}}, _context) do
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
             id: telegeram_user_id,
             first_name: first_name,
             last_name: last_name
           } = _from,
           message: %{chat: %{id: chat_id}, message_id: message_id}
         }},
        _context
      ) do
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

    %{id: user_id} = create_or_update_user(telegeram_user_id, %{city: city, name: "#{first_name} #{last_name}"})

    ExGram.send_message!(chat_id,
        """
        Бот настроен. Присылайте боту ссылки на карточки товаров на sbermarket.ru, задавайте целевую цену и бот уведомит вас, когда цена снизится до нужного уровня.
        Пример ссылки: https://sbermarket.ru/metro/foriel-okhlazhdiennaia-3-4.

        Либо с помощью команды /login задайте логин и пароль от СберМаркета и бот будет автоматически отслеживать цены на товары, которые вы добавили в избранное на СберМаркете.
        """,
      bot: @bot, disable_web_page_preview: true)

    # Force price check in the new city for this user
    PriceChecker.check_prices(user_id, true)
  end

  def handle(
        {:callback_query,
         %{
           data: "remove_monitor_" <> monitor_id = _query_data,
           id: query_id,
           message: %{chat: %{id: chat_id}, message_id: message_id}
         }},
         _context) do
    monitor_id = String.to_integer(monitor_id)
    Monitor.remove(monitor_id)

    ExGram.answer_callback_query(query_id,
      bot: @bot,
      text: "Удалён из отслеживания.")

    ExGram.delete_message(chat_id, message_id, bot: @bot)
  end

  def handle(
        {:callback_query,
         %{
           data: "set_target_" <> monitor_id = _query_data,
           id: query_id,
           message: %{chat: %{id: chat_id}}
         }},
         _context) do
    monitor_id = String.to_integer(monitor_id)

    ExGram.answer_callback_query(query_id, bot: @bot)

    monitor = Monitor.get(monitor_id)

    msg = ExGram.send_message!(chat_id, "Нужная цена на <b>#{monitor.product.name}</b>@#{monitor.product.retailer}?",
      bot: @bot,
      parse_mode: "HTML",
      reply_markup: %ExGram.Model.ForceReply{force_reply: true, selective: true})

    from(
      m in Monitor,
      where: m.id == ^monitor_id,
      update: [
        set: [target_price_message_id: ^msg.message_id]
      ]
    )
    |> Repo.update_all([])
  end


  def handle({:location, %{latitude: lat, longitude: lon}}, _context) do
    pi({lat, lon})
    :no_answer
  end

  def handle({:inline_query, %{query: query, offset: offset} = inline_msg}, context) do

    page = case offset do
      "" -> 1
      num -> String.to_integer(num)
    end

    suggestions =
      SberMarket.search(105, query, page, 7)
      |> Enum.reject(& &1["images"] == [])
      |> Enum.map(&sber_product_to_inline/1)

    answer_inline_query(context, suggestions, is_personal: true, next_offset: "#{page+1}")
  end

  def handle({:message, %{caption: caption, caption_entities: entities, chat: %{id: telegram_user_id}}}, context) do
    add_product_monitor(product_url(caption, entities), telegram_user_id, context)
  end

  defp product_url(_caption, []), do: nil
  defp product_url(caption, [%{type: "url", offset: offset, length: length} | _]), do:
    String.slice(caption, offset, length)

  defp product_url(caption, [_ | entities]), do: product_url(caption, entities)


  defp add_product_monitor(product_url, telegram_user_id, context) do
    {retailer, permalink} = SberMarket.parse_product_url(product_url) |> pi()

    case User.by_telegram_id(telegram_user_id) do
      nil ->
        select_city(context, retailer)

      user ->
        # Get the first retailer store in the users location
        pi(user)
        case SberMarket.stores(retailer, user.city) do
          [] ->
            answer(context, "В вашем городе #{user.city} не обнаружено магазинов #{retailer}. Отследить товар не получится.")

          stores ->
            store_id =
              stores
              |> SberMarket.ids()
              |> hd()

            sber_product = SberMarket.product(permalink, store_id)

            current_price = sber_product["offer"]["unit_price"] |> Product.to_kop()

            %{id: monitor_id, target_price: target_price} = create_or_update_product_and_monitor(
              product_url, sber_product["name"], retailer, user.id, current_price)

            answer(context, "<b>#{sber_product["name"]}</b>@#{retailer}\nЦена: <b>#{Product.format_price(current_price)}</b>\nКак подешевеет — сообщу.",
              reply_markup: edit_monitor_buttons(monitor_id, target_price || current_price),
              parse_mode: "HTML")
      end
    end
  end

  defp create_or_update_product_and_monitor(product_url, product_name, retailer, user_id, price) do
    product = find_or_create_product(product_url, product_name, retailer)
    create_or_update_monitor(user_id, product.id, price)
  end

  def add_monitors_from_sbermarket_favorites(email, password, user_id), do:
    SberMarket.login(email, password)
    |> SberMarket.favorites()
    |> Enum.map(&maybe_add_monitor(&1, user_id))

  defp maybe_add_monitor(%{"product" => %{"name" => name, "permalink" => permalink, "offer" => %{
    "price" => price,
    "store_id" => store_id
    }}}, user_id) do
    retailer = SberMarket.store(store_id)["retailer_slug"]

    create_or_update_product_and_monitor("https://sbermarket.ru/#{retailer}/#{permalink}",
    name, retailer, user_id, Product.to_kop(price))
  end

  defp maybe_add_monitor(_, _user_id), do: :nothing

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

    # %InlineQueryResultPhoto{id: sku, type: "photo",
    #   photo_url: original_url,
    #   photo_width: 100,
    #   photo_height: 100,
    #   thumb_url: mini_url,
    #   caption: "#{product_name} — <b>#{Product.format_price(price)}</b>\nhttps://sbermarket.ru/metro/#{sku}",
    #   title: product_name,
    #   description: product_name,
    #   parse_mode: "HTML"
    # }


  defp select_city(context, retailer, selected_city \\ nil), do:
    answer(context, "В каком городе отслеживать цены?", reply_markup: cities_buttons(0, retailer, selected_city))

  @lines_in_page 5
  @buttons_in_line 3
  defp cities_buttons(page, retailer, selected_city), do:
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

  defp next_button(_page, true = _last_page), do: []
  defp next_button(page, _last_page), do: [[%{text: "▼ Дальше ▼", callback_data: "page_#{page+1}"}]]


  defp create_or_update_user(telegram_user_id, attrs) do
    case User.by_telegram_id(telegram_user_id) do
      nil ->
        %User{}
        |> User.changeset(Map.merge(attrs, %{telegram_user_id: telegram_user_id}))
        |> Repo.insert!()

      user ->
        user
        |> User.changeset(attrs)
        |> Repo.update!()
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

  def notify_about_price_change(chat_id, product_name, store_name, old_price, target_price, price, unit \\ nil, product_url, image_url, monitor_id \\ nil), do:
    ExGram.send_photo(chat_id, image_url,
                      caption: price_change_caption(product_name, store_name, old_price, price, unit, product_url),
                      bot: @bot, parse_mode: "HTML",
                      reply_markup: edit_monitor_buttons(monitor_id, target_price))

  def notify_about_price_change_with_group(telegram_user_id, price_changes), do:
    price_changes
    |> Enum.chunk_every(10)
    |> Enum.each(&send_price_changes_group(telegram_user_id, &1))

  defp send_price_changes_group(telegram_user_id, changes) when is_list(changes), do:
    ExGram.send_media_group!(telegram_user_id, media_group_from_changes(changes), bot: @bot)

  defp media_group_from_changes(changes), do:
    Enum.map(changes, fn %{product_name: product_name, store_name: store_name,
                  last_price: last_price, current_price: current_price,
                  unit: unit, product_url: product_url, image_url: image_url} ->
      %ExGram.Model.InputMediaPhoto{
        media: image_url,
        type: "photo",
        caption: price_change_caption(product_name, store_name, last_price, current_price, unit, product_url),
        parse_mode: "HTML"
      }
    end)

  defp price_change_caption(product_name, store_name, old_price, price, unit, product_url), do:
    "#{product_name}@#{store_name} — <s>#{Product.format_price(old_price)}</s>→<b>#{Product.format_price(price)}</b>#{unit && "/" <> unit || ""}\n#{product_url}"

  defp edit_monitor_buttons(nil, _), do: []
  defp edit_monitor_buttons(monitor_id, target_price), do:
    create_inline([[
                    %{text: "Уточнить (#{Product.format_price(target_price)})", callback_data: "set_target_#{monitor_id}"},
                    %{text: "Удалить", callback_data: "remove_monitor_#{monitor_id}"}
                  ]])

  def list_products(telegram_user_id, context) do
    user = User.by_telegram_id(telegram_user_id)

    products_list =
    from(m in Monitor,
    where: m.user_id == ^user.id,
    left_join: product in assoc(m, :product),
    preload: [:product])
    |> Repo.all()
    |> Enum.map(fn %{id: _monitor_id, target_price: tprice, price_history: hprice, product: %{name: product_name, url: product_url, retailer: retailer}} ->
      "#{product_icon(product_name)}<a href=\"#{product_url}\">#{product_name}</a>@#{retailer} #{Product.format_price(List.last(hprice))}→<i>#{Product.format_price(tprice)}</i>"
    end)
    |> Enum.join("\n")

    answer(context, products_list, parse_mode: "HTML", disable_web_page_preview: true)
  end

  @product_icons [
    {~w(чипсы),"🍟"},
    {~w(кошач коше),"🐈"},
    {~w(майонез кетчуп консерв),"🥫"},
    {~w(паста спагетти макароны вермишель макарон),"🍝"},
    {~w(сыр),"🧀"},
    {~w(форель рыба лосось стерлядь сёмга угорь тунец), "🐟"},
    {~w(стейк), "🥩"},
    {~w(яйцо яйца), "🥚"},
    {~w(хлеб), "🍞"},
    {~w(вода), "💧"},
    {~w(соус), "🍶"},
    {~w(шоколад), "🍫"},
    {~w(картошка картофель), "🥔"},
    {~w(аперитив ликёр водка вино ликер ликёр), "🍾"}
  ]
  defp product_icon(name) do
    @product_icons
    |> Enum.find(fn {words, _icon} ->
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
