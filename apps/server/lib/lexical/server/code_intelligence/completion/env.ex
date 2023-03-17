defmodule Lexical.Server.CodeIntelligence.Completion.Env do
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile

  defstruct [:project, :document, :context, :prefix, :suffix, :position, :words]

  def new(
        %Project{} = project,
        %SourceFile{} = document,
        %Position{} = cursor_position,
        %Completion.Context{} = context
      ) do
    with {:ok, line} <- SourceFile.fetch_text_at(document, cursor_position.line) do
      graphemes = String.graphemes(line)
      prefix = graphemes |> Enum.take(cursor_position.character) |> IO.iodata_to_binary()
      suffix = String.slice(line, cursor_position.character..-1)
      words = String.split(prefix)

      {:ok,
       %__MODULE__{
         project: project,
         document: document,
         prefix: prefix,
         suffix: suffix,
         position: cursor_position,
         words: words,
         context: context
       }}
    else
      _ ->
        {:error, :out_of_bounds}
    end
  end

  def struct_reference?(%__MODULE__{} = env) do
    with {:ok, line} <- SourceFile.fetch_text_at(env.document, env.position.line) do
      fragment = String.slice(line, 0..(env.position.character - 1))

      case Code.Fragment.cursor_context(fragment) do
        {:struct, _} ->
          true

        {:local_or_var, '__'} ->
          # a reference to `%__MODULE`, often in a function head, as in
          # def foo(%__)
          String.contains?(line, "%__")

        _ ->
          false
      end
    else
      _ ->
        false
    end
  end

  def empty?("") do
    true
  end

  def empty?(string) when is_binary(string) do
    String.trim(string) == ""
  end

  def last_word(%__MODULE__{} = env) do
    List.last(env.words)
  end
end