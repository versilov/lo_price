defmodule LoPrice.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :url, :string, null: false
      add :name, :string, null: false
      add :retailer, :string, null: false

      timestamps()
    end

    create unique_index(:products, [:url])
  end
end
