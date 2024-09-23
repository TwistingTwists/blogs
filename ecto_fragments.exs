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

defmodule Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, otp_app: :foo
end

Application.put_env(:foo, Repo,
  show_sensitive_data_on_connection_error: true,
  pool_size: 3,
  url: database_url
)

defmodule Types.TsRange do
  @behaviour Ecto.Type

  def type, do: :tsrange

  def cast(%Postgrex.Range{lower: lower, upper: upper}) do
    {:ok, %Postgrex.Range{lower: lower, upper: upper}}
  end

  def cast(%{lower: lower, upper: upper} = map) when is_map(map) do
    if valid_datetime?(lower) and valid_datetime?(upper) do
      {:ok, %Postgrex.Range{lower: lower, upper: upper}}
    else
      :error
    end
  end

  def cast(_), do: :error

  def load(%Postgrex.Range{lower: lower, upper: upper}) do
    {:ok, %{lower: lower, upper: upper}}
  end

  def load(_), do: :error

  def dump(%{lower: lower, upper: upper}) do
    {:ok, %Postgrex.Range{lower: lower, upper: upper}}
  end

  def dump(_), do: :error

  def embed_as(_format), do: :self

  def equal?(%Postgrex.Range{lower: lower1, upper: upper1}, %Postgrex.Range{
        lower: lower2,
        upper: upper2
      }) do
    lower1 == lower2 and upper1 == upper2
  end

  defp valid_datetime?(value) do
    is_struct(value, DateTime) or is_struct(value, NaiveDateTime)
  end
end

defmodule Migration2 do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:title, :string)
      add(:description, :text)
      add(:start_time, :utc_datetime)
      add(:end_time, :utc_datetime)
      add(:duration, :tsrange)
      timestamps()
    end

    create table(:users, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:name, :string)
      timestamps()
    end

    create table(:user_events, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:user_id, references(:users, on_delete: :nothing))
      add(:event_id, references(:events, on_delete: :nothing))
      timestamps()
    end

    create(unique_index(:user_events, [:user_id, :event_id]))
  end
end

defmodule Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field(:title, :string)
    field(:description, :string)
    field(:start_time, :utc_datetime)
    field(:end_time, :utc_datetime)
    field(:duration, Types.TsRange)
    has_many(:user_events, UserEvent)
    has_many(:users, through: [:user_events, :user])
    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :description, :start_time, :end_time, :duration])
    |> validate_required([:title, :start_time, :end_time])
    |> validate_change(:duration, fn _, value ->
      if value && value.start_time < value.end_time do
        []
      else
        [duration: "must be a valid timestamp range"]
      end
    end)
  end
end

defmodule User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field(:name, :string)
    has_many(:user_events, UserEvent)
    has_many(:events, through: [:user_events, :event])
    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end

defmodule UserEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_events" do
    belongs_to(:user, MyApp.User)
    belongs_to(:event, MyApp.Event)
    timestamps()
  end

  @doc false
  def changeset(user_event, attrs) do
    user_event
    |> cast(attrs, [:user_id, :event_id])
    |> validate_required([:user_id, :event_id])
  end
end

