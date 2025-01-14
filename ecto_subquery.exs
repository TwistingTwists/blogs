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
    create table("hackers",primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:name, :string)
    end
    create table("challenges",primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:hacker_id, references(:hackers, on_delete: :nothing), null: false)
    end
  end
end

defmodule Hacker do
  use Ecto.Schema

  schema "hackers" do
    field(:name, :string)

    has_many :challenges, Challenge
  end
end

defmodule Challenge do
  use Ecto.Schema

  schema "challenges" do

    belongs_to :hacker, Hacker
  end
end

defmodule Main do
  import Ecto.Query, warn: false

  def main do
    Repo.__adapter__().storage_down(Repo.config())
    :ok = Repo.__adapter__().storage_up(Repo.config())
    {:ok, _} = Supervisor.start_link([Repo], strategy: :one_for_one)
    Ecto.Migrator.run(Repo, [{0, Migration0}], :up, all: true, log_migrations_sql: :info)

    hackers = [
      %{id: 1, name: "Alice"},
      %{id: 2, name: "Bob"},
      %{id: 3, name: "Charlie"},
      %{id: 4, name: "David"},
      %{id: 5, name: "Eve"}
    ]

    challenges = [
      %{id: 1, hacker_id: Enum.random(1..5)},
      %{id: 2, hacker_id: Enum.random(1..5)},
      %{id: 3, hacker_id: Enum.random(1..5)},
      %{id: 4, hacker_id: Enum.random(1..5)},
      %{id: 5, hacker_id: Enum.random(1..5)},
      %{id: 6, hacker_id: Enum.random(1..5)},
      %{id: 7, hacker_id: Enum.random(1..5)},
      %{id: 8, hacker_id: Enum.random(1..5)},
      %{id: 9, hacker_id: Enum.random(1..5)},
      %{id: 10, hacker_id: Enum.random(1..5)},
      %{id: 11, hacker_id: Enum.random(1..5)},
      %{id: 12, hacker_id: Enum.random(1..5)},
      %{id: 13, hacker_id: Enum.random(1..5)},
      %{id: 14, hacker_id: Enum.random(1..5)},
      %{id: 15, hacker_id: Enum.random(1..5)},
      %{id: 16, hacker_id: Enum.random(1..5)},
      %{id: 17, hacker_id: Enum.random(1..5)},
      %{id: 18, hacker_id: Enum.random(1..5)},
      %{id: 19, hacker_id: Enum.random(1..5)},
      %{id: 20, hacker_id: Enum.random(1..5)},
    ]

    Enum.each(hackers, fn attrs ->
      Repo.insert!(struct(Hacker, attrs), on_conflict: :nothing, conflict_target: [:id])
    end)

    Enum.each(challenges, fn attrs ->
      Repo.insert!(struct(Challenge, attrs), on_conflict: :nothing, conflict_target: [:id])
    end)

    Repo.all(from(h in Hacker, select: h))
    |> Enum.map(&Map.take(&1, [:id, :name]))
    |> IO.inspect(label: "hackers")
    
    Repo.all(from(c in Challenge, select: c))
    |> Enum.map(&Map.take(&1, [:id, :hacker_id]))
    |> IO.inspect(label: "challenges")


    challenge_counts_query =
      from h in Hacker,
        join: c in Challenge, on: h.id == c.hacker_id,
        distinct: true,
        select: %{
          hacker_id: h.id,
          name: h.name,
          num_challenges: count(c.id) |> over(partition_by: c.hacker_id)
        }

    max_challenge_count_query =
      from cc in subquery(challenge_counts_query),
        select: max(cc.num_challenges)

    duplicate_query =
      from cc in subquery(challenge_counts_query),
        group_by: cc.num_challenges,
        having: count(cc.hacker_id) > 1,
        select: cc.num_challenges

    final_query =
      from cc in subquery(challenge_counts_query),
        where: cc.num_challenges == subquery(max_challenge_count_query) or
               cc.num_challenges not in subquery(duplicate_query),
        order_by: [desc: cc.num_challenges, asc: cc.hacker_id]

    Repo.all(final_query)
    |> dbg()

    # You will get an answer like this:
    # [
    #   %{name: "Alice", hacker_id: 1, num_challenges: 6},
    #   %{name: "Charlie", hacker_id: 3, num_challenges: 6},
    #   %{name: "Bob", hacker_id: 2, num_challenges: 2}
    # ]
    # (Note: Your individual answer may vary becasue of Enum.random())

  end
end

Main.main()
