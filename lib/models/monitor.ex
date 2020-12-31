defmodule LoPrice.Monitor do
  use Ecto.Schema
  import Ecto.Changeset

  alias LoPrice.{User, Product}

  schema "monitors" do
    belongs_to :user, User
    belongs_to :product, Product
    field :price_history, {:array, :integer}
    field :target_price, :integer

    timestamps()
  end

  @doc false
  def changeset(monitor, attrs) do
    monitor
    |> cast(attrs, [:target_price, :price_history, :user_id, :product_id])
    |> validate_required([:target_price, :price_history, :user_id, :product_id])
  end
end
