defmodule LoPrice.MonitoredProduct do
  use Ecto.Schema
  import Ecto.Changeset

  schema "monitored_products" do
    field :name, :string
    field :price_history, {:array, :integer}
    field :retailer, :string
    field :target_price, :integer
    field :user_id, :id

    timestamps()
  end

  @doc false
  def changeset(monitored_product, attrs) do
    monitored_product
    |> cast(attrs, [:name, :retailer, :target_price, :price_history])
    |> validate_required([:name, :retailer, :target_price, :price_history])
  end
end
