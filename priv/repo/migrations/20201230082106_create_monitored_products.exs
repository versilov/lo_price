defmodule LoPrice.Repo.Migrations.CreateMonitoredProducts do
  use Ecto.Migration

  def change do
    create table(:monitored_products) do
      add :name, :string, null: false
      add :retailer, :string, null: false
      add :target_price, :integer
      add :price_history, {:array, :integer}, default: []
      add :user_id, references(:users, on_delete: :nothing), null: false

      timestamps()
    end

    create index(:monitored_products, [:user_id])
  end
end