defmodule Main do
  import Ecto.Query, warn: false

  def events_ranked_by_duration() do
    query =
      from(
        e in subquery(
          from(e in Event,
            select: %{
              id: e.id,
              title: e.title,
              duration: fragment("extract(epoch from age(?))", e.end_time)
            }
          )
        ),
        select: %{
          id: e.id,
          title: e.title,
          duration: e.duration,
          rank: fragment("rank() over (order by ? desc)", e.duration)
        }
      )

    Repo.all(query)
  end

  def events_overlapping(start_time, end_time) do
    query =
      from(e in Event,
        where: fragment("? && tsrange(?, ?)", e.duration, ^start_time, ^end_time)
      )

    Repo.all(query)
  end

  def events_ranked_by_duration_2() do
    subquery =
      from(e in Event,
        select: %{
          id: e.id,
          duration: fragment("extract(epoch from (? - ?))", e.end_time, e.start_time)
        }
      )

    query =
      from(e in subquery(subquery),
        select: %{
          id: e.id,
          duration: e.duration,
          rank: fragment("rank() over (order by ? desc)", e.duration)
        }
      )

    Repo.all(query)
  end

  def events_longer_than_average_duration() do
    avg_duration_subquery =
      from(e in Event,
        select: fragment("avg(extract(epoch from (? - ?)))", e.end_time, e.start_time)
      )

    query =
      from(e in Event,
        where:
          fragment("extract(epoch from (? - ?))", e.end_time, e.start_time) >
            subquery(avg_duration_subquery),
        select: e
      )

    Repo.all(query)
  end

  # Define a macro to calculate the duration in hours between start_time and end_time
  defmacro duration_in_hours(start_time, end_time) do
    quote do
      fragment("EXTRACT(EPOCH FROM (? - ?)) / 3600", unquote(start_time), unquote(end_time))
    end
  end

  # Query to get events with their durations in hours
  def events_with_duration_in_hours() do
    query =
      from(e in Event,
        select: %{
          id: e.id,
          title: e.title,
          duration_hours: duration_in_hours(e.start_time, e.end_time)
        }
      )

    Repo.all(query)
  end

  def main do
    Repo.__adapter__().storage_down(Repo.config())
    :ok = Repo.__adapter__().storage_up(Repo.config())
    {:ok, _} = Supervisor.start_link([Repo], strategy: :one_for_one)
    Ecto.Migrator.run(Repo, [{2, Migration2}], :up, all: true, log_migrations_sql: :info)

    # Insert Users
    user1 = %User{name: "Alice"}
    user2 = %User{name: "Bob"}
    user3 = %User{name: "Charlie"}

    {:ok, user1} = Repo.insert(user1)
    {:ok, user2} = Repo.insert(user2)
    {:ok, user3} = Repo.insert(user3)

    # Insert Events
    event1 = %Event{
      title: "Conference",
      description: "Annual tech conference",
      start_time: ~U[2024-09-10T09:00:00Z],
      end_time: ~U[2024-09-10T17:00:00Z],
      duration: %Postgrex.Range{lower: ~U[2024-09-10T09:00:00Z], upper: ~U[2024-09-10T17:00:00Z]}
    }

    event2 = %Event{
      title: "Workshop",
      description: "Hands-on coding workshop",
      start_time: ~U[2024-09-11T10:00:00Z],
      end_time: ~U[2024-09-11T15:00:00Z],
      duration: %Postgrex.Range{lower: ~U[2024-09-11T10:00:00Z], upper: ~U[2024-09-11T15:00:00Z]}
    }

    event3 = %Event{
      title: "Networking Event",
      description: "Networking with industry professionals",
      start_time: ~U[2024-09-12T18:00:00Z],
      end_time: ~U[2024-09-12T20:00:00Z],
      duration: %Postgrex.Range{lower: ~U[2024-09-12T18:00:00Z], upper: ~U[2024-09-12T20:00:00Z]}
    }

    {:ok, event1} = Repo.insert(event1)
    {:ok, event2} = Repo.insert(event2)
    {:ok, event3} = Repo.insert(event3)

    # Insert UserEvents
    user_event1 = %UserEvent{user_id: user1.id, event_id: event1.id}
    user_event2 = %UserEvent{user_id: user2.id, event_id: event1.id}
    user_event3 = %UserEvent{user_id: user1.id, event_id: event2.id}
    user_event4 = %UserEvent{user_id: user3.id, event_id: event3.id}

    {:ok, _user_event1} = Repo.insert(user_event1)
    {:ok, _user_event2} = Repo.insert(user_event2)
    {:ok, _user_event3} = Repo.insert(user_event3)
    {:ok, _user_event4} = Repo.insert(user_event4)

    # Call functions & inspect their vlaues using dbg
    events_ranked_by_duration() |> dbg()
    events_overlapping(~U[2024-09-10T09:00:00Z], ~U[2024-09-10T17:00:00Z]) |> dbg()
    events_ranked_by_duration_2() |> dbg()
    events_longer_than_average_duration() |> dbg()
    events_with_duration_in_hours() |> dbg()
  end
end

Main.main()
