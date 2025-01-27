defmodule Lexical.RemoteControl.Search.StoreTest do
  alias Lexical.RemoteControl.Dispatch
  alias Lexical.RemoteControl.Search.Store
  alias Lexical.RemoteControl.Search.Store.Backends.Ets
  alias Lexical.Test.Entry
  alias Lexical.Test.EventualAssertions
  alias Lexical.Test.Fixtures

  use ExUnit.Case

  import Entry.Builder
  import EventualAssertions
  import Fixtures

  @backends [Ets]

  setup_all do
    project = project()
    Lexical.RemoteControl.set_project(project)
    # These test cases require an clean slate going into them
    # so we should remove the indexes once when the tests start,
    # and again when tests end, so the next test has a clean slate.
    # Removing the index at the end will also let other test cases
    # start with a clean slate.

    destroy_backends(project)

    on_exit(fn ->
      destroy_backends(project)
    end)

    {:ok, project: project}
  end

  for backend <- @backends,
      backend_name = backend |> Module.split() |> List.last() do
    describe "#{backend_name} :: replace/1" do
      setup %{project: project} do
        with_a_started_store(project, unquote(backend))
      end

      test "replaces the entire index" do
        entries = [definition(subject: OtherModule)]

        Store.replace(entries)
        assert entries == Store.all()
      end
    end

    describe "#{backend_name} :: querying" do
      setup %{project: project} do
        with_a_started_store(project, unquote(backend))
      end

      test "matching can exclude on type" do
        Store.replace([
          definition(id: 1),
          reference(id: 3)
        ])

        assert {:ok, [ref]} = Store.exact(subtype: :reference)
        assert ref.subtype == :reference
      end

      test "matching with queries can exclude on type" do
        Store.replace([
          reference(subject: Foo.Bar.Baz),
          reference(subject: Other.Module),
          definition(subject: Foo.Bar.Baz)
        ])

        assert {:ok, [ref]} = Store.exact("Foo.Bar.Baz", subtype: :reference)

        assert ref.subject == Foo.Bar.Baz
        assert ref.type == :module
        assert ref.subtype == :reference
      end

      test "matching exact tokens should work" do
        Store.replace([
          definition(id: 1, subject: Foo.Bar.Baz),
          definition(id: 2, subject: Foo.Bar.Bak)
        ])

        assert {:ok, [entry]} = Store.exact("Foo.Bar.Baz", type: :module, subtype: :definition)

        assert entry.subject == Foo.Bar.Baz
        assert entry.id == 1
      end

      test "matching fuzzy tokens works" do
        Store.replace([
          definition(id: 1, subject: Foo.Bar.Baz),
          definition(id: 2, subject: Foo.Bar.Bak),
          definition(id: 3, subject: Bad.Times.Now)
        ])

        assert {:ok, [entry_1, entry_2]} =
                 Store.fuzzy("Foo.Bar.B", type: :module, subtype: :definition)

        assert entry_1.subject in [Foo.Bar.Baz, Foo.Bar.Bak]
        assert entry_2.subject in [Foo.Bar.Baz, Foo.Bar.Bak]
      end
    end

    describe "#{backend_name} :: updating entries in a file" do
      setup %{project: project} do
        with_a_started_store(project, unquote(backend))
      end

      test "old entries with the same path are deleted" do
        path = "/path/to/file.ex"

        Store.replace([
          definition(id: 1, subject: Foo.Bar.Baz, path: path),
          definition(id: 2, subject: Foo.Baz.Quux, path: path)
        ])

        updated = [
          definition(id: 3, subject: Other.Thing.Entirely, path: path)
        ]

        Store.update(path, updated)

        assert_eventually [remaining] = Store.all()
        refute remaining.id in [1, 2]
      end

      test "old entries with another path are kept" do
        updated_path = "/path/to/file.ex"

        Store.replace([
          definition(id: 1, subject: Foo.Bar.Baz, path: updated_path),
          definition(id: 2, subject: Foo.Bar.Baz.Quus, path: updated_path),
          definition(id: 3, subject: Foo.Bar.Baz, path: "/path/to/another.ex")
        ])

        updated = [
          definition(id: 4, subject: Other.Thing.Entirely, path: updated_path)
        ]

        Store.update(updated_path, updated)

        assert_eventually [first, second] = Store.all()

        assert first.id in [3, 4]
        assert second.id in [3, 4]
      end

      test "updated entries are not searchable" do
        path = "/path/to/ex.ex"

        Store.replace([
          reference(id: 1, subject: Should.Be.Replaced, path: path)
        ])

        Store.update(path, [
          reference(id: 2, subject: Present, path: path)
        ])

        assert_eventually {:ok, [found]} = Store.fuzzy("Pres", type: :module, subtype: :reference)
        assert found.id == 2
        assert found.subject == Present
      end
    end
  end

  defp after_each_test(_, _) do
    :ok
  end

  defp destroy_backends(project) do
    Enum.each(@backends, &destroy_backend(&1, project))
  end

  defp destroy_backend(Ets, project) do
    Ets.destroy(project)
  end

  defp default_create(_project) do
    {:ok, []}
  end

  defp default_update(_project, _entities) do
    {:ok, [], []}
  end

  defp with_a_started_store(project, backend) do
    start_supervised!(Dispatch)
    start_supervised!({Store, [project, &default_create/1, &default_update/2, backend]})
    Store.enable()
    assert_eventually ready?(), 1500

    on_exit(fn ->
      after_each_test(backend, project)
    end)

    {:ok, backend: backend}
  end

  def ready? do
    alive?() and Store.loaded?()
  end

  def alive? do
    case Process.whereis(Store) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end
end
