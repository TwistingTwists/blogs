Mix.install([
  {:ecto_sql, "~> 3.10"},
  {:ecto, "~> 3.12"},
  {:postgrex, ">= 0.0.0"}
])
System.get_env("DATABASE_URL") |> IO.inspect(label: "DATABASE_URL")

database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    environment variable DATABASE_URL is missing.
    For example: ecto://USER:PASS@HOST/DATABASE
    """

Application.put_env(:foo, Repo, show_sensitive_data_on_connection_error: true, pool_size: 3, url: database_url)

defmodule Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, otp_app: :foo
end

defmodule Migration0 do
  use Ecto.Migration

  def change do
    create table("posts") do
      add(:title, :string)
      timestamps(type: :utc_datetime_usec)
    end
  end
end

defmodule Post do
  use Ecto.Schema

  schema "posts" do
    field(:title, :string)
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Main do
  import Ecto.Query, warn: false

  def main do
    Repo.__adapter__().storage_down(Repo.config())
    :ok = Repo.__adapter__().storage_up(Repo.config())
    {:ok, _} = Supervisor.start_link([Repo], strategy: :one_for_one)
    Ecto.Migrator.run(Repo, [{0, Migration0}], :up, all: true, log_migrations_sql: :info)

    Repo.insert!(%Post{
      title: "Post 1"
    })

    Repo.all(from(p in Post))
    |> dbg()
  end
end

Main.main()