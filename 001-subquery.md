# Ecto Subquery Example

Today we are going to explore how to use Ecto to perform a common SQL operation as taken from hacker rank.
The problem can be found here: [Hacker Rank Challenges](https://www.hackerrank.com/challenges/challenges/problem)

The sql query solution can be found here: [mssql-solution](https://dev.to/ranggakd/challenges-hackerrank-mssql-dop)

Ensure postgres is running on your local machine & create an environment variable for your database url.
It should look something like this: `DATABASE_URL=ecto://postgres:postgres@localhost:5432/local_db`

Or you can just substitute for your db url without defining an environment variable, whatever suits you.

To beign, we first create a basic setup for our database.
You can find how to do that from this repo: [Local Ecto Setup](https://github.com/wojtekmach/mix_install_examples/blob/main/ecto_sql.exs)

```elixir
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
```

We then create a migration to create our `hackers` and `challenges` tables.

```elixir
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
```

We then create our schemas for our `hackers` and `challenges`.

```elixir
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
```

We then create our main module to perform our operations.

```elixir
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


    # Subquery to count the number of challenges for each hacker
    challenge_counts_query =
      from h in Hacker,
        join: c in Challenge, on: h.id == c.hacker_id,
        distinct: true,
        select: %{
          hacker_id: h.id,
          name: h.name,
          num_challenges: count(c.id) |> over(partition_by: c.hacker_id)
        }


    # Subquery to find the maximum number of challenges
    max_challenge_count_query =
      from cc in subquery(challenge_counts_query),
        select: max(cc.num_challenges)


    # Subquery to find the number of hackers with duplicate challenge counts
    duplicate_query =
      from cc in subquery(challenge_counts_query),
        group_by: cc.num_challenges,
        having: count(cc.hacker_id) > 1,
        select: cc.num_challenges


    # Final query to get the hackers with the maximum number of challenges or those with unique challenge counts
    final_query =
      from cc in subquery(challenge_counts_query),
        where: cc.num_challenges == subquery(max_challenge_count_query) or
               cc.num_challenges not in subquery(duplicate_query),
        order_by: [desc: cc.num_challenges, asc: cc.hacker_id]


    # Execute the final query and view the results
    Repo.all(final_query)
    |> dbg()

  end
end

Main.main()
```

You will get an answer like this:

```elixir
[
  %{name: "Alice", hacker_id: 1, num_challenges: 6},
  %{name: "Charlie", hacker_id: 3, num_challenges: 6},
  %{name: "Bob", hacker_id: 2, num_challenges: 2}
]
```

(Note: Your individual answer may vary becasue of `Enum.random()`, but now you get a general idea of how to use subqueries in Ecto.)

