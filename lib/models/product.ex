defmodule LoPrice.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :url, :string
    field :retailer, :string

    timestamps()
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :retailer, :url])
    |> validate_required([:name, :retailer, :url])
  end
end
