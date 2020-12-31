defmodule LoPrice.Product do
  use Ecto.Schema
  import Ecto.{Changeset, Query}

  alias LoPrice.{Repo, Product}

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

  def by_url(url), do:
    Product
    |> where(url: ^url)
    |> Repo.one()

  def by_id(product_id), do:
    Product
    |> where(id: ^product_id)
    |> Repo.one()

  def to_kop(float), do: trunc(float*100)
end