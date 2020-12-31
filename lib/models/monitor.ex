defmodule LoPrice.Monitor do
  use Ecto.Schema
  import Ecto.{Changeset, Query}

  alias LoPrice.{Repo, User, Product, Monitor}

  schema "monitors" do
    belongs_to :user, User
    belongs_to :product, Product
    field :price_history, {:array, :integer}
    field :target_price, :integer
    field :target_price_message_id, :integer

    timestamps()
  end

  @doc false
  def changeset(monitor, attrs) do
    monitor
    |> cast(attrs, [:target_price, :price_history, :user_id, :product_id, :target_price_message_id])
    |> validate_required([:target_price, :price_history, :user_id, :product_id])
  end

  def by_user_and_product(user_id, product_id) do
    Monitor
    |> where(user_id: ^user_id, product_id: ^product_id)
    |> Repo.one()
  end

  def maybe_update_price_history(attrs, %{price_history: history}, current_price) do
    if List.last(history) != current_price do
      Map.put(attrs, :price_history, history ++ [current_price])
    else
      attrs
    end
  end

  def update_price_history(monitor, current_price), do:
    monitor
    |> Monitor.changeset(Monitor.maybe_update_price_history(%{}, monitor, current_price))
    |> Repo.update()

  def remove(id), do:
    Repo.get!(Monitor, id)
    |> Repo.delete!()
end
