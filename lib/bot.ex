defmodule LoPrice.Bot do
  use PI

  import Ecto.Query

  alias LoPrice.{Repo, User, Product, Monitor, PriceChecker, Core}

  alias ExGram.Model.{
    InputMediaPhoto,
    InlineQueryResultPhoto,
    InlineQueryResultArticle,
    InputTextMessageContent
  }

  @bot :lopricebot

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start", description: "Первоначальная настройка — выбор города.")
  command("location", description: "Смена города в котором следим за ценами.")
  command("products", description: "Список отслеживаемых товаров.")

  command("login",
    description: "Введите логин и пароль от СберМаркета, чтобы загрузить любимые товары."
  )

  regex(~r/https:\/\/sbermarket.ru\/.*/iu, :sbermarket)

  use LoPrice.Bot.CitySelector
  use LoPrice.Bot.InlineSearch

  def handle({:command, command, %{from: %{id: user_id}, text: text} = msg}, context)
      when command in [:start, :location] do
    pi(text)
    user = User.by_telegram_id(user_id)
    user_city = user && user.city
    CitySelector.select_city(context, nil, user_city)
  end

  def handle({:command, :products, %{from: %{id: user_id}} = _msg}, context),
    do: list_products(user_id, context)

  def handle({:command, :login, %{from: %{id: telegram_user_id}, text: params}}, context) do
    [email, password] = String.split(params)
    sbermarket_auth = User.encode_credentials(email, password)

    %{id: user_id} =
      Core.create_or_update_user(telegram_user_id, %{extra: %{sbermarket_auth: sbermarket_auth}})

    count_favorites =
      add_monitors_from_sbermarket_favorites(email, password, user_id)
      |> length()

    list_products(telegram_user_id, context)

    answer(context, "Добавил #{count_favorites} шт. товаров из Избранного на СберМаркете.")
  end

  def handle(
        {:text, price_threshold, %{from: %{id: user_id}} = _msg},
        %{
          update: %{
            message: %{
              reply_to_message: %{text: "Нужная цена на " <> product_name, message_id: message_id}
            }
          }
        } = context
      ) do
    pi(price_threshold)

    product_name = String.trim_trailing(product_name, "?")

    {target_price, _} = Float.parse(price_threshold)
    user = User.by_telegram_id(user_id)

    target_price = Product.to_kop(target_price)

    Core.set_monitor_target_price(user.id, message_id, target_price)

    answer(
      context,
      "Сообщу когда <b>#{product_name}</b> подешевеет ниже <b>#{
        Product.format_price(target_price)
      }</b>",
      parse_mode: "HTML"
    )
  end

  # Handle messages with URL
  def handle(
        {:text, _text_message,
         %{text: text, entities: [%{type: "url"} | _] = entities, from: %{id: telegram_user_id}} =
           _msg},
        context
      ) do
    monitor = Core.add_monitor(url_from_message(text, entities), telegram_user_id)

    answer("Товар #{monitor.product.name} добавлен к отслеживанию.", context)
  end

  def handle({:text, telegram_bot_text_message, msg}, context) do
    pi(telegram_bot_text_message)
    pi(msg)
    pi(context)
    answer(context, "Не понимаю.")
  end

  def handle(
        {:regex, :sbermarket,
         %{text: text, entities: entities, chat: %{id: _chat_id}, from: %{id: telegram_user_id}} =
           msg},
        context
      ) do
    pi(msg)
    add_product_monitor(url_from_message(text, entities), telegram_user_id, context)
  end

  def handle(
        {:callback_query,
         %{
           data: "city_" <> city = _query_data,
           chat_instance: _chat_instance,
           id: query_id,
           from:
             %{
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

    %{id: user_id} =
      Core.create_or_update_user(telegeram_user_id, %{
        city: city,
        name: "#{first_name} #{last_name}"
      })

    ExGram.send_message!(
      chat_id,
      """
      Бот настроен. Присылайте боту ссылки на карточки товаров на sbermarket.ru, задавайте целевую цену и бот уведомит вас, когда цена снизится до нужного уровня.
      Пример ссылки: https://sbermarket.ru/metro/foriel-okhlazhdiennaia-3-4.

      Либо с помощью команды /login задайте логин и пароль от СберМаркета и бот будет автоматически отслеживать цены на товары, которые вы добавили в избранное ❤️ на СберМаркете.
      """,
      bot: @bot,
      disable_web_page_preview: true
    )

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
        _context
      ) do
    monitor_id
    |> String.to_integer()
    |> Core.remove_monitor()

    ExGram.answer_callback_query(query_id,
      bot: @bot,
      text: "Удалён из отслеживания."
    )

    ExGram.delete_message(chat_id, message_id, bot: @bot)
  end

  def handle(
        {:callback_query,
         %{
           data: "set_target_" <> monitor_id = _query_data,
           id: query_id,
           message: %{chat: %{id: chat_id}}
         }},
        _context
      ) do
    ExGram.answer_callback_query(query_id, bot: @bot)

    monitor =
      monitor_id
      |> String.to_integer()
      |> Core.get_monitor()

    msg =
      ExGram.send_message!(
        chat_id,
        "Нужная цена на <b>#{monitor.product.name}</b>@#{monitor.product.retailer}?",
        bot: @bot,
        parse_mode: "HTML",
        reply_markup: %ExGram.Model.ForceReply{force_reply: true, selective: true}
      )

    Core.update_monitor(monitor_id, target_price_message_id: msg.message_id)
  end

  def handle({:location, %{latitude: lat, longitude: lon}}, _context) do
    pi({lat, lon})
    :no_answer
  end

  def handle(
        {:message,
         %{caption: caption, caption_entities: entities, chat: %{id: telegram_user_id}}},
        context
      ) do
    add_product_monitor(url_from_message(caption, entities), telegram_user_id, context)
  end

  defp url_from_message(_message, []), do: nil

  defp url_from_message(message, [%{type: "url", offset: offset, length: length} | _]),
    do: String.slice(message, offset, length)

  defp url_from_message(message, [_ | entities]), do: url_from_message(message, entities)

  defp add_product_monitor(product_url, telegram_user_id, context) do
    {retailer, permalink_or_sku} = SberMarket.parse_product_url(product_url) |> pi()

    case User.by_telegram_id(telegram_user_id) do
      nil ->
        CitySelector.select_city(context, retailer)

      user ->
        # Get the first retailer store in the users location
        pi(user)

        case SberMarket.stores(retailer, user.city) do
          [] ->
            answer(
              context,
              "В вашем городе #{user.city} не обнаружено магазинов #{retailer}. Отследить товар не получится."
            )

          stores ->
            store_id =
              stores
              |> SberMarket.ids()
              |> hd()

            permalink = SberMarket.permalink_from_sku(permalink_or_sku)

            sber_product = SberMarket.product(permalink, store_id)

            current_price = sber_product["offer"]["unit_price"] |> Product.to_kop()
            url = "https://sbermarket.ru/#{retailer}/#{permalink}"

            %{id: monitor_id, target_price: target_price} =
              Core.create_or_update_product_and_monitor(
                url,
                sber_product["name"],
                retailer,
                user.id,
                current_price
              )

            unit = SberMarket.unit(sber_product)

            answer(
              context,
              """
              <a href=\"#{url}\">#{sber_product["name"]}</a>@#{retailer}
              Цена: <b>#{Product.format_price(current_price)}#{(unit && "/" <> unit) || ""}</b>
              Как подешевеет ниже #{Product.format_price(target_price)} — сообщу.
              """,
              reply_markup: edit_monitor_buttons(monitor_id, target_price || current_price),
              parse_mode: "HTML"
            )
        end
    end
  end

  def add_monitors_from_sbermarket_favorites(email, password, user_id),
    do:
      SberMarket.login(email, password)
      |> SberMarket.favorites()
      |> Enum.map(&maybe_add_monitor_from_favorite(&1, user_id))

  defp maybe_add_monitor_from_favorite(
         %{
           "product" => %{
             "name" => name,
             "permalink" => permalink,
             "offer" => %{
               "unit_price" => unit_price,
               "store_id" => store_id
             }
           }
         },
         user_id
       ) do
    retailer = SberMarket.store(store_id)["retailer_slug"]

    Core.create_or_update_product_and_monitor(
      "https://sbermarket.ru/#{retailer}/#{permalink}",
      name,
      retailer,
      user_id,
      Product.to_kop(unit_price)
    )
  end

  defp maybe_add_monitor_from_favorite(_, _user_id), do: :nothing

  def notify_about_price_change(
        chat_id,
        product_name,
        store_name,
        old_price,
        target_price,
        price,
        unit \\ nil,
        product_url,
        image_url,
        monitor_id \\ nil
      ),
      do:
        ExGram.send_photo(chat_id, image_url,
          caption:
            price_change_caption(product_name, store_name, old_price, price, unit, product_url),
          bot: @bot,
          parse_mode: "HTML",
          reply_markup: edit_monitor_buttons(monitor_id, target_price)
        )

  def notify_about_price_change_with_group(telegram_user_id, price_changes),
    do:
      price_changes
      |> Enum.chunk_every(10)
      |> Enum.each(&send_price_changes_group(telegram_user_id, &1))

  defp send_price_changes_group(telegram_user_id, changes) when is_list(changes),
    do: ExGram.send_media_group!(telegram_user_id, media_group_from_changes(changes), bot: @bot)

  defp media_group_from_changes(changes),
    do:
      Enum.map(changes, fn %{
                             product_name: product_name,
                             store_name: store_name,
                             last_price: last_price,
                             current_price: current_price,
                             unit: unit,
                             product_url: product_url,
                             image_url: image_url
                           } ->
        %ExGram.Model.InputMediaPhoto{
          media: image_url,
          type: "photo",
          caption:
            price_change_caption(
              product_name,
              store_name,
              last_price,
              current_price,
              unit,
              product_url
            ),
          parse_mode: "HTML"
        }
      end)

  defp price_change_caption(product_name, store_name, old_price, price, unit, product_url),
    do:
      "#{product_name}@#{store_name} — <s>#{Product.format_price(old_price)}</s>→<b>#{
        Product.format_price(price)
      }</b>#{(unit && "/" <> unit) || ""}\n#{product_url}"

  defp edit_monitor_buttons(nil, _), do: []

  defp edit_monitor_buttons(monitor_id, target_price),
    do:
      create_inline([
        [
          %{
            text: "Уточнить (#{Product.format_price(target_price)})",
            callback_data: "set_target_#{monitor_id}"
          },
          %{text: "Удалить", callback_data: "remove_monitor_#{monitor_id}"}
        ]
      ])

  def list_products(telegram_user_id, context) do
    Core.user_monitors(telegram_user_id)
    |> Enum.chunk_every(20)
    |> Enum.each(fn chunk ->
      products_list =
        chunk
        |> Enum.map(fn %{
                         id: _monitor_id,
                         target_price: tprice,
                         price_history: hprice,
                         product: %{name: product_name, url: product_url, retailer: retailer}
                       } ->
          "#{product_icon(product_name)}<a href=\"#{product_url}\">#{product_name}</a>@#{retailer} #{
            Product.format_price(List.last(hprice))
          }→<i>#{Product.format_price(tprice)}</i>"
        end)
        |> Enum.join("\n")

      ExGram.send_message(telegram_user_id, products_list,
        bot: @bot,
        parse_mode: "HTML",
        disable_web_page_preview: true
      )
    end)
  end

  @product_icons [
    {~w(чипсы), "🍟"},
    {~w(кошач коше), "🐈"},
    {~w(утка утин), "🦆"},
    {~w(майонез кетчуп консерв), "🥫"},
    {~w(паста спагетти макароны вермишель макарон), "🍝"},
    {~w(сыр), "🧀"},
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
