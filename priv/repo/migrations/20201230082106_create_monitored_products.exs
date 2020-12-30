defmodule LoPrice.Repo.Migrations.CreateMonitoredProducts do
  use Ecto.Migration

  def change do
    create table(:monitored_products) do
      add :name, :string
      add :retailer, :string
      add :target_price, :integer
      add :price_history, {:array, :integer}
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:monitored_products, [:user_id])
  end
end
