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

defmodule Migration1 do
  use Ecto.Migration

  def change do
    create table("posts", primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:title, :string)
      add(:content, :text)
    end
    create table("comments", primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:post_id, references(:posts, on_delete: :nothing), null: false)
      add(:content, :text)
    end
  end
end

defmodule Post do
  use Ecto.Schema

  schema "posts" do
    field(:title, :string)
    field(:content, :string)
    has_many :comments, Comment
  end
end

defmodule Comment do
  use Ecto.Schema

  schema "comments" do
    field(:content, :string)
    belongs_to :post, Post
  end
end

defmodule Main do
  import Ecto.Query, warn: false

  def main do
    Repo.__adapter__().storage_down(Repo.config())
    :ok = Repo.__adapter__().storage_up(Repo.config())
    {:ok, _} = Supervisor.start_link([Repo], strategy: :one_for_one)
    Ecto.Migrator.run(Repo, [{1, Migration1}], :up, all: true, log_migrations_sql: :info)

    posts = [
      %{id: 1, title: "First Post", content: "This is the first post."},
      %{id: 2, title: "Second Post", content: "This is the second post."},
      %{id: 3, title: "Third Post", content: "This is the third post."}
    ]

    # comments = [
    #   %{id: 1, post_id: Enum.random(1..3), content: "Great post!"},
    #   %{id: 2, post_id: Enum.random(1..3), content: "Interesting read."},
    #   %{id: 3, post_id: Enum.random(1..3), content: "I learned something new."},
    #   %{id: 4, post_id: Enum.random(1..3), content: "how r u."},
    #   %{id: 5, post_id: Enum.random(1..3), content: "Crap post"},
    #   %{id: 6, post_id: Enum.random(1..3), content: "Heya"},
    #   %{id: 7, post_id: Enum.random(1..3), content: "First"},
    #   %{id: 8, post_id: Enum.random(1..3), content: "Yt algo, thnx"},
    #   %{id: 9, post_id: Enum.random(1..3), content: "stock trading"},
    #   %{id: 10, post_id: Enum.random(1..3), content: "I am a bot"},
    #   %{id: 11, post_id: Enum.random(1..3), content: "I am a bot"},
    #   %{id: 12, post_id: Enum.random(1..3), content: "I am a bot"},
    #   %{id: 13, post_id: Enum.random(1..3), content: "I am NOT a bot"},
    #   %{id: 14, post_id: Enum.random(1..3), content: "I too am NOT a bot"},
    #   %{id: 15, post_id: Enum.random(1..3), content: "I too am definitely NOT a bot"},
    #   %{id: 16, post_id: Enum.random(1..3), content: "hello from siberia"},
    #   %{id: 17, post_id: Enum.random(1..3), content: "Tiger woods"},
    # ]

    comments = [
      %{id: 1, post_id: 1, content: "Great post!"},
      %{id: 2, post_id: 1, content: "Interesting read."},
      %{id: 3, post_id: 1, content: "I learned something new."},
      %{id: 4, post_id: 2, content: "how r u."},
      %{id: 5, post_id: 2, content: "Crap post"},
      %{id: 6, post_id: 2, content: "Heya"},
      %{id: 7, post_id: 3, content: "First"},
      %{id: 8, post_id: 3, content: "Yt algo, thnx"},
      %{id: 9, post_id: 3, content: "stock trading"},
      %{id: 10, post_id: 1, content: "I am a bot"},
      %{id: 11, post_id: 1, content: "I am a bot"},
      %{id: 12, post_id: 1, content: "I am a bot"},
      %{id: 13, post_id: 2, content: "I am NOT a bot"},
      %{id: 14, post_id: 2, content: "I too am NOT a bot"},
      %{id: 15, post_id: 2, content: "I too am definitely NOT a bot"},
      %{id: 16, post_id: 3, content: "hello from siberia"},
      %{id: 17, post_id: 3, content: "Tiger woods"},
    ]

    Enum.each(posts, fn attrs ->
      Repo.insert!(struct(Post, attrs), on_conflict: :nothing, conflict_target: [:id])
    end)

    Enum.each(comments, fn attrs ->
      Repo.insert!(struct(Comment, attrs), on_conflict: :nothing, conflict_target: [:id])
    end)

    Repo.all(from(p in Post, select: p))
    |> Enum.map(&Map.take(&1, [:id, :title, :content]))
    |> IO.inspect(label: "posts")

    Repo.all(from(c in Comment, select: c))
    |> Enum.map(&Map.take(&1, [:id, :post_id, :content]))
    |> IO.inspect(label: "comments")

    # Define a child query to find comments related to posts
    child_query = from c in Comment,
      # where: ilike(c.content, "%bot%") and ilike(c.content, "%not%"),
      where: parent_as(:posts).id == c.post_id and ilike(c.content, "%bot%") and ilike(c.content, "%not%"),
      select: c

    # Main query to find posts with comments that arent bots
    posts_with_bot_comments =
      from p in Post,
        as: :posts,
        inner_lateral_join: c in subquery(child_query),
        on: p.id == c.post_id,
        select: %{
          post_id: p.id,
          title: p.title,
          content: p.content,
          comment: c.content
        }

    Repo.all(posts_with_bot_comments) |> IO.inspect(label: "posts_with_bot_comments")

    # 3. All posts that have the same comments
    posts_with_same_comments =
      from(p in Post,
        join: c in Comment, on: c.post_id == p.id,
        group_by: p.id,
        having: count(c.id) > 1,
        select: %{post_id: p.id, title: p.title, content: p.content, comment_count: count(c.id)}
      )

    Repo.all(posts_with_same_comments) |> IO.inspect(label: "posts_with_same_comments")

    # All posts & their respective comments along with their comments count
    posts_with_comments_count =
      from(p in Post,
        as: :posts,
        inner_lateral_join: c in subquery(
          from(c in Comment,
            group_by: c.post_id,
            select: %{
              post_id: c.post_id,
              comment_count: count(c.id)
            }
          )
        ),
        on: p.id == c.post_id,
        select: %{
          post_id: p.id,
          title: p.title,
          content: p.content,
          comment_count: c.comment_count
        }
      )

    Repo.all(posts_with_comments_count) |> IO.inspect(label: "posts_with_comments_count")
  end
end

Main.main()
